#!/bin/bash

# =============================================
# Resource Management Module
# Berisi fungsi-fungsi untuk monitoring dan optimasi resource
# =============================================

# Load dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Fungsi untuk mendapatkan resource sistem saat ini
get_system_resources() {
    local total_memory_mb=$(free -m | awk 'NR==2{print $2}')
    local available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    local total_cpu_cores=$(nproc)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    # Hitung resource yang bisa digunakan (setelah safety margin)
    local usable_memory_mb=$(($total_memory_mb * (100 - $MEMORY_SAFETY_MARGIN) / 100))
    local usable_cpu_cores=$(echo "$total_cpu_cores * (100 - $CPU_SAFETY_MARGIN) / 100" | bc -l)

    echo "$total_memory_mb $available_memory_mb $total_cpu_cores $cpu_usage $usable_memory_mb $usable_cpu_cores"
}

# Fungsi untuk menghitung penggunaan resource aplikasi
get_app_resource_usage() {
    local total_apps=0
    local total_threads=0
    local total_memory_used=0
    local total_instances=0

    # Hitung aplikasi utama
    for config in $CONFIG_DIR/*.conf; do
        if [ -f "$config" ]; then
            source "$config"
            total_apps=$((total_apps + 1))

            # Hitung threads dari Caddyfile jika ada
            if [ -f "$APP_DIR/Caddyfile" ]; then
                local app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
                total_threads=$((total_threads + app_threads))
                total_memory_used=$((total_memory_used + (app_threads * THREAD_MEMORY_USAGE)))
            fi

            # Hitung scaled instances
            for service in /etc/systemd/system/frankenphp-$APP_NAME-*.service; do
                if [ -f "$service" ]; then
                    total_instances=$((total_instances + 1))
                    total_threads=$((total_threads + app_threads))
                    total_memory_used=$((total_memory_used + (app_threads * THREAD_MEMORY_USAGE)))
                fi
            done
        fi
    done

    echo "$total_apps $total_threads $total_memory_used $total_instances"
}

# Fungsi untuk menghitung smart thread allocation
calculate_smart_threads() {
    local base_threads=$1
    local existing_apps=$2
    local total_memory_mb=$3
    local available_memory_mb=$4
    local total_cpu_cores=$5

    local smart_threads=$base_threads

    # Kurangi threads berdasarkan jumlah aplikasi yang ada
    if [ $existing_apps -gt 0 ]; then
        # Hitung resource per app
        local memory_per_app=$(($total_memory_mb / ($existing_apps + 1)))
        local cpu_per_app=$(echo "$total_cpu_cores / ($existing_apps + 1)" | bc -l)

        # Sesuaikan threads berdasarkan memory constraint
        local max_threads_by_memory=$(($memory_per_app / $THREAD_MEMORY_USAGE))
        if [ $max_threads_by_memory -lt $smart_threads ]; then
            smart_threads=$max_threads_by_memory
        fi

        # Sesuaikan threads berdasarkan CPU constraint
        local max_threads_by_cpu=$(echo "$cpu_per_app * 2" | bc -l | cut -d'.' -f1)
        if [ $max_threads_by_cpu -lt $smart_threads ]; then
            smart_threads=$max_threads_by_cpu
        fi

        # Terapkan scaling factor berdasarkan jumlah app
        if [ $existing_apps -ge 5 ]; then
            smart_threads=$((smart_threads * 70 / 100))  # 30% reduction untuk 5+ apps
        elif [ $existing_apps -ge 3 ]; then
            smart_threads=$((smart_threads * 80 / 100))  # 20% reduction untuk 3-4 apps
        elif [ $existing_apps -ge 1 ]; then
            smart_threads=$((smart_threads * 90 / 100))  # 10% reduction untuk 1-2 apps
        fi
    fi

    # Pastikan minimum viable threads
    if [ $smart_threads -lt 2 ]; then
        smart_threads=2
    fi

    echo $smart_threads
}

# Fungsi untuk pre-flight resource check
preflight_resource_check() {
    local app_name=$1
    local github_repo=$2

    log_info "🔍 Menjalankan pre-flight resource check untuk $app_name..."

    # Dapatkan resource sistem saat ini
    local resources=($(get_system_resources))
    local total_memory_mb=${resources[0]}
    local available_memory_mb=${resources[1]}
    local total_cpu_cores=${resources[2]}
    local cpu_usage=${resources[3]}
    local usable_memory_mb=${resources[4]}
    local usable_cpu_cores=${resources[5]}

    # Dapatkan penggunaan resource aplikasi saat ini
    local usage=($(get_app_resource_usage))
    local existing_apps=${usage[0]}
    local total_threads=${usage[1]}
    local total_memory_used=${usage[2]}
    local total_instances=${usage[3]}

    # Cek hard limits
    if [ $existing_apps -ge $MAX_APPS_PER_SERVER ]; then
        log_error "❌ Hard limit tercapai: Maksimal $MAX_APPS_PER_SERVER apps per server"
        log_error "   Aplikasi saat ini: $existing_apps"
        log_error "   Silakan scale horizontal atau hapus aplikasi yang tidak digunakan"
        return 1
    fi

    # Cek ketersediaan memory
    local estimated_memory_needed=$(($MIN_MEMORY_PER_APP))
    if [ $available_memory_mb -lt $estimated_memory_needed ]; then
        log_error "❌ Memory tidak mencukupi"
        log_error "   Tersedia: ${available_memory_mb}MB"
        log_error "   Dibutuhkan: ${estimated_memory_needed}MB"
        log_error "   Sedang digunakan: ${total_memory_used}MB"
        return 1
    fi

    # Cek ketersediaan CPU
    local cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)
    if [ $cpu_usage_int -gt 80 ]; then
        log_error "❌ CPU usage tinggi terdeteksi: ${cpu_usage}%"
        log_error "   Tunggu hingga CPU usage menurun sebelum membuat app baru"
        return 1
    fi

    # Hitung smart threads untuk app baru
    local smart_threads=$(calculate_smart_threads $(calculate_optimal_threads) $existing_apps $total_memory_mb $available_memory_mb $total_cpu_cores)

    # Sistem warning
    local memory_usage_percent=$(($total_memory_used * 100 / $total_memory_mb))
    local projected_memory_usage=$(($total_memory_used + ($smart_threads * $THREAD_MEMORY_USAGE)))
    local projected_memory_percent=$(($projected_memory_usage * 100 / $total_memory_mb))

    # Warning untuk memory
    if [ $projected_memory_percent -gt 80 ]; then
        log_warning "⚠️  Proyeksi penggunaan memory tinggi: ${projected_memory_percent}%"
        log_warning "   Pertimbangkan untuk mengurangi thread count atau scale horizontal"
    elif [ $projected_memory_percent -gt 70 ]; then
        log_warning "⚠️  Proyeksi penggunaan memory sedang: ${projected_memory_percent}%"
    fi

    # Warning untuk jumlah app
    if [ $existing_apps -ge 7 ]; then
        log_warning "⚠️  Jumlah aplikasi tinggi: $existing_apps apps"
        log_warning "   Pertimbangkan untuk konsolidasi atau scale horizontal"
    elif [ $existing_apps -ge 5 ]; then
        log_warning "⚠️  Jumlah aplikasi sedang: $existing_apps apps"
    fi

    # Sukses - tampilkan alokasi resource
    log_info "✅ Pre-flight check berhasil!"
    log_info "📊 Alokasi resource untuk $app_name:"
    log_info "   🧵 Threads: $smart_threads (dioptimasi untuk $existing_apps aplikasi yang ada)"
    log_info "   💾 Memory: ~$(($smart_threads * $THREAD_MEMORY_USAGE))MB"
    log_info "   📈 Proyeksi total penggunaan memory: ${projected_memory_percent}%"
    log_info "   🏗️  Total apps setelah dibuat: $((existing_apps + 1))"

    # Simpan smart threads untuk digunakan nanti
    export SMART_THREADS=$smart_threads
    return 0
}

# Fungsi untuk menampilkan warning resource
display_resource_warnings() {
    local resources=($(get_system_resources))
    local total_memory_mb=${resources[0]}
    local available_memory_mb=${resources[1]}
    local total_cpu_cores=${resources[2]}
    local cpu_usage=${resources[3]}

    local usage=($(get_app_resource_usage))
    local existing_apps=${usage[0]}
    local total_memory_used=${usage[2]}

    local memory_usage_percent=$(($total_memory_used * 100 / $total_memory_mb))
    local cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)

    if [ $memory_usage_percent -gt 80 ] || [ $cpu_usage_int -gt 80 ] || [ $existing_apps -gt 7 ]; then
        log_warning "⚠️  Warning resource server:"
        if [ $memory_usage_percent -gt 80 ]; then
            log_warning "   💾 Penggunaan memory tinggi: ${memory_usage_percent}%"
        fi
        if [ $cpu_usage_int -gt 80 ]; then
            log_warning "   🔥 Penggunaan CPU tinggi: ${cpu_usage}%"
        fi
        if [ $existing_apps -gt 7 ]; then
            log_warning "   📱 Jumlah aplikasi tinggi: $existing_apps apps"
        fi
        log_warning "   💡 Pertimbangkan untuk scale horizontal atau optimasi resource"
    fi
}

# Fungsi untuk monitoring resource server
monitor_server_resources() {
    log_header "🖥️  MONITOR RESOURCE SERVER"
    log_header "=========================="
    echo ""

    # Dapatkan resource sistem
    local resources=($(get_system_resources))
    local total_memory_mb=${resources[0]}
    local available_memory_mb=${resources[1]}
    local total_cpu_cores=${resources[2]}
    local cpu_usage=${resources[3]}
    local usable_memory_mb=${resources[4]}
    local usable_cpu_cores=${resources[5]}

    # Dapatkan penggunaan resource app
    local usage=($(get_app_resource_usage))
    local existing_apps=${usage[0]}
    local total_threads=${usage[1]}
    local total_memory_used=${usage[2]}
    local total_instances=${usage[3]}

    # Hitung persentase
    local memory_usage_percent=$(($total_memory_used * 100 / $total_memory_mb))
    local cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)
    local available_memory_percent=$(($available_memory_mb * 100 / $total_memory_mb))

    # Tampilkan overview sistem
    log_header "📊 OVERVIEW SISTEM"
    echo "🔧 Total CPU Cores: $total_cpu_cores"
    echo "💾 Total Memory: ${total_memory_mb}MB"
    echo "⚡ Penggunaan CPU saat ini: ${cpu_usage}%"
    echo "🆓 Memory tersedia: ${available_memory_mb}MB (${available_memory_percent}%)"
    echo ""

    # Tampilkan penggunaan resource
    log_header "📈 PENGGUNAAN RESOURCE"
    echo "🏗️  Total Apps: $existing_apps"
    echo "📱 Total Instances: $total_instances"
    echo "🧵 Total Threads: $total_threads"
    echo "💾 Estimasi Memory digunakan: ${total_memory_used}MB (${memory_usage_percent}%)"
    echo ""

    # Analisis kapasitas
    log_header "🎯 ANALISIS KAPASITAS"
    local remaining_apps=$((MAX_APPS_PER_SERVER - existing_apps))
    echo "📱 Slot app tersisa: $remaining_apps / $MAX_APPS_PER_SERVER"

    # Hitung potensi app baru berdasarkan memory
    local potential_memory_apps=$(($available_memory_mb / MIN_MEMORY_PER_APP))
    echo "💾 Potensi Apps (Memory): $potential_memory_apps"

    # Hitung potensi app baru berdasarkan threads
    local max_threads_remaining=$(($total_cpu_cores * 2 - $total_threads))
    local potential_thread_apps=$(($max_threads_remaining / 2))
    echo "🧵 Potensi Apps (Threads): $potential_thread_apps"

    # Tampilkan faktor pembatas
    local limiting_factor
    local potential_apps
    if [ $remaining_apps -le $potential_memory_apps ] && [ $remaining_apps -le $potential_thread_apps ]; then
        limiting_factor="Hard Limit"
        potential_apps=$remaining_apps
    elif [ $potential_memory_apps -le $potential_thread_apps ]; then
        limiting_factor="Memory"
        potential_apps=$potential_memory_apps
    else
        limiting_factor="CPU/Threads"
        potential_apps=$potential_thread_apps
    fi

    echo "🎯 Faktor Pembatas: $limiting_factor"
    echo "⚡ Estimasi App Baru yang Mungkin: $potential_apps"
    echo ""

    # Indikator status
    log_header "🚦 INDIKATOR STATUS"
    if [ $memory_usage_percent -lt 50 ]; then
        echo -e "💾 Penggunaan Memory: ${GREEN}RENDAH${NC} (${memory_usage_percent}%)"
    elif [ $memory_usage_percent -lt 70 ]; then
        echo -e "💾 Penggunaan Memory: ${YELLOW}SEDANG${NC} (${memory_usage_percent}%)"
    else
        echo -e "💾 Penggunaan Memory: ${RED}TINGGI${NC} (${memory_usage_percent}%)"
    fi

    if [ $cpu_usage_int -lt 50 ]; then
        echo -e "🔥 Penggunaan CPU: ${GREEN}RENDAH${NC} (${cpu_usage}%)"
    elif [ $cpu_usage_int -lt 70 ]; then
        echo -e "🔥 Penggunaan CPU: ${YELLOW}SEDANG${NC} (${cpu_usage}%)"
    else
        echo -e "🔥 Penggunaan CPU: ${RED}TINGGI${NC} (${cpu_usage}%)"
    fi

    if [ $existing_apps -lt 3 ]; then
        echo -e "📱 Jumlah App: ${GREEN}RENDAH${NC} ($existing_apps apps)"
    elif [ $existing_apps -lt 7 ]; then
        echo -e "📱 Jumlah App: ${YELLOW}SEDANG${NC} ($existing_apps apps)"
    else
        echo -e "📱 Jumlah App: ${RED}TINGGI${NC} ($existing_apps apps)"
    fi

    echo ""

    # Warnings
    if [ $memory_usage_percent -gt 80 ] || [ $cpu_usage_int -gt 80 ] || [ $existing_apps -gt 7 ]; then
        log_header "⚠️  WARNINGS"
        if [ $memory_usage_percent -gt 80 ]; then
            log_warning "Penggunaan memory tinggi terdeteksi"
        fi
        if [ $cpu_usage_int -gt 80 ]; then
            log_warning "Penggunaan CPU tinggi terdeteksi"
        fi
        if [ $existing_apps -gt 7 ]; then
            log_warning "Jumlah aplikasi tinggi terdeteksi"
        fi
        log_warning "💡 Pertimbangkan untuk scale horizontal atau optimasi resource"
        echo ""
    fi

    # Rekomendasi
    log_header "💡 REKOMENDASI"
    if [ $potential_apps -gt 3 ]; then
        echo "✅ Server memiliki kapasitas yang baik untuk aplikasi baru"
    elif [ $potential_apps -gt 1 ]; then
        echo "⚠️  Server memiliki kapasitas terbatas - rencanakan dengan hati-hati"
    else
        echo "🚨 Server sudah pada kapasitas maksimal - scale horizontal"
    fi

    if [ $memory_usage_percent -gt 70 ]; then
        echo "💾 Pertimbangkan untuk mengoptimasi penggunaan memory atau menambah RAM"
    fi

    if [ $cpu_usage_int -gt 70 ]; then
        echo "🔥 Pertimbangkan untuk mengoptimasi penggunaan CPU atau menambah CPU cores"
    fi

    if [ $existing_apps -gt 5 ]; then
        echo "📱 Pertimbangkan untuk konsolidasi aplikasi serupa atau deploy ke server tambahan"
    fi

    echo ""
}

# Fungsi untuk analisis resource aplikasi detail
analyze_app_resources() {
    log_header "📱 ANALISIS RESOURCE APLIKASI DETAIL"
    log_header "=================================="
    echo ""

    local total_threads=0
    local total_memory_used=0
    local total_instances=0

    # Analisis setiap aplikasi
    for config in $CONFIG_DIR/*.conf; do
        if [ -f "$config" ]; then
            source "$config"

            # Dapatkan threads aplikasi
            local app_threads=2
            if [ -f "$APP_DIR/Caddyfile" ]; then
                app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
            fi

            # Hitung instances
            local instances=1
            local instance_list=""
            for service in /etc/systemd/system/frankenphp-$APP_NAME-*.service; do
                if [ -f "$service" ]; then
                    local port=$(basename "$service" .service | cut -d'-' -f3)
                    instances=$((instances + 1))
                    instance_list="$instance_list $port"
                fi
            done

            # Hitung penggunaan memory
            local app_memory=$(($app_threads * 80 * $instances))

            # Status service
            local status=$(systemctl is-active frankenphp-$APP_NAME 2>/dev/null || echo "inactive")

            # Tampilkan info aplikasi
            echo "🔸 App: $APP_NAME"
            echo "   🌐 Domain: $DOMAIN"
            echo "   🧵 Threads: $app_threads per instance"
            echo "   📱 Instances: $instances"
            if [ -n "$instance_list" ]; then
                echo "   🔗 Port yang di-scale:$instance_list"
            fi
            echo "   💾 Penggunaan Memory: ~${app_memory}MB"
            echo "   🔄 Status: $status"
            echo "   📁 Directory: $APP_DIR"
            echo ""

            total_threads=$(($total_threads + ($app_threads * $instances)))
            total_memory_used=$(($total_memory_used + $app_memory))
            total_instances=$(($total_instances + $instances))
        fi
    done

    # Ringkasan
    log_header "📊 RINGKASAN"
    echo "🏗️  Total Apps: $(ls $CONFIG_DIR/*.conf 2>/dev/null | wc -l)"
    echo "📱 Total Instances: $total_instances"
    echo "🧵 Total Threads: $total_threads"
    echo "💾 Total Memory Digunakan: ${total_memory_used}MB"
    echo ""

    # Perbandingan sistem
    local system_memory=$(free -m | awk 'NR==2{print $2}')
    local system_cpu=$(nproc)
    local memory_percent=$(($total_memory_used * 100 / $system_memory))

    echo "📈 Penggunaan Sistem:"
    echo "   💾 Memory: ${memory_percent}% dari ${system_memory}MB"
    echo "   🧵 Efisiensi Thread: $total_threads threads pada $system_cpu CPU cores"
    echo ""
}

# Export fungsi
export -f get_system_resources get_app_resource_usage calculate_smart_threads
export -f preflight_resource_check display_resource_warnings
export -f monitor_server_resources analyze_app_resources 