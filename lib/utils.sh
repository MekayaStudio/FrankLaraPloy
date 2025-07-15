#!/bin/bash

# =============================================
# Utilities Module
# Berisi fungsi-fungsi helper, logging, dan error handling
# =============================================

# Load konfigurasi
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Fungsi logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${BLUE}$1${NC}"
}

# Fungsi untuk menghitung optimal threads
calculate_optimal_threads() {
    local cpu_cores=$(nproc)
    local available_memory_gb=$(free -g | awk 'NR==2{print $7}')
    local optimal_threads

    # Base calculation: Start with CPU cores
    if [ $cpu_cores -eq 1 ]; then
        optimal_threads=2
    elif [ $cpu_cores -eq 2 ]; then
        optimal_threads=3
    elif [ $cpu_cores -le 4 ]; then
        optimal_threads=$((cpu_cores + 1))
    elif [ $cpu_cores -le 8 ]; then
        optimal_threads=$((cpu_cores + 2))
    else
        optimal_threads=$(((cpu_cores * 3 / 4) + 4))
    fi

    # Memory constraint check
    local max_threads_by_memory=$((available_memory_gb * 1024 / 80))

    if [ $max_threads_by_memory -lt $optimal_threads ]; then
        optimal_threads=$max_threads_by_memory
    fi

    # Ensure minimum of 2 threads and maximum of 32 threads
    if [ $optimal_threads -lt 2 ]; then
        optimal_threads=2
    elif [ $optimal_threads -gt 32 ]; then
        optimal_threads=32
    fi

    echo $optimal_threads
}

# Fungsi untuk validasi nama aplikasi
validate_app_name() {
    local app_name="$1"
    
    if [[ ! "$app_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        log_error "App name '$app_name' contains invalid characters!"
        log_error "App name should:"
        log_error "  - Start with a letter"
        log_error "  - Contain only letters, numbers, and underscores"
        log_error "  - No spaces or special characters"
        log_error ""
        log_error "Examples of valid names:"
        log_error "  - web_sam_l12"
        log_error "  - websaml12"
        log_error "  - webSamL12"
        log_error "  - web_app_sam"
        return 1
    fi
    return 0
}

# Fungsi untuk mengecek apakah port sudah digunakan
check_port_usage() {
    local port="$1"
    if netstat -tuln | grep -q ":$port "; then
        return 1  # Port sudah digunakan
    fi
    return 0  # Port tersedia
}

# Fungsi untuk membuat direktori dengan permission yang tepat
create_directory() {
    local dir_path="$1"
    local owner="${2:-www-data:www-data}"
    local permissions="${3:-755}"
    
    mkdir -p "$dir_path"
    chown "$owner" "$dir_path"
    chmod "$permissions" "$dir_path"
}

# Fungsi untuk menggenerate password yang aman
generate_password() {
    openssl rand -base64 32
}

# Fungsi untuk mengecek apakah service berjalan
check_service_status() {
    local service_name="$1"
    systemctl is-active "$service_name" >/dev/null 2>&1
}

# Fungsi untuk restart service dengan error handling
restart_service() {
    local service_name="$1"
    
    if systemctl restart "$service_name"; then
        log_info "✅ Service $service_name restarted successfully"
        return 0
    else
        log_error "❌ Failed to restart service $service_name"
        return 1
    fi
}

# Fungsi untuk enable service
enable_service() {
    local service_name="$1"
    
    if systemctl enable "$service_name"; then
        log_info "✅ Service $service_name enabled successfully"
        return 0
    else
        log_error "❌ Failed to enable service $service_name"
        return 1
    fi
}

# Fungsi untuk mengecek apakah aplikasi sudah ada
app_exists() {
    local app_name="$1"
    [ -d "$APPS_BASE_DIR/$app_name" ]
}

# Fungsi untuk mengecek apakah config file ada
config_exists() {
    local app_name="$1"
    [ -f "$CONFIG_DIR/$app_name.conf" ]
}

# Fungsi untuk membersihkan string untuk MySQL
clean_mysql_name() {
    local name="$1"
    echo "$name" | sed 's/-/_/g'
}

# Fungsi untuk mengecek koneksi internet
check_internet_connection() {
    if ping -c 1 google.com >/dev/null 2>&1; then
        return 0
    else
        log_error "❌ No internet connection detected"
        return 1
    fi
}

# Fungsi untuk download file dengan retry
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-3}"
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if wget -O "$output" "$url"; then
            return 0
        else
            retry_count=$((retry_count + 1))
            log_warning "Download failed, retrying ($retry_count/$max_retries)..."
            sleep 2
        fi
    done
    
    log_error "❌ Failed to download after $max_retries attempts"
    return 1
}

# Fungsi untuk mengecek space disk
check_disk_space() {
    local required_space_gb="${1:-5}"  # Default 5GB
    local available_space_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [ $available_space_gb -lt $required_space_gb ]; then
        log_error "❌ Insufficient disk space"
        log_error "   Required: ${required_space_gb}GB"
        log_error "   Available: ${available_space_gb}GB"
        return 1
    fi
    
    return 0
}

# Export semua fungsi agar bisa digunakan di modul lain
export -f log_info log_warning log_error log_header
export -f calculate_optimal_threads validate_app_name check_port_usage
export -f create_directory generate_password check_service_status
export -f restart_service enable_service app_exists config_exists
export -f clean_mysql_name check_internet_connection download_with_retry
export -f check_disk_space 