#!/bin/bash

# =============================================
# Shared Functions Library
# Library untuk fungsi-fungsi yang digunakan bersama
# oleh frankenphp-multiapp-deployer.sh dan install.sh
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "$SHARED_FUNCTIONS_LOADED" ]; then
    return 0
fi
export SHARED_FUNCTIONS_LOADED=1

# =============================================
# Configuration Constants
# =============================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Resource constants (can be overridden by config file)
MEMORY_SAFETY_MARGIN="${MEMORY_SAFETY_MARGIN:-20}"
CPU_SAFETY_MARGIN="${CPU_SAFETY_MARGIN:-25}"
MIN_MEMORY_PER_APP="${MIN_MEMORY_PER_APP:-512}"
MAX_MEMORY_PER_APP="${MAX_MEMORY_PER_APP:-2048}"
MIN_CPU_PER_APP="${MIN_CPU_PER_APP:-0.5}"
THREAD_MEMORY_USAGE="${THREAD_MEMORY_USAGE:-80}"
MAX_APPS_PER_SERVER="${MAX_APPS_PER_SERVER:-10}"

# Paths (can be overridden by config file)
APPS_BASE_DIR="${APPS_BASE_DIR:-/opt/laravel-apps}"
LOG_DIR="${LOG_DIR:-/var/log/frankenphp}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/laravel-apps}"
CONFIG_DIR="${CONFIG_DIR:-/etc/laravel-apps}"

# =============================================
# Logging Functions
# =============================================

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

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# =============================================
# Utility Functions
# =============================================

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if package is installed
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Check if systemd service exists
service_exists() {
    systemctl list-unit-files | grep -q "^$1.service"
}

# Check if service is running
service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# Get absolute path
get_absolute_path() {
    local path="$1"
    if [ -d "$path" ]; then
        cd "$path" && pwd
    else
        echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    fi
}

# =============================================
# Validation Functions
# =============================================

