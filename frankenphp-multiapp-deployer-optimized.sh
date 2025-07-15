#!/bin/bash

# =============================================
# FrankenPHP Multi-App Deployment Script - OPTIMIZED
# Ubuntu 24.04 - FrankenPHP approach
#
# Version: 2.0 (Modular)
# Features:
# - Modular architecture dengan file terpisah
# - Mirror Ubuntu Indonesia untuk download cepat
# - Embedded PHP server (no PHP-FPM needed)
# - Built-in Caddy web server
# - Automatic HTTPS with Let's Encrypt
# - Horizontal scaling with load balancer
# - Multi-app support with isolation
# - GitHub integration for auto-deployment
# - ERROR HANDLING & ROLLBACK MECHANISM
# - Resource awareness system
# =============================================

set -e  # Exit on any error

# Dapatkan direktori script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Load semua modul
source "$LIB_DIR/config.sh"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/system_setup.sh"
source "$LIB_DIR/resource_management.sh"
source "$LIB_DIR/app_management.sh"

# Fungsi rollback
rollback_deployment() {
    local app_name="$1"

    if [ "$ROLLBACK_NEEDED" = true ]; then
        log_error "❌ Deployment gagal! Memulai rollback untuk $app_name..."

        # Stop dan hapus service
        if [ -n "$CREATED_SERVICE_FILE" ]; then
            systemctl stop "frankenphp-$app_name" 2>/dev/null || true
            systemctl disable "frankenphp-$app_name" 2>/dev/null || true
            rm -f "$CREATED_SERVICE_FILE"
            log_info "✅ Service file dihapus"
        fi

        # Hapus supervisor config
        if [ -n "$CREATED_SUPERVISOR_FILE" ]; then
            rm -f "$CREATED_SUPERVISOR_FILE"
            supervisorctl reread 2>/dev/null || true
            supervisorctl update 2>/dev/null || true
            log_info "✅ Supervisor config dihapus"
        fi

        # Hapus cron jobs
        if [ -n "$CREATED_CRON_JOBS" ]; then
            crontab -u www-data -l 2>/dev/null | grep -v "$app_name" | crontab -u www-data - 2>/dev/null || true
            log_info "✅ Cron jobs dihapus"
        fi

        # Hapus database dan user
        if [ -n "$CREATED_DATABASE" ] && [ -n "$CREATED_DB_USER" ]; then
            source /root/.mysql_credentials 2>/dev/null || true
            if [ -n "$MYSQL_ROOT_PASS" ]; then
                mysql -u root -p$MYSQL_ROOT_PASS <<MYSQL_EOF 2>/dev/null || true
DROP DATABASE IF EXISTS \`$CREATED_DATABASE\`;
DROP USER IF EXISTS '$CREATED_DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF
                log_info "✅ Database dan user dihapus"
            fi
        fi

        # Hapus direktori aplikasi
        if [ -n "$CREATED_APP_DIR" ] && [ -d "$CREATED_APP_DIR" ]; then
            rm -rf "$CREATED_APP_DIR"
            log_info "✅ Direktori aplikasi dihapus"
        fi

        # Hapus config file
        if [ -n "$CREATED_CONFIG_FILE" ]; then
            rm -f "$CREATED_CONFIG_FILE"
            log_info "✅ Config file dihapus"
        fi

        systemctl daemon-reload 2>/dev/null || true

        log_info "🔄 Rollback selesai untuk $app_name"
        exit 1
    fi
}

# Error trap function
error_handler() {
    local exit_code=$?
    local line_number=$1
    log_error "❌ Error terjadi pada baris $line_number (exit code: $exit_code)"

    if [ -n "$CURRENT_APP_NAME" ]; then
        ROLLBACK_NEEDED=true
        rollback_deployment "$CURRENT_APP_NAME"
    fi

    exit $exit_code
}

# Set up error trap
trap 'error_handler $LINENO' ERR

# Fungsi untuk menampilkan bantuan
show_help() {
    log_header "🚀 FrankenPHP Multi-App Deployment Script - OPTIMIZED"
    log_header "=================================================="
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "COMMANDS:"
    echo "  setup                           - Setup sistem lengkap"
    echo "  create <name> <domain> [repo]   - Buat aplikasi Laravel baru"
    echo "  deploy <name>                   - Deploy aplikasi"
    echo "  list                            - List semua aplikasi"
    echo "  remove <name>                   - Hapus aplikasi"
    echo "  status <name>                   - Status aplikasi"
    echo "  monitor                         - Monitor resource server"
    echo "  analyze                         - Analisis resource aplikasi"
    echo "  help                            - Tampilkan bantuan ini"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 setup"
    echo "  $0 create web_sam testingsetup.rizqis.com https://github.com/CompleteLabs/web-app-sam.git"
    echo "  $0 deploy web_sam"
    echo "  $0 list"
    echo "  $0 monitor"
    echo ""
    echo "FEATURES:"
    echo "  🇮🇩 Mirror Ubuntu Indonesia untuk download cepat"
    echo "  ⚡ Embedded PHP server (no PHP-FPM needed)"
    echo "  🌐 Built-in Caddy web server"
    echo "  🔒 Auto HTTPS dengan Let's Encrypt"
    echo "  📈 Horizontal scaling dengan load balancer"
    echo "  🔧 GitHub integration"
    echo "  🧠 Dynamic thread optimization"
    echo "  📊 Resource awareness system"
    echo ""
}

# Fungsi utama
main() {
    local command="${1:-help}"
    
    case "$command" in
        "setup")
            log_header "🚀 Memulai setup sistem FrankenPHP Multi-App..."
            setup_system
            create_management_scripts
            log_info "✅ Setup sistem berhasil diselesaikan!"
            show_usage_info
            ;;
        
        "create")
            if [ $# -lt 3 ]; then
                log_error "Usage: $0 create <app-name> <domain> [github-repo] [db-name]"
                exit 1
            fi
            create_laravel_app "$2" "$3" "$4" "$5"
            ;;
        
        "deploy")
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 deploy <app-name>"
                exit 1
            fi
            deploy_laravel_app "$2"
            ;;
        
        "list")
            list_laravel_apps
            ;;
        
        "remove")
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 remove <app-name>"
                exit 1
            fi
            remove_laravel_app "$2"
            ;;
        
        "status")
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 status <app-name>"
                exit 1
            fi
            show_app_status "$2"
            ;;
        
        "monitor")
            monitor_server_resources
            ;;
        
        "analyze")
            analyze_app_resources
            ;;
        
        "help"|*)
            show_help
            ;;
    esac
}

# Fungsi untuk menampilkan status aplikasi
show_app_status() {
    local app_name="$1"
    local config_file="$CONFIG_DIR/$app_name.conf"

    if [ ! -f "$config_file" ]; then
        log_error "App $app_name tidak ditemukan!"
        return 1
    fi

    source "$config_file"

    echo "📊 Status untuk $app_name"
    echo "========================"
    echo "🌐 Domain: $DOMAIN"
    echo "📁 Directory: $APP_DIR"
    echo ""

    # Status service utama
    local main_status=$(systemctl is-active "frankenphp-$app_name" 2>/dev/null || echo "inactive")
    echo "🔸 Main Instance: $main_status"

    # Cek scaled instances
    echo "🔸 Scaled Instances:"
    for service in /etc/systemd/system/frankenphp-$app_name-*.service; do
        if [ -f "$service" ]; then
            local port=$(basename "$service" .service | cut -d'-' -f3)
            local status=$(systemctl is-active "frankenphp-$app_name-$port" 2>/dev/null || echo "inactive")
            echo "   Port $port: $status"
        fi
    done

    # Cek apakah load balancer aktif
    if grep -q "reverse_proxy" "$APP_DIR/Caddyfile"; then
        echo "⚖️  Load Balancer: Active"
        echo "🔄 Load Balancing Method: Round Robin"
    else
        echo "⚖️  Load Balancer: Direct Serve"
    fi

    # Status worker
    echo ""
    echo "👷 Queue Workers:"
    supervisorctl status "laravel-worker-$app_name:*" 2>/dev/null || echo "   No workers found"

    # Log terbaru
    echo ""
    echo "📋 Recent Logs (last 5 lines):"
    tail -5 "$LOG_DIR/$app_name"*.log 2>/dev/null || echo "   No logs found"
}

# Fungsi untuk membuat management scripts
create_management_scripts() {
    log_info "📝 Membuat management scripts..."
    
    # Buat script untuk create app
    cat > /usr/local/bin/create-laravel-app <<'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /root/frankenphp-multiapp-deployer-optimized.sh create "$@"
SCRIPT_EOF

    # Buat script untuk deploy app
    cat > /usr/local/bin/deploy-laravel-app <<'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /root/frankenphp-multiapp-deployer-optimized.sh deploy "$@"
SCRIPT_EOF

    # Buat script untuk list apps
    cat > /usr/local/bin/list-laravel-apps <<'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /root/frankenphp-multiapp-deployer-optimized.sh list
SCRIPT_EOF

    # Buat script untuk remove app
    cat > /usr/local/bin/remove-laravel-app <<'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /root/frankenphp-multiapp-deployer-optimized.sh remove "$@"
SCRIPT_EOF

    # Buat script untuk status app
    cat > /usr/local/bin/status-laravel-app <<'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /root/frankenphp-multiapp-deployer-optimized.sh status "$@"
SCRIPT_EOF

    # Buat script untuk monitor resources
    cat > /usr/local/bin/monitor-server-resources <<'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /root/frankenphp-multiapp-deployer-optimized.sh monitor
SCRIPT_EOF

    # Buat script untuk analyze resources
    cat > /usr/local/bin/analyze-app-resources <<'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /root/frankenphp-multiapp-deployer-optimized.sh analyze
SCRIPT_EOF

    # Buat script backup
    cat > /usr/local/bin/backup-all-laravel-apps <<'BACKUP_EOF'
#!/bin/bash

BACKUP_DIR="/var/backups/laravel-apps"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR/$DATE

echo "📦 Backing up all Laravel apps..."

for config in /etc/laravel-apps/*.conf; do
    if [ -f "$config" ]; then
        source "$config"

        echo "Backing up $APP_NAME..."

        # Backup database
        source /root/.mysql_credentials
        mysqldump -u root -p$MYSQL_ROOT_PASS \`$DB_NAME\` > $BACKUP_DIR/$DATE/${APP_NAME}_database.sql

        # Backup application files
        tar -czf $BACKUP_DIR/$DATE/${APP_NAME}_app.tar.gz -C $APP_DIR .

        echo "✅ $APP_NAME backed up"
    fi
done

# Keep only last 7 days of backups
find $BACKUP_DIR -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

echo "✅ All backups completed: $DATE"
BACKUP_EOF

    # Buat semua script executable
    chmod +x /usr/local/bin/create-laravel-app
    chmod +x /usr/local/bin/deploy-laravel-app
    chmod +x /usr/local/bin/list-laravel-apps
    chmod +x /usr/local/bin/remove-laravel-app
    chmod +x /usr/local/bin/status-laravel-app
    chmod +x /usr/local/bin/monitor-server-resources
    chmod +x /usr/local/bin/analyze-app-resources
    chmod +x /usr/local/bin/backup-all-laravel-apps

    log_info "✅ Management scripts berhasil dibuat"
}

# Fungsi untuk menampilkan informasi penggunaan
show_usage_info() {
    local optimal_threads=$(calculate_optimal_threads)
    
    log_info "✅ FrankenPHP Multi-App setup berhasil diselesaikan!"
    log_info ""
    log_info "📚 Perintah yang tersedia:"
    log_info "  create-laravel-app <name> <domain> [github-repo] [db-name]"
    log_info "  deploy-laravel-app <name>"
    log_info "  list-laravel-apps"
    log_info "  remove-laravel-app <name>"
    log_info "  status-laravel-app <name>"
    log_info "  monitor-server-resources"
    log_info "  analyze-app-resources"
    log_info "  backup-all-laravel-apps"
    log_info ""
    log_info "🎯 Contoh penggunaan:"
    log_info "  create-laravel-app web_sam testingsetup.rizqis.com https://github.com/CompleteLabs/web-app-sam.git"
    log_info "  create-laravel-app web_crm_app crm.completelabs.com https://github.com/user/laravel-crm.git"
    log_info "  deploy-laravel-app web_sam"
    log_info "  status-laravel-app web_sam"
    log_info "  monitor-server-resources"
    log_info ""
    log_info "📝 Aturan penamaan aplikasi:"
    log_info "  - Gunakan underscore bukan dash (web_sam bukan web-sam)"
    log_info "  - Mulai dengan huruf, hanya huruf/angka/underscore"
    log_info "  - Contoh: web_sam_l12, websaml12, webSamL12"
    log_info ""
    log_info "🔐 MySQL root password tersimpan di: /root/.mysql_credentials"
    log_info "🇮🇩 Menggunakan mirror Ubuntu Indonesia untuk download cepat"
    log_info "🎉 Siap untuk FrankenPHP multi-app deployment!"
    log_info ""
    log_info "🚀 Keunggulan FrankenPHP:"
    log_info "  - ⚡ Embedded PHP server (tidak perlu PHP-FPM)"
    log_info "  - 🌐 Built-in Caddy web server"
    log_info "  - 🔒 Auto HTTPS dengan Let's Encrypt"
    log_info "  - 📈 Horizontal scaling dengan load balancer"
    log_info "  - 🔧 Direct domain handling"
    log_info "  - 🎯 Arsitektur yang lebih sederhana"
    log_info "  - 🚀 Performa yang lebih baik"
    log_info "  - 📦 Integrasi GitHub"
    log_info "  - 🔄 Zero-downtime deployment"
    log_info "  - 🧠 Optimasi thread dinamis (CPU: $(nproc) cores → $optimal_threads threads)"
    log_info ""
    log_info "🔍 Sistem Resource Awareness:"
    log_info "  - 🛡️  Pre-flight checks mencegah over-komitmen resource"
    log_info "  - 🧠 Smart thread allocation berdasarkan kapasitas server"
    log_info "  - ⚠️  Sistem warning untuk threshold resource"
    log_info "  - 🚫 Hard limits mencegah server crash"
    log_info "  - 📊 Real-time resource monitoring"
    log_info "  - 🔮 Prediksi impact untuk perubahan"
    log_info "  - 💡 Rekomendasi optimasi"
    log_info "  - 📈 Tools untuk capacity planning"
    log_info "  - 🎯 Dynamic scaling decisions"
    log_info "  - 🔧 Automated resource management"

    # Tampilkan warning resource saat ini
    display_resource_warnings
}

# Jalankan fungsi utama
main "$@" 