# Validate domain format
validate_domain() {
    local domain="$1"
    local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$"
    local ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    local localhost_regex="^localhost$"

    if [ -z "$domain" ]; then
        log_error "Domain tidak boleh kosong!"
        return 1
    fi

    if [ ${#domain} -gt 253 ]; then
        log_error "Domain terlalu panjang (maksimal 253 karakter)!"
        return 1
    fi

    if [[ "$domain" =~ $localhost_regex ]]; then
        log_debug "Domain localhost valid"
        return 0
    fi

    # Validate IP address
    if [[ "$domain" =~ ^[0-9.]+$ ]]; then
        local dot_count=$(echo "$domain" | tr -cd '.' | wc -c)
        if [ $dot_count -eq 3 ]; then
            local valid_ip=true
            IFS='.' read -ra OCTETS <<< "$domain"

            if [ ${#OCTETS[@]} -ne 4 ]; then
                log_error "IP address $domain tidak valid!"
                return 1
            fi

            for octet in "${OCTETS[@]}"; do
                if [ -z "$octet" ] || ! [[ "$octet" =~ ^[0-9]+$ ]] || [ $octet -gt 255 ]; then
                    valid_ip=false
                    break
                fi

                if [ ${#octet} -gt 1 ] && [ "${octet:0:1}" = "0" ]; then
                    valid_ip=false
                    break
                fi
            done

            if [ "$valid_ip" = true ]; then
                log_debug "IP address $domain valid"
                return 0
            else
                log_error "IP address $domain tidak valid!"
                return 1
            fi
        else
            log_error "IP address $domain tidak valid!"
            return 1
        fi
    fi

    # Validate domain format
    if [[ "$domain" =~ $domain_regex ]]; then
        log_debug "Domain $domain valid"
        return 0
    else
        log_error "Format domain $domain tidak valid!"
        log_error "Contoh format yang valid:"
        log_error "  - example.com"
        log_error "  - subdomain.example.com"
        log_error "  - example.co.id"
        log_error "  - localhost"
        log_error "  - 192.168.1.1"
        return 1
    fi
}

# Validate port number
validate_port() {
    local port="$1"
    local check_in_use="${2:-true}"

    if [ -z "$port" ]; then
        log_error "Port tidak boleh kosong!"
        return 1
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "Port harus berupa angka!"
        return 1
    fi

    if [ $port -lt 1 ] || [ $port -gt 65535 ]; then
        log_error "Port harus dalam range 1-65535!"
        return 1
    fi

    if [ $port -lt 1024 ]; then
        log_warning "Port $port adalah privileged port (< 1024), memerlukan akses root"
    fi

    if [ "$check_in_use" = true ]; then
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            log_error "Port $port sudah digunakan!"
            return 1
        fi
    fi

    log_debug "Port $port valid dan tersedia"
    return 0
}

# Validate app name
validate_app_name() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Nama app tidak boleh kosong!"
        return 1
    fi

    if [ ${#app_name} -gt 60 ]; then
        log_error "Nama app terlalu panjang (maksimal 60 karakter)!"
        return 1
    fi

    if ! [[ "$app_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        log_error "Format nama app '$app_name' tidak valid!"
        log_error "Nama app harus:"
        log_error "  - Dimulai dengan huruf"
        log_error "  - Hanya mengandung huruf, angka, dan underscore"
        log_error "  - Tidak ada spasi atau karakter spesial"
        log_error ""
        log_error "Contoh nama yang valid:"
        log_error "  - web_sam_l12"
        log_error "  - websaml12"
        log_error "  - webSamL12"
        log_error "  - web_app_sam"
        return 1
    fi

    local reserved_words=("mysql" "root" "admin" "test" "information_schema" "performance_schema" "sys")
    for reserved in "${reserved_words[@]}"; do
        local app_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
        local reserved_lower=$(echo "$reserved" | tr '[:upper:]' '[:lower:]')
        if [ "$app_lower" = "$reserved_lower" ]; then
            log_error "Nama app '$app_name' adalah reserved word!"
            return 1
        fi
    done

    log_debug "Nama app '$app_name' valid"
    return 0
}

# Check if Laravel app directory is valid
check_laravel_app() {
    local dir="${1:-.}"

    if [ ! -f "$dir/artisan" ]; then
        log_error "Tidak ditemukan file artisan di $dir"
        log_error "Pastikan Anda berada di direktori Laravel yang valid"
        return 1
    fi

    if [ ! -f "$dir/composer.json" ]; then
        log_error "Tidak ditemukan file composer.json di $dir"
        return 1
    fi

    log_debug "Laravel app ditemukan di $dir"
    return 0
}

# =============================================
# Resource Management Functions
# =============================================

# Get current system resources
get_system_resources() {
    local total_memory_mb available_memory_mb total_cpu_cores cpu_usage

    # Check if running on macOS or Linux
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        local total_memory_bytes=$(sysctl -n hw.memsize)
        total_memory_mb=$((total_memory_bytes / 1024 / 1024))
        available_memory_mb=$((total_memory_mb * 80 / 100))  # Estimate 80% available
        total_cpu_cores=$(sysctl -n hw.ncpu)
        cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo "10")
    else
        # Linux
        if command -v free >/dev/null 2>&1; then
            total_memory_mb=$(free -m | awk 'NR==2{print $2}')
            available_memory_mb=$(free -m | awk 'NR==2{print $7}')
        else
            # Fallback for systems without free command
            total_memory_mb=1024
            available_memory_mb=512
        fi

        if command -v nproc >/dev/null 2>&1; then
            total_cpu_cores=$(nproc)
        else
            total_cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "2")
        fi

        cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' 2>/dev/null || echo "10")
    fi

    # Ensure we have valid numbers
    total_memory_mb=${total_memory_mb:-1024}
    available_memory_mb=${available_memory_mb:-512}
    total_cpu_cores=${total_cpu_cores:-2}
    cpu_usage=${cpu_usage:-10}

    # Calculate usable resources (after safety margins)
    local usable_memory_mb=$(($total_memory_mb * (100 - $MEMORY_SAFETY_MARGIN) / 100))
    local usable_cpu_cores=$(echo "$total_cpu_cores * (100 - $CPU_SAFETY_MARGIN) / 100" | bc -l 2>/dev/null || echo "$total_cpu_cores")

    echo "$total_memory_mb $available_memory_mb $total_cpu_cores $cpu_usage $usable_memory_mb $usable_cpu_cores"
}

# Get app resource usage
get_app_resource_usage() {
    local app_count=0
    local total_memory_used=0
    local total_cpu_used=0

    # Count apps and their resource usage
    if [ -d "$CONFIG_DIR" ]; then
        app_count=$(find "$CONFIG_DIR" -name "*.conf" | wc -l)
    fi

    # Estimate resource usage based on app count
    total_memory_used=$((app_count * MIN_MEMORY_PER_APP))
    total_cpu_used=$(echo "$app_count * $MIN_CPU_PER_APP" | bc -l 2>/dev/null || echo "$app_count")

    echo "$app_count $total_memory_used $total_cpu_used"
}

# Calculate optimal FrankenPHP thread count
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

# Calculate smart threads based on existing apps
calculate_smart_threads() {
    local base_threads=$1
    local existing_apps=$2
    local total_memory_mb=$3
    local available_memory_mb=$4
    local total_cpu_cores=$5

    local smart_threads=$base_threads

    if [ $existing_apps -gt 0 ]; then
        # Calculate resource per app
        local memory_per_app=$(($total_memory_mb / ($existing_apps + 1)))
        local cpu_per_app=$(echo "$total_cpu_cores / ($existing_apps + 1)" | bc -l)

        # Adjust threads based on memory constraint
        local max_threads_by_memory=$(($memory_per_app / $THREAD_MEMORY_USAGE))
        if [ $max_threads_by_memory -lt $smart_threads ]; then
            smart_threads=$max_threads_by_memory
        fi

        # Adjust threads based on CPU constraint
        local max_threads_by_cpu=$(echo "$cpu_per_app * 2" | bc -l | cut -d'.' -f1)
        if [ $max_threads_by_cpu -lt $smart_threads ]; then
            smart_threads=$max_threads_by_cpu
        fi

        # Apply scaling factor based on app count
        if [ $existing_apps -ge 5 ]; then
            smart_threads=$((smart_threads * 70 / 100))
        elif [ $existing_apps -ge 3 ]; then
            smart_threads=$((smart_threads * 80 / 100))
        elif [ $existing_apps -ge 1 ]; then
            smart_threads=$((smart_threads * 90 / 100))
        fi
    fi

    # Ensure minimum viable threads
    if [ $smart_threads -lt 2 ]; then
        smart_threads=2
    fi

    echo $smart_threads
}

# =============================================
# File and Directory Management
# =============================================

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    local owner="${2:-www-data:www-data}"
    local permissions="${3:-755}"

    if [ ! -d "$dir" ]; then
        log_debug "Creating directory: $dir"
        mkdir -p "$dir"
        chown "$owner" "$dir"
        chmod "$permissions" "$dir"
    else
        log_debug "Directory already exists: $dir"
    fi
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    local backup_suffix="${2:-$(date +%Y%m%d_%H%M%S)}"

    if [ -f "$file" ]; then
        local backup_file="${file}.backup.${backup_suffix}"
        cp "$file" "$backup_file"
        log_debug "File backed up: $file -> $backup_file"
        echo "$backup_file"
    else
        log_debug "File not found for backup: $file"
        return 1
    fi
}

# Safe file update with backup
safe_file_update() {
    local file="$1"
    local content="$2"
    local backup_file

    if [ -f "$file" ]; then
        backup_file=$(backup_file "$file")
        if [ $? -ne 0 ]; then
            log_error "Failed to backup file: $file"
            return 1
        fi
    fi

    echo "$content" > "$file"
    if [ $? -eq 0 ]; then
        log_debug "File updated successfully: $file"
        return 0
    else
        log_error "Failed to update file: $file"
        if [ -n "$backup_file" ]; then
            cp "$backup_file" "$file"
            log_info "File restored from backup"
        fi
        return 1
    fi
}

# =============================================
# MySQL Helper Functions
# =============================================

# Get MySQL root credentials
get_mysql_credentials() {
    local cred_file="${MYSQL_CREDENTIALS_FILE:-/root/.mysql_credentials}"

    if [ -f "$cred_file" ]; then
        source "$cred_file"
        echo "${MYSQL_ROOT_PASS:-password}"
    else
        # Return default password in test mode
        if [ "${TEST_MODE:-false}" = "true" ]; then
            echo "testpass"
        else
            log_error "MySQL credentials file not found: $cred_file"
            return 1
        fi
    fi
}

# Test MySQL connection
test_mysql_connection() {
    local mysql_credentials_file="${MYSQL_CREDENTIALS_FILE:-/root/.mysql_credentials}"

    if [ ! -f "$mysql_credentials_file" ]; then
        log_debug "MySQL credentials file not found: $mysql_credentials_file"
        return 1
    fi

    local password=$(get_mysql_credentials)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Test connection (mock in test environment)
    if [ "${TEST_MODE:-false}" = "true" ]; then
        # Mock successful connection in test mode
        log_debug "MySQL connection successful (mocked)"
        return 0
    fi

    # Real MySQL connection test
    if command -v mysql >/dev/null 2>&1; then
        mysql -u root -p"$password" -e "SELECT 1;" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_debug "MySQL connection successful"
            return 0
        else
            log_error "MySQL connection failed"
            return 1
        fi
    else
        log_error "MySQL command not found"
        return 1
    fi
}

# Test Redis connection
test_redis_connection() {
    # Test connection (mock in test environment)
    if [ "${TEST_MODE:-false}" = "true" ]; then
        # Mock successful connection in test mode
        log_debug "Redis connection successful (mocked)"
        return 0
    fi

    # Real Redis connection test
    if command -v redis-cli >/dev/null 2>&1; then
        redis-cli ping >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_debug "Redis connection successful"
            return 0
        else
            log_error "Redis connection failed"
            return 1
        fi
    else
        log_error "Redis CLI command not found"
        return 1
    fi
}

# =============================================
# Service Management Functions
# =============================================

# Start service with error handling
start_service() {
    local service_name="$1"

    if ! service_exists "$service_name"; then
        log_error "Service $service_name does not exist"
        return 1
    fi

    systemctl start "$service_name"
    if [ $? -eq 0 ]; then
        log_info "Service $service_name started successfully"
        return 0
    else
        log_error "Failed to start service $service_name"
        return 1
    fi
}

# Stop service with error handling
stop_service() {
    local service_name="$1"

    if service_running "$service_name"; then
        systemctl stop "$service_name"
        if [ $? -eq 0 ]; then
            log_info "Service $service_name stopped successfully"
            return 0
        else
            log_error "Failed to stop service $service_name"
            return 1
        fi
    else
        log_debug "Service $service_name is not running"
        return 0
    fi
}

# Restart service with error handling
restart_service() {
    local service_name="$1"

    systemctl restart "$service_name"
    if [ $? -eq 0 ]; then
        log_info "Service $service_name restarted successfully"
        return 0
    else
        log_error "Failed to restart service $service_name"
        return 1
    fi
}

# Enable service on boot
enable_service() {
    local service_name="$1"

    systemctl enable "$service_name"
    if [ $? -eq 0 ]; then
        log_debug "Service $service_name enabled on boot"
        return 0
    else
        log_error "Failed to enable service $service_name"
        return 1
    fi
}

# =============================================
# Configuration Management
# =============================================

# Load app configuration
load_app_config() {
    local app_name="$1"
    local config_file="$CONFIG_DIR/$app_name.conf"

    if [ ! -f "$config_file" ]; then
        log_error "App configuration not found: $config_file"
        return 1
    fi

    source "$config_file"
    log_debug "App configuration loaded: $app_name"
    return 0
}

# Save app configuration
save_app_config() {
    local app_name="$1"
    local config_file="$CONFIG_DIR/$app_name.conf"

    cat > "$config_file" <<EOF
APP_NAME=$APP_NAME
APP_DIR=$APP_DIR
DOMAIN=$DOMAIN
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
GITHUB_REPO=$GITHUB_REPO
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    if [ $? -eq 0 ]; then
        log_debug "App configuration saved: $config_file"
        return 0
    else
        log_error "Failed to save app configuration: $config_file"
        return 1
    fi
}

# Create app configuration
create_app_config() {
    local app_name="$1"
    local domain="$2"
    local github_repo="$3"
    local config_file="$4"

    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$config_file")"

    # Create app configuration
    cat > "$config_file" << EOF
# App Configuration for $app_name
APP_NAME=$app_name
APP_DOMAIN=$domain
APP_DIR=$APPS_BASE_DIR/$app_name
APP_PORT=8080
GITHUB_REPO=$github_repo
DB_NAME=${app_name}_db
DB_USER=${app_name}_user
DB_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "random_password_$(date +%s)")
CREATED_AT=$(date)
EOF

    log_debug "App config created: $config_file"
}

# =============================================
# Cleanup Functions
# =============================================

# Clean up temporary files
cleanup_temp_files() {
    local temp_pattern="${1:-/tmp/frankenphp-*}"

    find /tmp -name "$(basename "$temp_pattern")" -type f -mtime +1 -delete 2>/dev/null
    log_debug "Temporary files cleaned up"
}

# Clean up old log files
cleanup_old_logs() {
    local log_dir="${1:-$LOG_DIR}"
    local days="${2:-30}"

    if [ -d "$log_dir" ]; then
        find "$log_dir" -name "*.log" -type f -mtime +$days -delete 2>/dev/null
        log_debug "Old log files cleaned up (older than $days days)"
    fi
}

# =============================================
# Error Handling
# =============================================

# Set up error trap
setup_error_trap() {
    trap 'handle_error $? $LINENO' ERR
}

# Handle errors
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Error occurred at line $line_number (exit code: $exit_code)"

    # Call cleanup if function exists
    if type cleanup_on_error >/dev/null 2>&1; then
        cleanup_on_error
    fi

    exit $exit_code
}

# =============================================
# Initialization
# =============================================

# Initialize shared functions
init_shared_functions() {
    # Ensure required directories exist
    ensure_directory "$APPS_BASE_DIR"
    ensure_directory "$LOG_DIR"
    ensure_directory "$BACKUP_DIR"
    ensure_directory "$CONFIG_DIR" "root:root" "755"

    # Setup error handling
    setup_error_trap

    log_debug "Shared functions initialized"
}

# =============================================
# Systemd Configuration
# =============================================

# Generate systemd security settings based on configuration
generate_systemd_security() {
    local app_dir="$1"
    local security_settings=""

    # Load main configuration
    local config_file="config/frankenphp-config.conf"
    if [ -f "$config_file" ]; then
        source "$config_file"
    fi

    # Add resource limits
    security_settings+="# Resource limits\n"
    security_settings+="LimitNOFILE=${SYSTEMD_LIMIT_NOFILE:-65536}\n"
    security_settings+="LimitNPROC=${SYSTEMD_LIMIT_NPROC:-32768}\n\n"

    # Security settings - disabled to prevent namespace conflicts
    # NoNewPrivileges, PrivateTmp, ProtectSystem, ProtectHome disabled
    # to avoid systemd namespace issues (exit code 226/NAMESPACE)
    security_settings+="# Security settings - disabled to prevent namespace conflicts\n"
    security_settings+="# NoNewPrivileges, PrivateTmp, ProtectSystem, ProtectHome disabled\n"
    security_settings+="# to avoid systemd namespace issues (exit code 226/NAMESPACE)\n"

    echo -e "$security_settings"
}

# Auto-initialize when sourced (only for root commands)
if [ "${BASH_SOURCE[0]}" != "${0}" ] && [ "$EUID" -eq 0 ]; then
    init_shared_functions
fi

# Get current CPU usage
get_cpu_usage() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo "10"
    else
        # Linux
        top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' 2>/dev/null || echo "10"
    fi
}

# Get current memory usage in MB
get_memory_usage() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - get memory usage in MB
        local memory_pressure=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print $5}' | sed 's/%//' || echo "50")
        local total_memory_bytes=$(sysctl -n hw.memsize)
        local total_memory_mb=$((total_memory_bytes / 1024 / 1024))
        local used_memory_mb=$(($total_memory_mb * (100 - $memory_pressure) / 100))
        echo "$used_memory_mb"
    else
        # Linux
        if command -v free >/dev/null 2>&1; then
            free -m | awk 'NR==2{print $3}'
        else
            echo "512"  # Default fallback
        fi
    fi
}
