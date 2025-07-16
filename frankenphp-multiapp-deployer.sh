#!/bin/bash

# =============================================
# FrankenPHP Multi-App Deployment Script
# Ubuntu 24.04 - FrankenPHP approach
#
# Features:
# - Embedded PHP server (no PHP-FPM needed)
# - Built-in Caddy web server
# - Automatic HTTPS with Let's Encrypt
# - Horizontal scaling with load balancer
# - Multi-app support with isolation
# - GitHub integration for auto-deployment
# - ERROR HANDLING & ROLLBACK MECHANISM
# =============================================

set -e  # Exit on any error

# Global variables for rollback
ROLLBACK_NEEDED=false
CREATED_DATABASE=""
CREATED_DB_USER=""
CREATED_APP_DIR=""
CREATED_CONFIG_FILE=""
CREATED_SERVICE_FILE=""
CREATED_SUPERVISOR_FILE=""
CREATED_CRON_JOBS=""

# Rollback function
rollback_deployment() {
    local app_name="$1"

    if [ "$ROLLBACK_NEEDED" = true ]; then
        log_error "❌ Deployment failed! Starting rollback for $app_name..."

        # Stop and remove service
        if [ -n "$CREATED_SERVICE_FILE" ]; then
            systemctl stop frankenphp-$app_name 2>/dev/null || true
            systemctl disable frankenphp-$app_name 2>/dev/null || true
            rm -f "$CREATED_SERVICE_FILE"
            log_info "✅ Removed service file"
        fi

        # Remove supervisor config
        if [ -n "$CREATED_SUPERVISOR_FILE" ]; then
            rm -f "$CREATED_SUPERVISOR_FILE"
            supervisorctl reread 2>/dev/null || true
            supervisorctl update 2>/dev/null || true
            log_info "✅ Removed supervisor config"
        fi

        # Remove cron jobs
        if [ -n "$CREATED_CRON_JOBS" ]; then
            crontab -u www-data -l 2>/dev/null | grep -v "$app_name" | crontab -u www-data - 2>/dev/null || true
            log_info "✅ Removed cron jobs"
        fi

        # Remove database and user
        if [ -n "$CREATED_DATABASE" ] && [ -n "$CREATED_DB_USER" ]; then
            source /root/.mysql_credentials 2>/dev/null || true
            if [ -n "$MYSQL_ROOT_PASS" ]; then
                mysql -u root -p$MYSQL_ROOT_PASS <<MYSQL_EOF 2>/dev/null || true
DROP DATABASE IF EXISTS \`$CREATED_DATABASE\`;
DROP USER IF EXISTS '$CREATED_DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF
                log_info "✅ Removed database and user"
            fi
        fi

        # Remove app directory
        if [ -n "$CREATED_APP_DIR" ] && [ -d "$CREATED_APP_DIR" ]; then
            rm -rf "$CREATED_APP_DIR"
            log_info "✅ Removed app directory"
        fi

        # Remove config file
        if [ -n "$CREATED_CONFIG_FILE" ]; then
            rm -f "$CREATED_CONFIG_FILE"
            log_info "✅ Removed config file"
        fi

        systemctl daemon-reload 2>/dev/null || true

        log_info "🔄 Rollback completed for $app_name"
        exit 1
    fi
}

# Error trap function
error_handler() {
    local exit_code=$?
    local line_number=$1
    log_error "❌ Error occurred at line $line_number (exit code: $exit_code)"

    if [ -n "$CURRENT_APP_NAME" ]; then
        ROLLBACK_NEEDED=true
        rollback_deployment "$CURRENT_APP_NAME"
    fi

    exit $exit_code
}

# Set up error trap
trap 'error_handler $LINENO' ERR

echo "🚀 Starting FrankenPHP Multi-App deployment on Ubuntu 24.04..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global Configuration
APPS_BASE_DIR="/opt/laravel-apps"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================
# Validation Functions
# =============================================

# Fungsi untuk validasi domain
validate_domain() {
    local domain="$1"

    # Regex pattern untuk validasi domain
    # Mendukung: domain.com, sub.domain.com, domain.co.id, localhost, 192.168.1.1
    local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$"
    local ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    local localhost_regex="^localhost$"

    # Check if empty
    if [ -z "$domain" ]; then
        log_error "Domain tidak boleh kosong!"
        return 1
    fi

    # Check length (max 253 characters)
    if [ ${#domain} -gt 253 ]; then
        log_error "Domain terlalu panjang (maksimal 253 karakter)!"
        return 1
    fi

    # Check if localhost
    if [[ "$domain" =~ $localhost_regex ]]; then
        log_info "✅ Domain localhost valid"
        return 0
    fi

            # Check if IP address (only digits and dots)
        if [[ "$domain" =~ ^[0-9.]+$ ]]; then
            # Count dots - should be exactly 3
            local dot_count=$(echo "$domain" | tr -cd '.' | wc -c)
            if [ $dot_count -eq 3 ]; then
                # Validate IP octets
                local valid_ip=true
                IFS='.' read -ra OCTETS <<< "$domain"

                # Check exactly 4 octets
                if [ ${#OCTETS[@]} -ne 4 ]; then
                    log_error "IP address $domain tidak valid!"
                    return 1
                fi

                for octet in "${OCTETS[@]}"; do
                    # Check if octet is empty
                    if [ -z "$octet" ]; then
                        valid_ip=false
                        break
                    fi

                    # Check if octet is numeric
                    if ! [[ "$octet" =~ ^[0-9]+$ ]]; then
                        valid_ip=false
                        break
                    fi

                    # Check if octet is in valid range (0-255)
                    if [ $octet -gt 255 ]; then
                        valid_ip=false
                        break
                    fi

                    # Check for leading zeros (except for "0" itself)
                    if [ ${#octet} -gt 1 ] && [ "${octet:0:1}" = "0" ]; then
                        valid_ip=false
                        break
                    fi
                done

                if [ "$valid_ip" = true ]; then
                    log_info "✅ IP address $domain valid"
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

    # Check domain format
    if [[ "$domain" =~ $domain_regex ]]; then
        log_info "✅ Domain $domain valid"
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

# Fungsi untuk validasi port
validate_port() {
    local port="$1"
    local check_in_use="${2:-true}"

    # Check if empty
    if [ -z "$port" ]; then
        log_error "Port tidak boleh kosong!"
        return 1
    fi

    # Check if numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "Port harus berupa angka!"
        return 1
    fi

    # Check port range (1-65535)
    if [ $port -lt 1 ] || [ $port -gt 65535 ]; then
        log_error "Port harus dalam range 1-65535!"
        return 1
    fi

    # Warn about privileged ports
    if [ $port -lt 1024 ]; then
        log_warning "Port $port adalah privileged port (< 1024), memerlukan akses root"
    fi

    # Check if port is in use (if requested)
    if [ "$check_in_use" = true ]; then
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            log_error "Port $port sudah digunakan!"
            return 1
        fi
    fi

    log_info "✅ Port $port valid dan tersedia"
    return 0
}

# Fungsi untuk validasi nama app
validate_app_name() {
    local app_name="$1"

    # Check if empty
    if [ -z "$app_name" ]; then
        log_error "Nama app tidak boleh kosong!"
        return 1
    fi

    # Check length (MySQL identifier limit is 64 chars)
    if [ ${#app_name} -gt 60 ]; then
        log_error "Nama app terlalu panjang (maksimal 60 karakter)!"
        return 1
    fi

    # Check format (must start with letter, only letters, numbers, underscore)
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

    # Check reserved words
    local reserved_words=("mysql" "root" "admin" "test" "information_schema" "performance_schema" "sys")
    for reserved in "${reserved_words[@]}"; do
        if [ "${app_name,,}" = "${reserved,,}" ]; then
            log_error "Nama app '$app_name' adalah reserved word!"
            return 1
        fi
    done

    log_info "✅ Nama app '$app_name' valid"
    return 0
}

# Fungsi untuk check apakah command exists (idempotent)
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Fungsi untuk check apakah package terinstall (idempotent)
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Fungsi untuk check apakah systemd service exists
service_exists() {
    systemctl list-unit-files | grep -q "^$1.service"
}

# Function to calculate optimal FrankenPHP thread count
calculate_optimal_threads() {
    local cpu_cores=$(nproc)
    local available_memory_gb=$(free -g | awk 'NR==2{print $7}')
    local optimal_threads

    # Base calculation: Start with CPU cores
    if [ $cpu_cores -eq 1 ]; then
        # Single core: Use 2 threads to avoid blocking
        optimal_threads=2
    elif [ $cpu_cores -eq 2 ]; then
        # Dual core: Use 3 threads (1.5x cores)
        optimal_threads=3
    elif [ $cpu_cores -le 4 ]; then
        # Quad core or less: Use cores + 1
        optimal_threads=$((cpu_cores + 1))
    elif [ $cpu_cores -le 8 ]; then
        # 6-8 cores: Use cores + 2
        optimal_threads=$((cpu_cores + 2))
    else
        # High core count: Use 75% of cores + 4 (to avoid overloading)
        optimal_threads=$(((cpu_cores * 3 / 4) + 4))
    fi

    # Memory constraint check (each thread can use ~50-100MB)
    # Conservative estimate: 80MB per thread
    local max_threads_by_memory=$((available_memory_gb * 1024 / 80))

    # Use the lower of CPU-based or memory-based calculation
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

# Calculate optimal threads for this system
OPTIMAL_THREADS=$(calculate_optimal_threads)
log_info "Detected $(nproc) CPU cores, calculated optimal FrankenPHP threads: $OPTIMAL_THREADS"

# =============================================
# Resource Awareness System
# =============================================

# Resource constants and limits
MEMORY_SAFETY_MARGIN=20  # Reserve 20% of total memory
CPU_SAFETY_MARGIN=25     # Reserve 25% of total CPU
MIN_MEMORY_PER_APP=512   # Minimum MB per app
MAX_MEMORY_PER_APP=2048  # Maximum MB per app
MIN_CPU_PER_APP=0.5      # Minimum CPU cores per app
THREAD_MEMORY_USAGE=80   # Average MB per thread
MAX_APPS_PER_SERVER=10   # Hard limit for apps per server

# Function to get current system resources
get_system_resources() {
    local total_memory_mb=$(free -m | awk 'NR==2{print $2}')
    local available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    local total_cpu_cores=$(nproc)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    # Calculate usable resources (after safety margins)
    local usable_memory_mb=$(($total_memory_mb * (100 - $MEMORY_SAFETY_MARGIN) / 100))
    local usable_cpu_cores=$(echo "$total_cpu_cores * (100 - $CPU_SAFETY_MARGIN) / 100" | bc -l)

    echo "$total_memory_mb $available_memory_mb $total_cpu_cores $cpu_usage $usable_memory_mb $usable_cpu_cores"
}

# Function to count existing apps and their resource usage
get_app_resource_usage() {
    local total_apps=0
    local total_threads=0
    local total_memory_used=0
    local total_instances=0

    # Count main apps
    for config in /etc/laravel-apps/*.conf; do
        if [ -f "$config" ]; then
            source "$config"
            total_apps=$((total_apps + 1))

            # Count threads from Caddyfile if exists
            if [ -f "$APP_DIR/Caddyfile" ]; then
                local app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
                total_threads=$((total_threads + app_threads))
                total_memory_used=$((total_memory_used + (app_threads * THREAD_MEMORY_USAGE)))
            fi

            # Count scaled instances
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

# Smart thread allocation based on total apps
calculate_smart_threads() {
    local base_threads=$1
    local existing_apps=$2
    local total_memory_mb=$3
    local available_memory_mb=$4
    local total_cpu_cores=$5

    # Base allocation
    local smart_threads=$base_threads

    # Reduce threads based on number of existing apps
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
            smart_threads=$((smart_threads * 70 / 100))  # 30% reduction for 5+ apps
        elif [ $existing_apps -ge 3 ]; then
            smart_threads=$((smart_threads * 80 / 100))  # 20% reduction for 3-4 apps
        elif [ $existing_apps -ge 1 ]; then
            smart_threads=$((smart_threads * 90 / 100))  # 10% reduction for 1-2 apps
        fi
    fi

    # Ensure minimum viable threads
    if [ $smart_threads -lt 2 ]; then
        smart_threads=2
    fi

    echo $smart_threads
}

# Pre-flight resource check
preflight_resource_check() {
    local app_name=$1
    local github_repo=$2

    log_info "🔍 Running pre-flight resource check for $app_name..."

    # Get current system resources
    local resources=($(get_system_resources))
    local total_memory_mb=${resources[0]}
    local available_memory_mb=${resources[1]}
    local total_cpu_cores=${resources[2]}
    local cpu_usage=${resources[3]}
    local usable_memory_mb=${resources[4]}
    local usable_cpu_cores=${resources[5]}

    # Get current app usage
    local usage=($(get_app_resource_usage))
    local existing_apps=${usage[0]}
    local total_threads=${usage[1]}
    local total_memory_used=${usage[2]}
    local total_instances=${usage[3]}

    # Check hard limits
    if [ $existing_apps -ge $MAX_APPS_PER_SERVER ]; then
        log_error "❌ Hard limit reached: Maximum $MAX_APPS_PER_SERVER apps per server"
        log_error "   Current apps: $existing_apps"
        log_error "   Please scale horizontally or remove unused apps"
        return 1
    fi

    # Check memory availability
    local estimated_memory_needed=$(($MIN_MEMORY_PER_APP))
    if [ $available_memory_mb -lt $estimated_memory_needed ]; then
        log_error "❌ Insufficient memory available"
        log_error "   Available: ${available_memory_mb}MB"
        log_error "   Required: ${estimated_memory_needed}MB"
        log_error "   Currently used: ${total_memory_used}MB"
        return 1
    fi

    # Check CPU availability
    local cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)
    if [ $cpu_usage_int -gt 80 ]; then
        log_error "❌ High CPU usage detected: ${cpu_usage}%"
        log_error "   Please wait for CPU usage to decrease before creating new apps"
        return 1
    fi

    # Calculate smart threads for new app
    local smart_threads=$(calculate_smart_threads $(calculate_optimal_threads) $existing_apps $total_memory_mb $available_memory_mb $total_cpu_cores)

    # Warning system
    local memory_usage_percent=$(($total_memory_used * 100 / $total_memory_mb))
    local projected_memory_usage=$(($total_memory_used + ($smart_threads * $THREAD_MEMORY_USAGE)))
    local projected_memory_percent=$(($projected_memory_usage * 100 / $total_memory_mb))

    # Memory warnings
    if [ $projected_memory_percent -gt 80 ]; then
        log_warning "⚠️  High memory usage projected: ${projected_memory_percent}%"
        log_warning "   Consider reducing thread count or scaling horizontally"
    elif [ $projected_memory_percent -gt 70 ]; then
        log_warning "⚠️  Moderate memory usage projected: ${projected_memory_percent}%"
    fi

    # App count warnings
    if [ $existing_apps -ge 7 ]; then
        log_warning "⚠️  High app count: $existing_apps apps"
        log_warning "   Consider consolidating or scaling horizontally"
    elif [ $existing_apps -ge 5 ]; then
        log_warning "⚠️  Moderate app count: $existing_apps apps"
    fi

    # Success - display resource allocation
    log_info "✅ Pre-flight check passed!"
    log_info "📊 Resource allocation for $app_name:"
    log_info "   🧵 Threads: $smart_threads (optimized for $existing_apps existing apps)"
    log_info "   💾 Memory: ~$(($smart_threads * $THREAD_MEMORY_USAGE))MB"
    log_info "   📈 Projected total memory usage: ${projected_memory_percent}%"
    log_info "   🏗️  Total apps after creation: $((existing_apps + 1))"

    # Store smart threads for later use
    export SMART_THREADS=$smart_threads
    return 0
}

# Function to display resource warnings
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
        log_warning "⚠️  Server resource warnings:"
        if [ $memory_usage_percent -gt 80 ]; then
            log_warning "   💾 High memory usage: ${memory_usage_percent}%"
        fi
        if [ $cpu_usage_int -gt 80 ]; then
            log_warning "   🔥 High CPU usage: ${cpu_usage}%"
        fi
        if [ $existing_apps -gt 7 ]; then
            log_warning "   📱 High app count: $existing_apps apps"
        fi
        log_warning "   💡 Consider scaling horizontally or optimizing resources"
    fi
}

# =============================================
# 0. Configure Indonesia Mirror & Remove Apache (Idempotent)
# =============================================
log_info "Configuring Indonesia mirror servers..."

# Backup original sources.list
if [ ! -f /etc/apt/sources.list.backup ]; then
    log_info "Backing up original sources.list..."
    cp /etc/apt/sources.list /etc/apt/sources.list.backup
fi

# Detect Ubuntu version
UBUNTU_VERSION=$(lsb_release -cs)
log_info "Detected Ubuntu version: $UBUNTU_VERSION"

# Configure Indonesia mirror (using reliable Indonesia mirrors)
log_info "Configuring Indonesia mirror servers..."
cat > /etc/apt/sources.list <<EOF
# Indonesia Mirror - Fast and reliable mirrors for Indonesia
deb http://mirror.unej.ac.id/ubuntu/ $UBUNTU_VERSION main restricted universe multiverse
deb http://mirror.unej.ac.id/ubuntu/ $UBUNTU_VERSION-updates main restricted universe multiverse
deb http://mirror.unej.ac.id/ubuntu/ $UBUNTU_VERSION-backports main restricted universe multiverse
deb http://mirror.unej.ac.id/ubuntu/ $UBUNTU_VERSION-security main restricted universe multiverse

# Fallback to other Indonesia mirrors
deb http://buaya.klas.or.id/ubuntu/ $UBUNTU_VERSION main restricted universe multiverse
deb http://buaya.klas.or.id/ubuntu/ $UBUNTU_VERSION-updates main restricted universe multiverse
deb http://buaya.klas.or.id/ubuntu/ $UBUNTU_VERSION-backports main restricted universe multiverse
deb http://buaya.klas.or.id/ubuntu/ $UBUNTU_VERSION-security main restricted universe multiverse

# Ultimate fallback to official Ubuntu mirrors
deb http://archive.ubuntu.com/ubuntu/ $UBUNTU_VERSION main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $UBUNTU_VERSION-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $UBUNTU_VERSION-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ $UBUNTU_VERSION-security main restricted universe multiverse
EOF

# Remove Apache and related packages if installed
log_info "Removing Apache and conflicting web servers..."
APACHE_PACKAGES=(
    "apache2"
    "apache2-bin"
    "apache2-common"
    "apache2-data"
    "apache2-utils"
    "libapache2-mod-php*"
    "nginx"
    "nginx-common"
    "nginx-core"
)

for package in "\${APACHE_PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii.*$package"; then
        log_info "Removing $package..."
        apt remove --purge -y $package
    fi
done

# Stop and disable Apache/Nginx services if running
for service in apache2 nginx; do
    if systemctl is-active --quiet $service; then
        log_info "Stopping $service service..."
        systemctl stop $service
    fi
    if systemctl is-enabled --quiet $service 2>/dev/null; then
        log_info "Disabling $service service..."
        systemctl disable $service
    fi
done

# Clean up Apache/Nginx configuration directories
log_info "Cleaning up web server configurations..."
rm -rf /etc/apache2 /etc/nginx /var/www/html
log_info "✅ Apache and Nginx removed successfully"

# =============================================
# 1. System Update & Basic Packages (Idempotent)
# =============================================
log_info "Checking and updating system packages..."

# Update package list only if it's older than 1 hour
if [ ! -f /var/lib/apt/periodic/update-success-stamp ] || \
   [ $(find /var/lib/apt/periodic/update-success-stamp -mmin +60 | wc -l) -gt 0 ]; then
    log_info "Updating package list..."
    apt update
else
    log_info "Package list is up to date"
fi

# Upgrade packages only if needed
if [ $(apt list --upgradable 2>/dev/null | grep -c upgradable) -gt 1 ]; then
    log_info "Upgrading packages..."
    apt upgrade -y
else
    log_info "All packages are up to date"
fi

log_info "Installing essential packages (idempotent)..."
# Install packages only if not already installed
PACKAGES=(
    curl
    wget
    unzip
    git
    supervisor
    ufw
    htop
    nano
    jq
    net-tools
    software-properties-common
    apt-transport-https
    ca-certificates
    gnupg
    lsb-release
    bc
)

for package in "${PACKAGES[@]}"; do
    if ! package_installed "$package"; then
        log_info "Installing $package..."
        apt install -y "$package"
    else
        log_info "✅ $package already installed"
    fi
done

# =============================================
# 2. Install PHP 8.3+ & Extensions (Idempotent)
# =============================================
log_info "Installing PHP 8.3 and extensions for FrankenPHP..."

# Set environment to prevent Apache installation
export DEBIAN_FRONTEND=noninteractive

# Add PHP repository only if not already added
if ! grep -q "ondrej/php" /etc/apt/sources.list.d/*.list 2>/dev/null; then
    log_info "Adding PHP repository..."
    add-apt-repository -y ppa:ondrej/php
    apt update
else
    log_info "✅ PHP repository already added"
fi

# Prevent Apache installation by holding packages
log_info "Preventing Apache installation..."
apt-mark hold apache2 apache2-bin apache2-common apache2-data apache2-utils nginx nginx-common nginx-core 2>/dev/null || true

# Install PHP packages only if not already installed
PHP_PACKAGES=(
    php8.3
    php8.3-cli
    php8.3-common
    php8.3-curl
    php8.3-zip
    php8.3-gd
    php8.3-mysql
    php8.3-pgsql
    php8.3-sqlite3
    php8.3-xml
    php8.3-mbstring
    php8.3-bcmath
    php8.3-intl
    php8.3-redis
    php8.3-imagick
)

for package in "${PHP_PACKAGES[@]}"; do
    if ! package_installed "$package"; then
        log_info "Installing $package..."
        apt install -y "$package"
    else
        log_info "✅ $package already installed"
    fi
done

# Double check: Remove Apache if it was installed as dependency
log_info "Double-checking Apache removal..."
if dpkg -l | grep -q "^ii.*apache2"; then
    log_warning "⚠️  Apache was installed as dependency, removing it..."
    apt remove --purge -y apache2* libapache2-mod-php*
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
fi

# Unhold packages after installation
apt-mark unhold apache2 apache2-bin apache2-common apache2-data apache2-utils nginx nginx-common nginx-core 2>/dev/null || true

log_info "✅ PHP 8.3 installed without Apache"

# =============================================
# 3. Install Composer (Idempotent)
# =============================================
if ! command_exists composer; then
    log_info "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    log_info "✅ Composer installed successfully"
else
    log_info "✅ Composer already installed"
    composer --version
fi

# =============================================
# 4. Install Node.js & npm (Idempotent)
# =============================================
if ! command_exists node || [ $(node -v 2>/dev/null | cut -d'v' -f2 | cut -d'.' -f1) -lt 20 ]; then
    log_info "Installing Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
    log_info "✅ Node.js installed successfully"
else
    log_info "✅ Node.js already installed"
    node --version
    npm --version
fi

# =============================================
# 5. Install MySQL (Idempotent)
# =============================================
if ! package_installed mysql-server; then
    log_info "Installing MySQL 8.0..."
    apt install -y mysql-server

    # Generate root password with only alphanumeric characters
    MYSQL_ROOT_PASS="$(openssl rand -base64 32 | tr -d '/+=\n' | head -c 32)"

    # Secure MySQL installation
    mysql_secure_installation <<EOF

y
2
$MYSQL_ROOT_PASS
$MYSQL_ROOT_PASS
y
y
y
y
EOF

    # Save MySQL root credentials
    echo "MYSQL_ROOT_PASS=$MYSQL_ROOT_PASS" > /root/.mysql_credentials
    chmod 600 /root/.mysql_credentials
    log_info "✅ MySQL installed and secured"
else
    log_info "✅ MySQL already installed"
    # Check if credentials file exists
    if [ ! -f /root/.mysql_credentials ]; then
        log_warning "⚠️  MySQL credentials file not found!"
        log_warning "   You may need to manually set MySQL root password"
    else
        log_info "✅ MySQL credentials file exists"
    fi
fi

# =============================================
# 6. Install Redis (Idempotent)
# =============================================
if ! package_installed redis-server; then
    log_info "Installing Redis..."
    apt install -y redis-server
    systemctl enable redis-server
    systemctl start redis-server

    # Configure Redis for multi-app usage
    sed -i 's/^# maxmemory <bytes>/maxmemory 512mb/' /etc/redis/redis.conf
    sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
    systemctl restart redis-server
    log_info "✅ Redis installed and configured"
else
    log_info "✅ Redis already installed"
    # Ensure Redis is running
    if ! systemctl is-active --quiet redis-server; then
        log_info "Starting Redis service..."
        systemctl start redis-server
    fi
fi

# =============================================
# 7. Setup Base Directory Structure (Idempotent)
# =============================================
log_info "Setting up base directory structure..."

# Create directories only if they don't exist
DIRECTORIES=(
    "$APPS_BASE_DIR"
    "/var/log/frankenphp"
    "/var/backups/laravel-apps"
    "/etc/laravel-apps"
)

for dir in "${DIRECTORIES[@]}"; do
    if [ ! -d "$dir" ]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir"
    else
        log_info "✅ Directory already exists: $dir"
    fi
done

# Set ownership
chown -R www-data:www-data $APPS_BASE_DIR
chown -R www-data:www-data /var/log/frankenphp
chown -R www-data:www-data /var/backups/laravel-apps

# =============================================
# 8. Check Port Availability & Configure Firewall (Idempotent)
# =============================================
log_info "Checking port availability..."

# Check if ports 80 and 443 are free
PORTS_TO_CHECK=("80" "443")
for port in "${PORTS_TO_CHECK[@]}"; do
    if netstat -tlnp | grep -q ":$port "; then
        local process=$(netstat -tlnp | grep ":$port " | awk '{print $7}' | cut -d'/' -f2 | head -1)
        log_warning "⚠️  Port $port is being used by: $process"

        # If it's Apache or Nginx, try to stop it
        if [[ "$process" == "apache2" || "$process" == "nginx" ]]; then
            log_info "Stopping $process to free port $port..."
            systemctl stop $process 2>/dev/null || true
            systemctl disable $process 2>/dev/null || true
        fi
    else
        log_info "✅ Port $port is available"
    fi
done

log_info "Configuring firewall..."

# Enable firewall if not already enabled
if ! ufw status | grep -q "Status: active"; then
    log_info "Enabling firewall..."
    ufw --force enable
else
    log_info "✅ Firewall already enabled"
fi

# Add rules only if they don't exist
FIREWALL_RULES=(
    "22/tcp"
    "80/tcp"
    "443/tcp"
)

for rule in "${FIREWALL_RULES[@]}"; do
    if ! ufw status | grep -q "$rule"; then
        log_info "Adding firewall rule: $rule"
        ufw allow $rule
    else
        log_info "✅ Firewall rule already exists: $rule"
    fi
done

# =============================================
# 9. Create FrankenPHP Management Scripts
# =============================================
log_info "Creating FrankenPHP management scripts..."

# Create app creation script
cat > /usr/local/bin/create-laravel-app <<'EOF'
#!/bin/bash

set -e

# Global variables for rollback
ROLLBACK_NEEDED=false
CREATED_DATABASE=""
CREATED_DB_USER=""
CREATED_APP_DIR=""
CREATED_CONFIG_FILE=""
CREATED_SERVICE_FILE=""
CREATED_HTTP_SERVICE_FILE=""
CREATED_SUPERVISOR_FILE=""
CREATED_CRON_JOBS=""
CURRENT_APP_NAME=""

# Rollback function
rollback_deployment() {
    local app_name="$1"

    if [ "$ROLLBACK_NEEDED" = true ]; then
        log_error "❌ Deployment failed! Starting rollback for $app_name..."

        # Stop and remove service
        if [ -n "$CREATED_SERVICE_FILE" ]; then
            systemctl stop frankenphp-$app_name 2>/dev/null || true
            systemctl disable frankenphp-$app_name 2>/dev/null || true
            rm -f "$CREATED_SERVICE_FILE"
            log_info "✅ Removed service file"
        fi

        # Remove supervisor config
        if [ -n "$CREATED_SUPERVISOR_FILE" ]; then
            rm -f "$CREATED_SUPERVISOR_FILE"
            supervisorctl reread 2>/dev/null || true
            supervisorctl update 2>/dev/null || true
            log_info "✅ Removed supervisor config"
        fi

        # Remove cron jobs
        if [ -n "$CREATED_CRON_JOBS" ]; then
            crontab -u www-data -l 2>/dev/null | grep -v "$app_name" | crontab -u www-data - 2>/dev/null || true
            log_info "✅ Removed cron jobs"
        fi

        # Remove database and user
        if [ -n "$CREATED_DATABASE" ] && [ -n "$CREATED_DB_USER" ]; then
            source /root/.mysql_credentials 2>/dev/null || true
            if [ -n "$MYSQL_ROOT_PASS" ]; then
                mysql -u root -p$MYSQL_ROOT_PASS <<MYSQL_EOF 2>/dev/null || true
DROP DATABASE IF EXISTS \`$CREATED_DATABASE\`;
DROP USER IF EXISTS '$CREATED_DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF
                log_info "✅ Removed database and user"
            fi
        fi

        # Remove app directory
        if [ -n "$CREATED_APP_DIR" ] && [ -d "$CREATED_APP_DIR" ]; then
            rm -rf "$CREATED_APP_DIR"
            log_info "✅ Removed app directory"
        fi

        # Remove config file
        if [ -n "$CREATED_CONFIG_FILE" ]; then
            rm -f "$CREATED_CONFIG_FILE"
            log_info "✅ Removed config file"
        fi

        systemctl daemon-reload 2>/dev/null || true

        log_info "🔄 Rollback completed for $app_name"
        exit 1
    fi
}

# Error trap function
error_handler() {
    local exit_code=$?
    local line_number=$1
    log_error "❌ Error occurred at line $line_number (exit code: $exit_code)"

    if [ -n "$CURRENT_APP_NAME" ]; then
        ROLLBACK_NEEDED=true
        rollback_deployment "$CURRENT_APP_NAME"
    fi

    exit $exit_code
}

# Set up error trap
trap 'error_handler $LINENO' ERR

if [ $# -lt 2 ]; then
    echo "Usage: $0 <app-name> <domain> [github-repo] [db-name]"
    echo "Example: $0 web_sam testingsetup.rizqis.com"
    echo "Example: $0 web_sam testingsetup.rizqis.com https://github.com/CompleteLabs/web-app-sam.git"
    echo "Example: $0 web_crm_app crm.mydomain.com https://github.com/user/laravel-crm.git"
    exit 1
fi

APP_NAME="$1"
DOMAIN="$2"
GITHUB_REPO="$3"
DB_NAME="${4:-${APP_NAME}_db}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Resource constants and limits
MEMORY_SAFETY_MARGIN=20  # Reserve 20% of total memory
CPU_SAFETY_MARGIN=25     # Reserve 25% of total CPU
MIN_MEMORY_PER_APP=512   # Minimum MB per app
MAX_MEMORY_PER_APP=2048  # Maximum MB per app
MIN_CPU_PER_APP=0.5      # Minimum CPU cores per app
THREAD_MEMORY_USAGE=80   # Average MB per thread
MAX_APPS_PER_SERVER=10   # Hard limit for apps per server

# Function to get current system resources
get_system_resources() {
    local total_memory_mb=$(free -m | awk 'NR==2{print $2}')
    local available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    local total_cpu_cores=$(nproc)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    # Calculate usable resources (after safety margins)
    local usable_memory_mb=$(($total_memory_mb * (100 - $MEMORY_SAFETY_MARGIN) / 100))
    local usable_cpu_cores=$(echo "$total_cpu_cores * (100 - $CPU_SAFETY_MARGIN) / 100" | bc -l)

    echo "$total_memory_mb $available_memory_mb $total_cpu_cores $cpu_usage $usable_memory_mb $usable_cpu_cores"
}

# Function to count existing apps and their resource usage
get_app_resource_usage() {
    local total_apps=0
    local total_threads=0
    local total_memory_used=0
    local total_instances=0

    # Count main apps
    for config in /etc/laravel-apps/*.conf; do
        if [ -f "$config" ]; then
            source "$config"
            total_apps=$((total_apps + 1))

            # Count threads from Caddyfile if exists
            if [ -f "$APP_DIR/Caddyfile" ]; then
                local app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
                total_threads=$((total_threads + app_threads))
                total_memory_used=$((total_memory_used + (app_threads * THREAD_MEMORY_USAGE)))
            fi

            # Count scaled instances
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

# Smart thread allocation based on total apps
calculate_smart_threads() {
    local base_threads=$1
    local existing_apps=$2
    local total_memory_mb=$3
    local available_memory_mb=$4
    local total_cpu_cores=$5

    # Base allocation
    local smart_threads=$base_threads

    # Reduce threads based on number of existing apps
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
            smart_threads=$((smart_threads * 70 / 100))  # 30% reduction for 5+ apps
        elif [ $existing_apps -ge 3 ]; then
            smart_threads=$((smart_threads * 80 / 100))  # 20% reduction for 3-4 apps
        elif [ $existing_apps -ge 1 ]; then
            smart_threads=$((smart_threads * 90 / 100))  # 10% reduction for 1-2 apps
        fi
    fi

    # Ensure minimum viable threads
    if [ $smart_threads -lt 2 ]; then
        smart_threads=2
    fi

    echo $smart_threads
}

# Pre-flight resource check
preflight_resource_check() {
    local app_name=$1
    local github_repo=$2

    log_info "🔍 Running pre-flight resource check for $app_name..."

    # Get current system resources
    local resources=($(get_system_resources))
    local total_memory_mb=${resources[0]}
    local available_memory_mb=${resources[1]}
    local total_cpu_cores=${resources[2]}
    local cpu_usage=${resources[3]}
    local usable_memory_mb=${resources[4]}
    local usable_cpu_cores=${resources[5]}

    # Get current app usage
    local usage=($(get_app_resource_usage))
    local existing_apps=${usage[0]}
    local total_threads=${usage[1]}
    local total_memory_used=${usage[2]}
    local total_instances=${usage[3]}

    # Check hard limits
    if [ $existing_apps -ge $MAX_APPS_PER_SERVER ]; then
        log_error "❌ Hard limit reached: Maximum $MAX_APPS_PER_SERVER apps per server"
        log_error "   Current apps: $existing_apps"
        log_error "   Please scale horizontally or remove unused apps"
        return 1
    fi

    # Check memory availability
    local estimated_memory_needed=$(($MIN_MEMORY_PER_APP))
    if [ $available_memory_mb -lt $estimated_memory_needed ]; then
        log_error "❌ Insufficient memory available"
        log_error "   Available: ${available_memory_mb}MB"
        log_error "   Required: ${estimated_memory_needed}MB"
        log_error "   Currently used: ${total_memory_used}MB"
        return 1
    fi

    # Check CPU availability
    local cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)
    if [ $cpu_usage_int -gt 80 ]; then
        log_error "❌ High CPU usage detected: ${cpu_usage}%"
        log_error "   Please wait for CPU usage to decrease before creating new apps"
        return 1
    fi

    # Calculate smart threads for new app
    local smart_threads=$(calculate_smart_threads $(calculate_optimal_threads) $existing_apps $total_memory_mb $available_memory_mb $total_cpu_cores)

    # Warning system
    local memory_usage_percent=$(($total_memory_used * 100 / $total_memory_mb))
    local projected_memory_usage=$(($total_memory_used + ($smart_threads * $THREAD_MEMORY_USAGE)))
    local projected_memory_percent=$(($projected_memory_usage * 100 / $total_memory_mb))

    # Memory warnings
    if [ $projected_memory_percent -gt 80 ]; then
        log_warning "⚠️  High memory usage projected: ${projected_memory_percent}%"
        log_warning "   Consider reducing thread count or scaling horizontally"
    elif [ $projected_memory_percent -gt 70 ]; then
        log_warning "⚠️  Moderate memory usage projected: ${projected_memory_percent}%"
    fi

    # App count warnings
    if [ $existing_apps -ge 7 ]; then
        log_warning "⚠️  High app count: $existing_apps apps"
        log_warning "   Consider consolidating or scaling horizontally"
    elif [ $existing_apps -ge 5 ]; then
        log_warning "⚠️  Moderate app count: $existing_apps apps"
    fi

    # Success - display resource allocation
    log_info "✅ Pre-flight check passed!"
    log_info "📊 Resource allocation for $app_name:"
    log_info "   🧵 Threads: $smart_threads (optimized for $existing_apps existing apps)"
    log_info "   💾 Memory: ~$(($smart_threads * $THREAD_MEMORY_USAGE))MB"
    log_info "   📈 Projected total memory usage: ${projected_memory_percent}%"
    log_info "   🏗️  Total apps after creation: $((existing_apps + 1))"

    # Store smart threads for later use
    export SMART_THREADS=$smart_threads
    return 0
}

# Function to calculate optimal FrankenPHP thread count
calculate_optimal_threads() {
    local cpu_cores=$(nproc)
    local available_memory_gb=$(free -g | awk 'NR==2{print $7}')
    local optimal_threads

    # Base calculation: Start with CPU cores
    if [ $cpu_cores -eq 1 ]; then
        # Single core: Use 2 threads to avoid blocking
        optimal_threads=2
    elif [ $cpu_cores -eq 2 ]; then
        # Dual core: Use 3 threads (1.5x cores)
        optimal_threads=3
    elif [ $cpu_cores -le 4 ]; then
        # Quad core or less: Use cores + 1
        optimal_threads=$((cpu_cores + 1))
    elif [ $cpu_cores -le 8 ]; then
        # 6-8 cores: Use cores + 2
        optimal_threads=$((cpu_cores + 2))
    else
        # High core count: Use 75% of cores + 4 (to avoid overloading)
        optimal_threads=$(((cpu_cores * 3 / 4) + 4))
    fi

    # Memory constraint check (each thread can use ~50-100MB)
    # Conservative estimate: 80MB per thread
    local max_threads_by_memory=$((available_memory_gb * 1024 / 80))

    # Use the lower of CPU-based or memory-based calculation
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

# Import validation functions from main script
source /usr/local/bin/frankenphp-multiapp-deployer.sh 2>/dev/null || true

# If functions not available, define them here
if ! type validate_app_name &>/dev/null; then
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
            if [ "${app_name,,}" = "${reserved,,}" ]; then
                log_error "Nama app '$app_name' adalah reserved word!"
                return 1
            fi
        done

        log_info "✅ Nama app '$app_name' valid"
        return 0
    }

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
            log_info "✅ Domain localhost valid"
            return 0
        fi

        # Check if IP address (only digits and dots)
        if [[ "$domain" =~ ^[0-9.]+$ ]]; then
            # Count dots - should be exactly 3
            local dot_count=$(echo "$domain" | tr -cd '.' | wc -c)
            if [ $dot_count -eq 3 ]; then
                # Validate IP octets
                local valid_ip=true
                IFS='.' read -ra OCTETS <<< "$domain"

                # Check exactly 4 octets
                if [ ${#OCTETS[@]} -ne 4 ]; then
                    log_error "IP address $domain tidak valid!"
                    return 1
                fi

                for octet in "${OCTETS[@]}"; do
                    # Check if octet is empty
                    if [ -z "$octet" ]; then
                        valid_ip=false
                        break
                    fi

                    # Check if octet is numeric
                    if ! [[ "$octet" =~ ^[0-9]+$ ]]; then
                        valid_ip=false
                        break
                    fi

                    # Check if octet is in valid range (0-255)
                    if [ $octet -gt 255 ]; then
                        valid_ip=false
                        break
                    fi

                    # Check for leading zeros (except for "0" itself)
                    if [ ${#octet} -gt 1 ] && [ "${octet:0:1}" = "0" ]; then
                        valid_ip=false
                        break
                    fi
                done

                if [ "$valid_ip" = true ]; then
                    log_info "✅ IP address $domain valid"
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

        if [[ "$domain" =~ $domain_regex ]]; then
            log_info "✅ Domain $domain valid"
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
fi

# Validate app name
if ! validate_app_name "$APP_NAME"; then
    exit 1
fi

# Validate domain
if ! validate_domain "$DOMAIN"; then
    exit 1
fi

APPS_BASE_DIR="/opt/laravel-apps"
APP_DIR="$APPS_BASE_DIR/$APP_NAME"

# Function to calculate optimal FrankenPHP thread count
calculate_optimal_threads() {
    local cpu_cores=$(nproc)
    local available_memory_gb=$(free -g | awk 'NR==2{print $7}')
    local optimal_threads

    # Base calculation: Start with CPU cores
    if [ $cpu_cores -eq 1 ]; then
        # Single core: Use 2 threads to avoid blocking
        optimal_threads=2
    elif [ $cpu_cores -eq 2 ]; then
        # Dual core: Use 3 threads (1.5x cores)
        optimal_threads=3
    elif [ $cpu_cores -le 4 ]; then
        # Quad core or less: Use cores + 1
        optimal_threads=$((cpu_cores + 1))
    elif [ $cpu_cores -le 8 ]; then
        # 6-8 cores: Use cores + 2
        optimal_threads=$((cpu_cores + 2))
    else
        # High core count: Use 75% of cores + 4 (to avoid overloading)
        optimal_threads=$(((cpu_cores * 3 / 4) + 4))
    fi

    # Memory constraint check (each thread can use ~50-100MB)
    # Conservative estimate: 80MB per thread
    local max_threads_by_memory=$((available_memory_gb * 1024 / 80))

    # Use the lower of CPU-based or memory-based calculation
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

# Calculate optimal threads for this system (will be overridden by smart threads)
OPTIMAL_THREADS=$(calculate_optimal_threads)

# Use smart threads if available (from pre-flight check)
if [ -n "$SMART_THREADS" ]; then
    OPTIMAL_THREADS=$SMART_THREADS
fi

# Check if app already exists
if [ -d "$APP_DIR" ]; then
    log_error "App $APP_NAME already exists!"
    exit 1
fi

# Run pre-flight resource check
if ! preflight_resource_check "$APP_NAME" "$GITHUB_REPO"; then
    log_error "Pre-flight check failed! Cannot create app."
    exit 1
fi

log_info "Creating FrankenPHP Laravel app: $APP_NAME"
log_info "Domain: $DOMAIN"
log_info "Database: $DB_NAME"
if [ -n "$GITHUB_REPO" ]; then
    log_info "GitHub Repository: $GITHUB_REPO"
fi

# Set current app name for rollback
export CURRENT_APP_NAME="$APP_NAME"

# Create app directory
mkdir -p $APP_DIR
CREATED_APP_DIR="$APP_DIR"
chown www-data:www-data $APP_DIR

# Generate database credentials
DB_USER="${APP_NAME}_user"
# Generate password with only alphanumeric characters to avoid sed issues
DB_PASS="$(openssl rand -base64 32 | tr -d '/+=\n' | head -c 32)"

# Clean DB_NAME to be MySQL compatible (replace - with _)
DB_NAME_CLEAN=$(echo $DB_NAME | sed 's/-/_/g')

# Get MySQL root password
if [ ! -f /root/.mysql_credentials ]; then
    log_error "MySQL credentials file not found!"
    log_error "Please run the main deployment script first"
    exit 1
fi
source /root/.mysql_credentials

# Check if database already exists
DB_EXISTS=$(mysql -u root -p$MYSQL_ROOT_PASS -e "SHOW DATABASES LIKE '$DB_NAME_CLEAN';" 2>/dev/null | grep -c "$DB_NAME_CLEAN" || echo "0")

# Create database and user
mysql -u root -p$MYSQL_ROOT_PASS <<MYSQL_EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME_CLEAN\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME_CLEAN\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF

# Track created database only if it was newly created
if [ "$DB_EXISTS" = "0" ]; then
    CREATED_DATABASE="$DB_NAME_CLEAN"
    CREATED_DB_USER="$DB_USER"
fi

# Save app configuration
cat > /etc/laravel-apps/$APP_NAME.conf <<CONFIG_EOF
APP_NAME=$APP_NAME
APP_DIR=$APP_DIR
DOMAIN=$DOMAIN
DB_NAME=$DB_NAME_CLEAN
DB_USER=$DB_USER
DB_PASS=$DB_PASS
GITHUB_REPO=$GITHUB_REPO
CONFIG_EOF
CREATED_CONFIG_FILE="/etc/laravel-apps/$APP_NAME.conf"

# Clone Laravel app from GitHub or create new Laravel project
if [ -n "$GITHUB_REPO" ]; then
    log_info "Cloning Laravel app from GitHub..."
    cd $APP_DIR
    git clone $GITHUB_REPO .
    chown -R www-data:www-data $APP_DIR

    # Setup Laravel environment
    log_info "Setting up Laravel environment..."

    # Copy .env.example to .env if exists
    if [ -f ".env.example" ]; then
        cp .env.example .env
        log_info "✅ Created .env from .env.example"
    else
        log_info "⚠️  No .env.example found, creating basic .env"
        cat > .env <<ENV_EOF
APP_NAME=Laravel
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://$DOMAIN

LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$DB_NAME_CLEAN
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS

BROADCAST_DRIVER=log
CACHE_DRIVER=redis
FILESYSTEM_DRIVER=local
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="\${APP_NAME}"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=
AWS_USE_PATH_STYLE_ENDPOINT=false

PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_HOST=
PUSHER_PORT=443
PUSHER_SCHEME=https
PUSHER_APP_CLUSTER=mt1

VITE_PUSHER_APP_KEY="\${PUSHER_APP_KEY}"
VITE_PUSHER_HOST="\${PUSHER_HOST}"
VITE_PUSHER_PORT="\${PUSHER_PORT}"
VITE_PUSHER_SCHEME="\${PUSHER_SCHEME}"
VITE_PUSHER_APP_CLUSTER="\${PUSHER_APP_CLUSTER}"
ENV_EOF
    fi

    # Update database credentials in .env
    log_info "Updating database credentials in .env..."
    # Use a safer approach to update .env file to handle special characters in password

    # Create a backup of original .env
    cp .env .env.backup

    # Use a safe method to update .env file
    {
        # Read the original .env file and update values
        while IFS= read -r line; do
            case "$line" in
                DB_DATABASE=*)
                    echo "DB_DATABASE=$DB_NAME_CLEAN"
                    ;;
                DB_USERNAME=*)
                    echo "DB_USERNAME=$DB_USER"
                    ;;
                DB_PASSWORD=*)
                    echo "DB_PASSWORD=$DB_PASS"
                    ;;
                APP_URL=*)
                    echo "APP_URL=https://$DOMAIN"
                    ;;
                *)
                    echo "$line"
                    ;;
            esac
        done < .env.backup
    } > .env

    # Remove backup file
    rm -f .env.backup

    # Install dependencies if composer.json exists
    if [ -f "composer.json" ]; then
        log_info "Installing Composer dependencies..."
        composer install --no-dev --optimize-autoloader

        # Generate Laravel app key
        php artisan key:generate
        log_info "✅ Laravel app key generated"
    else
        log_info "⚠️  No composer.json found, skipping composer install"
    fi

    # Install npm dependencies if package.json exists
    if [ -f "package.json" ]; then
        log_info "Installing NPM dependencies..."
        npm ci

        # Check for build scripts
        if npm run --silent 2>&1 | grep -q "build"; then
            log_info "Building frontend assets..."
            npm run build
            log_info "✅ Frontend assets built"
        else
            log_info "⚠️  No build script found, skipping npm build"
        fi
    else
        log_info "⚠️  No package.json found, skipping npm install"
    fi

    # Run database migrations if available
    if [ -f "artisan" ]; then
        log_info "Running database migrations..."
        php artisan migrate --force || log_info "⚠️  Migration failed or no migrations to run"

        # Clear and cache configurations
        php artisan config:clear
        php artisan config:cache
        php artisan route:clear
        php artisan route:cache
        php artisan view:clear
        php artisan view:cache

        log_info "✅ Laravel optimizations completed"
    fi

    # Set proper permissions
    chown -R www-data:www-data $APP_DIR
    chmod -R 755 $APP_DIR

    # Create storage and cache directories if they don't exist
    mkdir -p $APP_DIR/storage/logs
    mkdir -p $APP_DIR/bootstrap/cache
    chmod -R 775 $APP_DIR/storage $APP_DIR/bootstrap/cache
    chown -R www-data:www-data $APP_DIR/storage $APP_DIR/bootstrap/cache

    log_info "✅ Laravel app cloned and configured successfully"
else
    log_info "⚠️  No GitHub repository provided, creating empty directory"
    log_info "   You can manually deploy your Laravel app to: $APP_DIR"
fi

# Note: No Caddyfile needed for Laravel Octane FrankenPHP native deployment
# Laravel Octane FrankenPHP handles HTTPS, HTTP/2, HTTP/3 natively via octane:frankenphp command
log_info "📝 Using native Laravel Octane FrankenPHP deployment (no Caddyfile needed)"
log_info "   HTTPS, HTTP/2, HTTP/3, and auto SSL certificates handled natively"

# Create systemd service
if [ -f "$APP_DIR/artisan" ]; then
    # Laravel Octane service
    cat > /etc/systemd/system/frankenphp-$APP_NAME.service <<SERVICE_EOF
[Unit]
Description=Laravel Octane FrankenPHP Server for $APP_NAME
After=network.target mysql.service redis.service
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/php artisan octane:frankenphp --host=$DOMAIN --port=443 --https --workers=$OPTIMAL_THREADS --max-requests=1000 --log-level=info
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=10
Restart=always
RestartSec=5
SyslogIdentifier=octane-$APP_NAME

Environment=APP_ENV=production
Environment=APP_DEBUG=false

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768

# Security settings - disabled to prevent namespace conflicts
# NoNewPrivileges, PrivateTmp, ProtectSystem, ProtectHome disabled
# to avoid systemd namespace issues (exit code 226/NAMESPACE)

[Install]
WantedBy=multi-user.target
SERVICE_EOF
else
    # Standalone FrankenPHP service
    cat > /etc/systemd/system/frankenphp-$APP_NAME.service <<SERVICE_EOF
[Unit]
Description=FrankenPHP Web Server for $APP_NAME
After=network.target mysql.service redis.service
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/frankenphp run --config Caddyfile
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=10
Restart=always
RestartSec=5
SyslogIdentifier=frankenphp-$APP_NAME

Environment=APP_ENV=production
Environment=APP_DEBUG=false

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768

# Security settings - disabled to prevent namespace conflicts
# NoNewPrivileges, PrivateTmp, ProtectSystem, ProtectHome disabled
# to avoid systemd namespace issues (exit code 226/NAMESPACE)

[Install]
WantedBy=multi-user.target
SERVICE_EOF
fi
CREATED_SERVICE_FILE="/etc/systemd/system/frankenphp-$APP_NAME.service"

# Create supervisor config for queue workers
cat > /etc/supervisor/conf.d/laravel-worker-$APP_NAME.conf <<SUPERVISOR_EOF
[program:laravel-worker-$APP_NAME]
process_name=%(program_name)s_%(process_num)02d
command=php $APP_DIR/artisan queue:work --sleep=3 --tries=3 --max-time=3600
directory=$APP_DIR
user=www-data
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
numprocs=2
redirect_stderr=true
stdout_logfile=$APP_DIR/storage/logs/worker.log
stopwaitsecs=3600
SUPERVISOR_EOF
CREATED_SUPERVISOR_FILE="/etc/supervisor/conf.d/laravel-worker-$APP_NAME.conf"

# Install Laravel Octane with FrankenPHP
if [ -f "artisan" ]; then
    log_info "🚀 Installing Laravel Octane with FrankenPHP..."

    # Install Octane if not already installed
    if ! grep -q "laravel/octane" composer.json; then
        log_info "📦 Installing Laravel Octane package..."
        if ! composer require laravel/octane; then
            log_error "Failed to install Laravel Octane package"
            exit 1
        fi
        log_info "✅ Laravel Octane package installed successfully"
    else
        log_info "✅ Laravel Octane package already installed"
    fi

    # Install FrankenPHP via Octane (automatically downloads binary)
    log_info "⬇️  Installing FrankenPHP via Laravel Octane..."
    log_info "This will automatically download the correct FrankenPHP binary for your system"

    # Run octane:install with proper error handling
    if php artisan octane:install --server=frankenphp --force; then
        log_info "✅ FrankenPHP installed successfully via Laravel Octane"
    else
        log_error "Failed to install FrankenPHP via Laravel Octane"
        log_info "This might be due to:"
        log_info "  - Network connectivity issues"
        log_info "  - GitHub API rate limits"
        log_info "  - Unsupported architecture"
        exit 1
    fi

    # Publish Octane config if needed
    if [ ! -f "config/octane.php" ]; then
        log_info "📝 Publishing Octane configuration..."
        php artisan vendor:publish --provider="Laravel\Octane\OctaneServiceProvider" --tag=config
        log_info "✅ Octane configuration published"
    else
        log_info "✅ Octane configuration already exists"
    fi

    # Verify FrankenPHP installation
    if [ -f "frankenphp" ]; then
        log_info "✅ FrankenPHP binary found in app directory"
        chmod +x frankenphp
        chown www-data:www-data frankenphp
    else
        log_warning "⚠️  FrankenPHP binary not found in app directory"
        log_info "Laravel Octane might have installed it in a different location"
    fi

    log_info "✅ Laravel Octane with FrankenPHP setup completed successfully"
else
    log_info "⚠️  No artisan file found, this is not a Laravel project"
    log_info "Falling back to manual FrankenPHP binary download..."

    # Fallback to manual download if not a Laravel project
    if [ ! -f "$APP_DIR/frankenphp" ]; then
        log_info "📥 Downloading FrankenPHP binary manually..."
        cd $APP_DIR

        # Detect architecture
        ARCH=$(uname -m)
        case $ARCH in
            x86_64)
                FRANKEN_ARCH="x86_64"
                ;;
            aarch64|arm64)
                FRANKEN_ARCH="aarch64"
                ;;
            *)
                log_error "Unsupported architecture: $ARCH"
                exit 1
                ;;
        esac

        # Download latest FrankenPHP with improved error handling
        log_info "🔍 Getting latest FrankenPHP version..."

        # Try multiple methods to get version (compatible with different systems)
        FRANKEN_VERSION=""

        # Method 1: Using sed (most portable)
        if [ -z "$FRANKEN_VERSION" ]; then
            FRANKEN_VERSION=$(curl -sL https://api.github.com/repos/php/frankenphp/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
        fi

        # Method 2: Using awk as fallback
        if [ -z "$FRANKEN_VERSION" ]; then
            FRANKEN_VERSION=$(curl -sL https://api.github.com/repos/php/frankenphp/releases/latest | awk -F'"' '/"tag_name"/ {print $4; exit}')
        fi

        # Method 3: Using python if available
        if [ -z "$FRANKEN_VERSION" ] && command -v python3 >/dev/null 2>&1; then
            FRANKEN_VERSION=$(curl -sL https://api.github.com/repos/php/frankenphp/releases/latest | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "")
        fi

        # Fallback to known working version
        if [ -z "$FRANKEN_VERSION" ]; then
            log_warning "⚠️  Failed to get latest version from GitHub API, using fallback version"
            FRANKEN_VERSION="v1.8.0"
        fi

        FRANKEN_URL="https://github.com/php/frankenphp/releases/download/${FRANKEN_VERSION}/frankenphp-linux-${FRANKEN_ARCH}"

        log_info "📥 Downloading FrankenPHP ${FRANKEN_VERSION} for ${FRANKEN_ARCH}..."
        log_info "URL: $FRANKEN_URL"

        # Try wget first, then curl as fallback
        if command -v wget >/dev/null 2>&1; then
            if ! wget -O frankenphp "$FRANKEN_URL"; then
                log_warning "wget failed, trying curl..."
                if ! curl -L -o frankenphp "$FRANKEN_URL"; then
                    log_error "Both wget and curl failed to download FrankenPHP binary"
                    log_error "Please check your internet connection and try again"
                    exit 1
                fi
            fi
        else
            if ! curl -L -o frankenphp "$FRANKEN_URL"; then
                log_error "curl failed to download FrankenPHP binary"
                log_error "Please check your internet connection and try again"
                exit 1
            fi
        fi

        # Verify download
        if [ ! -f "frankenphp" ] || [ ! -s "frankenphp" ]; then
            log_error "Downloaded FrankenPHP binary is empty or missing"
            exit 1
        fi

        chmod +x frankenphp
        chown www-data:www-data frankenphp

        log_info "✅ FrankenPHP binary downloaded successfully: $FRANKEN_VERSION"
    else
        log_info "✅ FrankenPHP binary already exists"
    fi
fi

# Setup cron for Laravel scheduler
(crontab -u www-data -l 2>/dev/null; echo "* * * * * cd $APP_DIR && php artisan schedule:run >> /dev/null 2>&1") | crontab -u www-data -
CREATED_CRON_JOBS="$APP_NAME"

# Create HTTP redirect service for port 80 (Laravel apps only)
if [ -f "$APP_DIR/artisan" ]; then
    log_info "📝 Creating HTTP redirect service for port 80..."
    cat > /etc/systemd/system/frankenphp-$APP_NAME-http.service <<HTTP_SERVICE_EOF
[Unit]
Description=Laravel Octane FrankenPHP HTTP Server for $APP_NAME (Redirect to HTTPS)
After=network.target mysql.service redis.service
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/php artisan octane:frankenphp --host=$DOMAIN --port=80 --http-redirect --workers=2 --log-level=info
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=10
Restart=always
RestartSec=5
SyslogIdentifier=octane-$APP_NAME-http

Environment=APP_ENV=production
Environment=APP_DEBUG=false

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768

# Security settings - disabled to prevent namespace conflicts
# NoNewPrivileges, PrivateTmp, ProtectSystem, ProtectHome disabled
# to avoid systemd namespace issues (exit code 226/NAMESPACE)

[Install]
WantedBy=multi-user.target
HTTP_SERVICE_EOF
    CREATED_HTTP_SERVICE_FILE="/etc/systemd/system/frankenphp-$APP_NAME-http.service"
    log_info "✅ HTTP redirect service created"
fi

# Reload services
systemctl daemon-reload
systemctl enable frankenphp-$APP_NAME
if [ -f "$APP_DIR/artisan" ]; then
    systemctl enable frankenphp-$APP_NAME-http
fi
supervisorctl reread && supervisorctl update

log_info "✅ FrankenPHP Laravel app $APP_NAME created successfully!"
log_info "📁 Directory: $APP_DIR"
log_info "🌐 Domain: $DOMAIN"
log_info "🗄️ Database: $DB_NAME_CLEAN"
log_info "👤 DB User: $DB_USER"
log_info "🔑 DB Pass: $DB_PASS"
if [ -n "$GITHUB_REPO" ]; then
    log_info "📦 GitHub Repo: $GITHUB_REPO"
    log_info "🔧 Environment: Configured automatically"
fi
log_info ""
log_info "🚀 Native Laravel Octane FrankenPHP deployment configured!"
log_info "   • HTTPS service: frankenphp-$APP_NAME (port 443)"
log_info "   • HTTP redirect service: frankenphp-$APP_NAME-http (port 80)"
log_info "   • Auto SSL certificates: Enabled"
log_info "   • HTTP/2 & HTTP/3: Enabled"
log_info ""
if [ -n "$GITHUB_REPO" ]; then
    log_info "🚀 Your Laravel app is ready to start!"
    log_info "   Run: systemctl start frankenphp-$APP_NAME"
    log_info "   Run: systemctl start frankenphp-$APP_NAME-http"
    log_info "   Visit: https://$DOMAIN (auto SSL)"
    log_info "   Visit: http://$DOMAIN (redirects to HTTPS)"
else
    log_info "Next steps:"
    log_info "1. Deploy your app to $APP_DIR"
    log_info "2. Configure .env file"
    log_info "3. Run: systemctl start frankenphp-$APP_NAME"
    log_info "4. Run: systemctl start frankenphp-$APP_NAME-http"
    log_info "5. Visit: https://$DOMAIN (auto SSL)"
fi
EOF

chmod +x /usr/local/bin/create-laravel-app

# Create app deployment script
cat > /usr/local/bin/deploy-laravel-app <<'EOF'
#!/bin/bash

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <app-name>"
    echo "Example: $0 web-sam-l12"
    exit 1
fi

APP_NAME="$1"
CONFIG_FILE="/etc/laravel-apps/$APP_NAME.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: App $APP_NAME not found!"
    exit 1
fi

# Load app configuration
source $CONFIG_FILE

cd $APP_DIR

echo "🚀 Deploying $APP_NAME..."

# Check if this is a GitHub-based app
if [ -n "$GITHUB_REPO" ] && [ "$GITHUB_REPO" != "" ]; then
    echo "📦 GitHub repository detected: $GITHUB_REPO"

    # Check if git repository is initialized
    if [ -d ".git" ]; then
        echo "🔄 Pulling latest changes from GitHub..."
        git pull origin main || git pull origin master || echo "⚠️  Failed to pull, continuing with existing code"
    else
        echo "⚠️  No git repository found, skipping pull"
    fi
else
    echo "📁 Local deployment (no GitHub repository configured)"
fi

# Install dependencies if composer.json exists
if [ -f "composer.json" ]; then
    echo "📦 Installing Composer dependencies..."
    composer install --no-dev --optimize-autoloader
else
    echo "⚠️  No composer.json found, skipping composer install"
fi

# Install npm dependencies and build if package.json exists
if [ -f "package.json" ]; then
    echo "📦 Installing NPM dependencies..."
    npm ci

    # Check for build scripts
    if npm run --silent 2>&1 | grep -q "build"; then
        echo "🔨 Building frontend assets..."
        npm run build
    else
        echo "⚠️  No build script found, skipping npm build"
    fi
else
    echo "⚠️  No package.json found, skipping npm install"
fi

# Laravel optimizations if artisan exists
if [ -f "artisan" ]; then
    echo "⚡ Running Laravel optimizations..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache

    # Run migrations
    echo "🗄️  Running database migrations..."
    php artisan migrate --force

    # Clear cache
    php artisan cache:clear
    php artisan queue:restart
else
    echo "⚠️  No artisan file found, skipping Laravel optimizations"
fi

# Fix permissions
chown -R www-data:www-data $APP_DIR
chmod -R 755 $APP_DIR
chmod -R 775 $APP_DIR/storage $APP_DIR/bootstrap/cache

# Restart services
systemctl restart frankenphp-$APP_NAME
supervisorctl restart laravel-worker-$APP_NAME:*

echo "✅ Deployment completed for $APP_NAME!"
echo "🌐 Visit: https://$DOMAIN"
EOF

chmod +x /usr/local/bin/deploy-laravel-app

# Create app listing script
cat > /usr/local/bin/list-laravel-apps <<'EOF'
#!/bin/bash

echo "📋 FrankenPHP Laravel Apps:"
echo "=================================="

for config in /etc/laravel-apps/*.conf; do
    if [ -f "$config" ]; then
        source "$config"
        STATUS=$(systemctl is-active frankenphp-$APP_NAME 2>/dev/null || echo "inactive")
        echo "🔸 $APP_NAME"
        echo "   Domain: $DOMAIN"
        echo "   Status: $STATUS"
        echo "   Directory: $APP_DIR"
        echo "   URL: https://$DOMAIN"
        echo ""
    fi
done
EOF

chmod +x /usr/local/bin/list-laravel-apps

# Create app removal script
cat > /usr/local/bin/remove-laravel-app <<'EOF'
#!/bin/bash

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <app-name>"
    echo "Example: $0 web-sam-l12"
    exit 1
fi

APP_NAME="$1"
CONFIG_FILE="/etc/laravel-apps/$APP_NAME.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: App $APP_NAME not found!"
    exit 1
fi

# Load app configuration
source $CONFIG_FILE

echo "🗑️ Removing Laravel app: $APP_NAME"

# Stop services
systemctl stop frankenphp-$APP_NAME || true
systemctl disable frankenphp-$APP_NAME || true
supervisorctl stop laravel-worker-$APP_NAME:* || true

# Remove service files
rm -f /etc/systemd/system/frankenphp-$APP_NAME.service
rm -f /etc/supervisor/conf.d/laravel-worker-$APP_NAME.conf

# Remove cron jobs
crontab -u www-data -l 2>/dev/null | grep -v "$APP_DIR" | crontab -u www-data - || true

# Remove app directory (with confirmation)
read -p "Remove app directory $APP_DIR? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf $APP_DIR
    echo "Directory removed."
fi

# Remove database (with confirmation)
read -p "Remove database $DB_NAME? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    source /root/.mysql_credentials
    mysql -u root -p$MYSQL_ROOT_PASS <<MYSQL_EOF
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
MYSQL_EOF
    echo "Database removed."
fi

# Remove config
rm -f $CONFIG_FILE

# Reload services
systemctl daemon-reload
supervisorctl reread && supervisorctl update

echo "✅ App $APP_NAME removed successfully!"
EOF

chmod +x /usr/local/bin/remove-laravel-app

# Create enable/disable HTTPS scripts
cat > /usr/local/bin/enable-https-app <<'EOF'
#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Usage: $0 <app-name>"
    exit 1
fi

APP_NAME="$1"
CONFIG_FILE="/etc/laravel-apps/$APP_NAME.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: App $APP_NAME not found!"
    exit 1
fi

source $CONFIG_FILE

# Enable auto HTTPS in Caddyfile
sed -i 's/auto_https off/auto_https on/' $APP_DIR/Caddyfile

# Restart FrankenPHP
systemctl restart frankenphp-$APP_NAME

echo "✅ Auto HTTPS enabled for $APP_NAME"
echo "🌐 Visit: https://$DOMAIN"
EOF

chmod +x /usr/local/bin/enable-https-app

# Create horizontal scaling script for load balancing
cat > /usr/local/bin/scale-laravel-app <<'EOF'
#!/bin/bash

if [ $# -lt 3 ]; then
    echo "Usage: $0 <app-name> <scale-up|scale-down> <port>"
    echo "Example: $0 web-sam-l12 scale-up 8001"
    echo "Example: $0 web-sam-l12 scale-down 8002"
    exit 1
fi

APP_NAME="$1"
ACTION="$2"
PORT="$3"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Resource constants and limits
MEMORY_SAFETY_MARGIN=20  # Reserve 20% of total memory
CPU_SAFETY_MARGIN=25     # Reserve 25% of total CPU
MIN_MEMORY_PER_APP=512   # Minimum MB per app
MAX_MEMORY_PER_APP=2048  # Maximum MB per app
MIN_CPU_PER_APP=0.5      # Minimum CPU cores per app
THREAD_MEMORY_USAGE=80   # Average MB per thread
MAX_APPS_PER_SERVER=10   # Hard limit for apps per server

# Function to get current system resources
get_system_resources() {
    local total_memory_mb=$(free -m | awk 'NR==2{print $2}')
    local available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    local total_cpu_cores=$(nproc)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    # Calculate usable resources (after safety margins)
    local usable_memory_mb=$(($total_memory_mb * (100 - $MEMORY_SAFETY_MARGIN) / 100))
    local usable_cpu_cores=$(echo "$total_cpu_cores * (100 - $CPU_SAFETY_MARGIN) / 100" | bc -l)

    echo "$total_memory_mb $available_memory_mb $total_cpu_cores $cpu_usage $usable_memory_mb $usable_cpu_cores"
}

# Function to count existing apps and their resource usage
get_app_resource_usage() {
    local total_apps=0
    local total_threads=0
    local total_memory_used=0
    local total_instances=0

    # Count main apps
    for config in /etc/laravel-apps/*.conf; do
        if [ -f "$config" ]; then
            source "$config"
            total_apps=$((total_apps + 1))

            # Count threads from Caddyfile if exists
            if [ -f "$APP_DIR/Caddyfile" ]; then
                local app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
                total_threads=$((total_threads + app_threads))
                total_memory_used=$((total_memory_used + (app_threads * THREAD_MEMORY_USAGE)))
            fi

            # Count scaled instances
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

# Smart thread allocation based on total apps
calculate_smart_threads() {
    local base_threads=$1
    local existing_apps=$2
    local total_memory_mb=$3
    local available_memory_mb=$4
    local total_cpu_cores=$5

    # Base allocation
    local smart_threads=$base_threads

    # Reduce threads based on number of existing apps
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
            smart_threads=$((smart_threads * 70 / 100))  # 30% reduction for 5+ apps
        elif [ $existing_apps -ge 3 ]; then
            smart_threads=$((smart_threads * 80 / 100))  # 20% reduction for 3-4 apps
        elif [ $existing_apps -ge 1 ]; then
            smart_threads=$((smart_threads * 90 / 100))  # 10% reduction for 1-2 apps
        fi
    fi

    # Ensure minimum viable threads
    if [ $smart_threads -lt 2 ]; then
        smart_threads=2
    fi

    echo $smart_threads
}

# Function to calculate optimal FrankenPHP thread count
calculate_optimal_threads() {
    local cpu_cores=$(nproc)
    local available_memory_gb=$(free -g | awk 'NR==2{print $7}')
    local optimal_threads

    # Base calculation: Start with CPU cores
    if [ $cpu_cores -eq 1 ]; then
        # Single core: Use 2 threads to avoid blocking
        optimal_threads=2
    elif [ $cpu_cores -eq 2 ]; then
        # Dual core: Use 3 threads (1.5x cores)
        optimal_threads=3
    elif [ $cpu_cores -le 4 ]; then
        # Quad core or less: Use cores + 1
        optimal_threads=$((cpu_cores + 1))
    elif [ $cpu_cores -le 8 ]; then
        # 6-8 cores: Use cores + 2
        optimal_threads=$((cpu_cores + 2))
    else
        # High core count: Use 75% of cores + 4 (to avoid overloading)
        optimal_threads=$(((cpu_cores * 3 / 4) + 4))
    fi

    # Memory constraint check (each thread can use ~50-100MB)
    # Conservative estimate: 80MB per thread
    local max_threads_by_memory=$((available_memory_gb * 1024 / 80))

    # Use the lower of CPU-based or memory-based calculation
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

# Validate port function
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

    log_info "✅ Port $port valid dan tersedia"
    return 0
}

# Validate action
if [ "$ACTION" != "scale-up" ] && [ "$ACTION" != "scale-down" ]; then
    log_error "Action harus 'scale-up' atau 'scale-down'!"
    exit 1
fi

# Validate port
if ! validate_port "$PORT" "$( [ "$ACTION" = "scale-up" ] && echo "true" || echo "false" )"; then
    exit 1
fi

CONFIG_FILE="/etc/laravel-apps/$APP_NAME.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: App $APP_NAME not found!"
    exit 1
fi

source $CONFIG_FILE

# Function to calculate optimal FrankenPHP thread count
calculate_optimal_threads() {
    local cpu_cores=$(nproc)
    local available_memory_gb=$(free -g | awk 'NR==2{print $7}')
    local optimal_threads

    # Base calculation: Start with CPU cores
    if [ $cpu_cores -eq 1 ]; then
        # Single core: Use 2 threads to avoid blocking
        optimal_threads=2
    elif [ $cpu_cores -eq 2 ]; then
        # Dual core: Use 3 threads (1.5x cores)
        optimal_threads=3
    elif [ $cpu_cores -le 4 ]; then
        # Quad core or less: Use cores + 1
        optimal_threads=$((cpu_cores + 1))
    elif [ $cpu_cores -le 8 ]; then
        # 6-8 cores: Use cores + 2
        optimal_threads=$((cpu_cores + 2))
    else
        # High core count: Use 75% of cores + 4 (to avoid overloading)
        optimal_threads=$(((cpu_cores * 3 / 4) + 4))
    fi

    # Memory constraint check (each thread can use ~50-100MB)
    # Conservative estimate: 80MB per thread
    local max_threads_by_memory=$((available_memory_gb * 1024 / 80))

    # Use the lower of CPU-based or memory-based calculation
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

# Calculate optimal threads for this system (will be adjusted for scaling)
OPTIMAL_THREADS=$(calculate_optimal_threads)

# Get current resource usage for smart thread allocation
resources=($(get_system_resources))
usage=($(get_app_resource_usage))
existing_apps=${usage[0]}

# Calculate smart threads for new instance
SMART_THREADS=$(calculate_smart_threads $OPTIMAL_THREADS $existing_apps ${resources[0]} ${resources[1]} ${resources[2]})
OPTIMAL_THREADS=$SMART_THREADS

if [ "$ACTION" == "scale-up" ]; then
    # Scale up: Add new instance
    log_info "Scaling up $APP_NAME to port $PORT..."

    # Create new instance directory
    INSTANCE_DIR="$APP_DIR-$PORT"
    cp -r $APP_DIR $INSTANCE_DIR
    chown -R www-data:www-data $INSTANCE_DIR

    # Create service for instance
    if [ -f "$INSTANCE_DIR/artisan" ]; then
        # Laravel Octane instance
        cat > /etc/systemd/system/frankenphp-$APP_NAME-$PORT.service <<SERVICE_EOF
[Unit]
Description=Laravel Octane FrankenPHP Server for $APP_NAME Instance Port $PORT
After=network.target mysql.service redis.service
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$INSTANCE_DIR
ExecStart=/usr/bin/php artisan octane:frankenphp --host=0.0.0.0 --port=$PORT --workers=$OPTIMAL_THREADS --max-requests=1000 --log-level=info
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=10
Restart=always
RestartSec=5
SyslogIdentifier=octane-$APP_NAME-$PORT

Environment=APP_ENV=production
Environment=APP_DEBUG=false

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768

# Security settings - disabled to prevent namespace conflicts
# NoNewPrivileges, PrivateTmp, ProtectSystem, ProtectHome disabled
# to avoid systemd namespace issues (exit code 226/NAMESPACE)

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    else
        # Create Caddyfile for instance (backend only)
        cat > $INSTANCE_DIR/Caddyfile <<CADDY_EOF
{
    frankenphp {
        num_threads $OPTIMAL_THREADS
    }
    # Backend instance - no domain, just port
    auto_https off
}

# Backend instance on specific port
:$PORT {
    root * public
    encode zstd gzip

    php_server {
        resolve_root_symlink
    }

    file_server
    try_files {path} {path}/ /index.php?{query}

    header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
    }

    # Logging
    log {
        format json
        output file /var/log/frankenphp/$APP_NAME-$PORT.log
        level INFO
    }

    # Handle large uploads
    request_body {
        max_size 100MB
    }
}
CADDY_EOF

        # Standalone FrankenPHP instance
        cat > /etc/systemd/system/frankenphp-$APP_NAME-$PORT.service <<SERVICE_EOF
[Unit]
Description=FrankenPHP Web Server for $APP_NAME Instance Port $PORT
After=network.target mysql.service redis.service
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$INSTANCE_DIR
ExecStart=$INSTANCE_DIR/frankenphp run --config Caddyfile
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=10
Restart=always
RestartSec=5
SyslogIdentifier=frankenphp-$APP_NAME-$PORT

Environment=APP_ENV=production
Environment=APP_DEBUG=false

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768

# Security settings - disabled to prevent namespace conflicts
# NoNewPrivileges, PrivateTmp, ProtectSystem, ProtectHome disabled
# to avoid systemd namespace issues (exit code 226/NAMESPACE)

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    fi

    # Update main Caddyfile to include load balancer
    if ! grep -q "reverse_proxy" $APP_DIR/Caddyfile || ! grep -q "to localhost:" $APP_DIR/Caddyfile; then
        # First time scaling - convert to load balancer setup
        if [ -f "$APP_DIR/artisan" ]; then
            # Laravel Octane load balancer
            cat > $APP_DIR/Caddyfile <<CADDY_EOF
{
    # Auto HTTPS will be enabled for real domains
    auto_https off
}

# Load balancer configuration
$DOMAIN {
    encode zstd gzip

    reverse_proxy {
        # Main instance (Laravel Octane port 8000)
        to localhost:8000
        # New instance
        to localhost:$PORT

        # Load balancing method
        lb_policy round_robin

        # Health checks
        health_uri /health
        health_interval 30s
        health_timeout 5s

        # Fail timeout
        fail_timeout 30s
        max_fails 3

        # Headers
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote}
        header_up X-Forwarded-For {http.request.remote}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Forwarded-Port {http.request.port}
    }

    header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        # Add HSTS for production
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # Logging
    log {
        format json
        output file /var/log/frankenphp/$APP_NAME-lb.log
        level INFO
    }

    # Handle large uploads
    request_body {
        max_size 100MB
    }
}

# Optional: Redirect www to non-www
www.$DOMAIN {
    redir https://$DOMAIN{uri} permanent
}
CADDY_EOF
        else
            # Standalone FrankenPHP load balancer
            cat > $APP_DIR/Caddyfile <<CADDY_EOF
{
    frankenphp {
        num_threads $OPTIMAL_THREADS
    }
    # Auto HTTPS will be enabled for real domains
    auto_https off
}

# Load balancer configuration
$DOMAIN {
    encode zstd gzip

    reverse_proxy {
        # Main instance (port 80 internal)
        to localhost:80
        # New instance
        to localhost:$PORT

        # Load balancing method
        lb_policy round_robin

        # Health checks
        health_uri /health
        health_interval 30s
        health_timeout 5s

        # Fail timeout
        fail_timeout 30s
        max_fails 3

        # Headers
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote}
        header_up X-Forwarded-For {http.request.remote}
        header_up X-Forwarded-Proto {http.request.scheme}
    }

    header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        # Add HSTS for production
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # Logging
    log {
        format json
        output file /var/log/frankenphp/$APP_NAME-lb.log
        level INFO
    }
}

# Optional: Redirect www to non-www
www.$DOMAIN {
    redir https://$DOMAIN{uri} permanent
}

# Main instance backend
:80 {
    root * public
    encode zstd gzip

    php_server {
        resolve_root_symlink
    }

    file_server
    try_files {path} {path}/ /index.php?{query}

    # Health check endpoint
    respond /health 200 {
        body "OK"
    }

    # Handle large uploads
    request_body {
        max_size 100MB
    }
}
CADDY_EOF
        fi
    else
        # Add new instance to existing load balancer
        sed -i "/# New instance/a\\        to localhost:$PORT" $APP_DIR/Caddyfile
    fi

    # Start the new instance
    systemctl daemon-reload
    systemctl enable frankenphp-$APP_NAME-$PORT
    systemctl start frankenphp-$APP_NAME-$PORT

    # Restart main load balancer
    systemctl restart frankenphp-$APP_NAME

    log_info "✅ Scaled up $APP_NAME to port $PORT"
    log_info "🌐 Instance running at: http://localhost:$PORT"
    log_info "🔧 Load balancer updated at: https://$DOMAIN"

elif [ "$ACTION" == "scale-down" ]; then
    # Scale down: Remove instance
    log_info "Scaling down $APP_NAME from port $PORT..."

    # Stop and disable instance
    systemctl stop frankenphp-$APP_NAME-$PORT || true
    systemctl disable frankenphp-$APP_NAME-$PORT || true

    # Remove service file
    rm -f /etc/systemd/system/frankenphp-$APP_NAME-$PORT.service

    # Remove instance directory
    INSTANCE_DIR="$APP_DIR-$PORT"
    rm -rf $INSTANCE_DIR

    # Update main Caddyfile to remove instance
    sed -i "/to localhost:$PORT/d" $APP_DIR/Caddyfile

    # If no more instances, convert back to direct serve
    if [ $(grep -c "to localhost:" $APP_DIR/Caddyfile) -eq 1 ]; then
        # Only main instance left, convert back to direct serve
        if [ -f "$APP_DIR/artisan" ]; then
            # Laravel Octane direct serve
            cat > $APP_DIR/Caddyfile <<CADDY_EOF
{
    # Auto HTTPS will be enabled for real domains
    auto_https off
}

# Main domain configuration
$DOMAIN {
    encode zstd gzip

    # Reverse proxy to Laravel Octane
    reverse_proxy localhost:8000 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote}
        header_up X-Forwarded-For {http.request.remote}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Forwarded-Port {http.request.port}

        # Health check
        health_uri /health
        health_interval 30s
        health_timeout 5s

        # Fail timeout
        fail_timeout 30s
        max_fails 3
    }

    header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        # Add HSTS for production
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # Logging
    log {
        format json
        output file /var/log/frankenphp/$APP_NAME.log
        level INFO
    }

    # Handle large uploads
    request_body {
        max_size 100MB
    }
}

# Optional: Redirect www to non-www
www.$DOMAIN {
    redir https://$DOMAIN{uri} permanent
}
CADDY_EOF
        else
            # Standalone FrankenPHP direct serve
            cat > $APP_DIR/Caddyfile <<CADDY_EOF
{
    frankenphp {
        num_threads $OPTIMAL_THREADS
    }
    # Auto HTTPS will be enabled for real domains
    auto_https off
}

# Main domain configuration
$DOMAIN {
    root * public
    encode zstd gzip

    php_server {
        resolve_root_symlink
    }

    file_server
    try_files {path} {path}/ /index.php?{query}

    header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        # Add HSTS for production
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # Logging
    log {
        format json
        output file /var/log/frankenphp/$APP_NAME.log
        level INFO
    }

    # Handle large uploads
    request_body {
        max_size 100MB
    }
}

# Optional: Redirect www to non-www
www.$DOMAIN {
    redir https://$DOMAIN{uri} permanent
}
CADDY_EOF
        fi
    fi

    # Restart main service
    systemctl daemon-reload
    systemctl restart frankenphp-$APP_NAME

    log_info "✅ Scaled down $APP_NAME from port $PORT"
    log_info "🔧 Load balancer updated at: https://$DOMAIN"

else
    log_error "Invalid action: $ACTION"
    log_error "Use: scale-up or scale-down"
    exit 1
fi
EOF

chmod +x /usr/local/bin/scale-laravel-app

# Create app status monitoring script
cat > /usr/local/bin/status-laravel-app <<'EOF'
#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Usage: $0 <app-name>"
    echo "Example: $0 web-sam-l12"
    exit 1
fi

APP_NAME="$1"
CONFIG_FILE="/etc/laravel-apps/$APP_NAME.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: App $APP_NAME not found!"
    exit 1
fi

source $CONFIG_FILE

echo "📊 Status for $APP_NAME"
echo "========================"
echo "🌐 Domain: $DOMAIN"
echo "📁 Directory: $APP_DIR"
echo ""

# Main service status
MAIN_STATUS=$(systemctl is-active frankenphp-$APP_NAME 2>/dev/null || echo "inactive")
echo "🔸 Main Instance: $MAIN_STATUS"

# Check for scaled instances
echo "🔸 Scaled Instances:"
for service in /etc/systemd/system/frankenphp-$APP_NAME-*.service; do
    if [ -f "$service" ]; then
        PORT=$(basename "$service" .service | cut -d'-' -f3)
        STATUS=$(systemctl is-active frankenphp-$APP_NAME-$PORT 2>/dev/null || echo "inactive")
        echo "   Port $PORT: $STATUS"
    fi
done

# Check if load balancer is active
if grep -q "reverse_proxy" $APP_DIR/Caddyfile; then
    echo "⚖️  Load Balancer: Active"
    echo "🔄 Load Balancing Method: Round Robin"
else
    echo "⚖️  Load Balancer: Direct Serve"
fi

# Worker status
echo ""
echo "👷 Queue Workers:"
supervisorctl status laravel-worker-$APP_NAME:* 2>/dev/null || echo "   No workers found"

# Recent logs
echo ""
echo "📋 Recent Logs (last 5 lines):"
tail -5 /var/log/frankenphp/$APP_NAME*.log 2>/dev/null || echo "   No logs found"
EOF

chmod +x /usr/local/bin/status-laravel-app

# Create resource monitoring script
cat > /usr/local/bin/monitor-server-resources <<'EOF'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Resource constants and limits
MEMORY_SAFETY_MARGIN=20  # Reserve 20% of total memory
CPU_SAFETY_MARGIN=25     # Reserve 25% of total CPU
MIN_MEMORY_PER_APP=512   # Minimum MB per app
MAX_MEMORY_PER_APP=2048  # Maximum MB per app
MIN_CPU_PER_APP=0.5      # Minimum CPU cores per app
THREAD_MEMORY_USAGE=80   # Average MB per thread
MAX_APPS_PER_SERVER=10   # Hard limit for apps per server

# Function to get current system resources
get_system_resources() {
    local total_memory_mb=$(free -m | awk 'NR==2{print $2}')
    local available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    local total_cpu_cores=$(nproc)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    # Calculate usable resources (after safety margins)
    local usable_memory_mb=$(($total_memory_mb * (100 - $MEMORY_SAFETY_MARGIN) / 100))
    local usable_cpu_cores=$(echo "$total_cpu_cores * (100 - $CPU_SAFETY_MARGIN) / 100" | bc -l)

    echo "$total_memory_mb $available_memory_mb $total_cpu_cores $cpu_usage $usable_memory_mb $usable_cpu_cores"
}

# Function to count existing apps and their resource usage
get_app_resource_usage() {
    local total_apps=0
    local total_threads=0
    local total_memory_used=0
    local total_instances=0

    # Count main apps
    for config in /etc/laravel-apps/*.conf; do
        if [ -f "$config" ]; then
            source "$config"
            total_apps=$((total_apps + 1))

            # Count threads from Caddyfile if exists
            if [ -f "$APP_DIR/Caddyfile" ]; then
                local app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
                total_threads=$((total_threads + app_threads))
                total_memory_used=$((total_memory_used + (app_threads * THREAD_MEMORY_USAGE)))
            fi

            # Count scaled instances
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

# Get system resources
resources=($(get_system_resources))
total_memory_mb=${resources[0]}
available_memory_mb=${resources[1]}
total_cpu_cores=${resources[2]}
cpu_usage=${resources[3]}
usable_memory_mb=${resources[4]}
usable_cpu_cores=${resources[5]}

# Get app resource usage
usage=($(get_app_resource_usage))
existing_apps=${usage[0]}
total_threads=${usage[1]}
total_memory_used=${usage[2]}
total_instances=${usage[3]}

# Calculate percentages
memory_usage_percent=$(($total_memory_used * 100 / $total_memory_mb))
cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)
available_memory_percent=$(($available_memory_mb * 100 / $total_memory_mb))

echo ""
log_header "🖥️  SERVER RESOURCE MONITOR"
log_header "=========================="
echo ""

# System Overview
log_header "📊 SYSTEM OVERVIEW"
echo "🔧 Total CPU Cores: $total_cpu_cores"
echo "💾 Total Memory: ${total_memory_mb}MB"
echo "⚡ Current CPU Usage: ${cpu_usage}%"
echo "🆓 Available Memory: ${available_memory_mb}MB (${available_memory_percent}%)"
echo ""

# Resource Usage
log_header "📈 RESOURCE USAGE"
echo "🏗️  Total Apps: $existing_apps"
echo "📱 Total Instances: $total_instances"
echo "🧵 Total Threads: $total_threads"
echo "💾 Estimated Memory Used: ${total_memory_used}MB (${memory_usage_percent}%)"
echo ""

# Capacity Analysis
log_header "🎯 CAPACITY ANALYSIS"
remaining_apps=$((MAX_APPS_PER_SERVER - existing_apps))
echo "📱 Remaining App Slots: $remaining_apps / $MAX_APPS_PER_SERVER"

# Calculate potential new apps based on memory
potential_memory_apps=$(($available_memory_mb / MIN_MEMORY_PER_APP))
echo "💾 Potential Apps (Memory): $potential_memory_apps"

# Calculate potential new apps based on threads
max_threads_remaining=$(($total_cpu_cores * 2 - $total_threads))
potential_thread_apps=$(($max_threads_remaining / 2))
echo "🧵 Potential Apps (Threads): $potential_thread_apps"

# Show the limiting factor
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

echo "🎯 Limiting Factor: $limiting_factor"
echo "⚡ Estimated New Apps Possible: $potential_apps"
echo ""

# Status indicators
log_header "🚦 STATUS INDICATORS"
if [ $memory_usage_percent -lt 50 ]; then
    echo -e "💾 Memory Usage: ${GREEN}LOW${NC} (${memory_usage_percent}%)"
elif [ $memory_usage_percent -lt 70 ]; then
    echo -e "💾 Memory Usage: ${YELLOW}MODERATE${NC} (${memory_usage_percent}%)"
else
    echo -e "💾 Memory Usage: ${RED}HIGH${NC} (${memory_usage_percent}%)"
fi

if [ $cpu_usage_int -lt 50 ]; then
    echo -e "🔥 CPU Usage: ${GREEN}LOW${NC} (${cpu_usage}%)"
elif [ $cpu_usage_int -lt 70 ]; then
    echo -e "🔥 CPU Usage: ${YELLOW}MODERATE${NC} (${cpu_usage}%)"
else
    echo -e "🔥 CPU Usage: ${RED}HIGH${NC} (${cpu_usage}%)"
fi

if [ $existing_apps -lt 3 ]; then
    echo -e "📱 App Count: ${GREEN}LOW${NC} ($existing_apps apps)"
elif [ $existing_apps -lt 7 ]; then
    echo -e "📱 App Count: ${YELLOW}MODERATE${NC} ($existing_apps apps)"
else
    echo -e "📱 App Count: ${RED}HIGH${NC} ($existing_apps apps)"
fi

echo ""

# Warnings
if [ $memory_usage_percent -gt 80 ] || [ $cpu_usage_int -gt 80 ] || [ $existing_apps -gt 7 ]; then
    log_header "⚠️  WARNINGS"
    if [ $memory_usage_percent -gt 80 ]; then
        log_warning "High memory usage detected"
    fi
    if [ $cpu_usage_int -gt 80 ]; then
        log_warning "High CPU usage detected"
    fi
    if [ $existing_apps -gt 7 ]; then
        log_warning "High app count detected"
    fi
    echo "💡 Consider scaling horizontally or optimizing resources"
    echo ""
fi

# Recommendations
log_header "💡 RECOMMENDATIONS"
if [ $potential_apps -gt 3 ]; then
    echo "✅ Server has good capacity for new apps"
elif [ $potential_apps -gt 1 ]; then
    echo "⚠️  Server has limited capacity - plan carefully"
else
    echo "🚨 Server is at capacity - scale horizontally"
fi

if [ $memory_usage_percent -gt 70 ]; then
    echo "💾 Consider optimizing memory usage or adding more RAM"
fi

if [ $cpu_usage_int -gt 70 ]; then
    echo "🔥 Consider optimizing CPU usage or adding more CPU cores"
fi

if [ $existing_apps -gt 5 ]; then
    echo "📱 Consider consolidating similar apps or deploying to additional servers"
fi

echo ""
EOF

chmod +x /usr/local/bin/monitor-server-resources

# Create detailed app resource usage script
cat > /usr/local/bin/analyze-app-resources <<'EOF'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_header() {
    echo -e "${BLUE}$1${NC}"
}

# Resource constants and limits
MEMORY_SAFETY_MARGIN=20  # Reserve 20% of total memory
CPU_SAFETY_MARGIN=25     # Reserve 25% of total CPU
MIN_MEMORY_PER_APP=512   # Minimum MB per app
MAX_MEMORY_PER_APP=2048  # Maximum MB per app
MIN_CPU_PER_APP=0.5      # Minimum CPU cores per app
THREAD_MEMORY_USAGE=80   # Average MB per thread
MAX_APPS_PER_SERVER=10   # Hard limit for apps per server

echo ""
log_header "📱 DETAILED APP RESOURCE ANALYSIS"
log_header "=================================="
echo ""

total_threads=0
total_memory_used=0
total_instances=0

# Analyze each app
for config in /etc/laravel-apps/*.conf; do
    if [ -f "$config" ]; then
        source "$config"

        # Get app threads
        app_threads=2
        if [ -f "$APP_DIR/Caddyfile" ]; then
            app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
        fi

        # Count instances
        instances=1
        instance_list=""
        for service in /etc/systemd/system/frankenphp-$APP_NAME-*.service; do
            if [ -f "$service" ]; then
                port=$(basename "$service" .service | cut -d'-' -f3)
                instances=$((instances + 1))
                instance_list="$instance_list $port"
            fi
        done

        # Calculate memory usage
        app_memory=$(($app_threads * 80 * $instances))

        # Service status
        status=$(systemctl is-active frankenphp-$APP_NAME 2>/dev/null || echo "inactive")

        # Display app info
        echo "🔸 App: $APP_NAME"
        echo "   🌐 Domain: $DOMAIN"
        echo "   🧵 Threads: $app_threads per instance"
        echo "   📱 Instances: $instances"
        if [ -n "$instance_list" ]; then
            echo "   🔗 Scaled ports:$instance_list"
        fi
        echo "   💾 Memory Usage: ~${app_memory}MB"
        echo "   🔄 Status: $status"
        echo "   📁 Directory: $APP_DIR"
        echo ""

        total_threads=$(($total_threads + ($app_threads * $instances)))
        total_memory_used=$(($total_memory_used + $app_memory))
        total_instances=$(($total_instances + $instances))
    fi
done

# Summary
log_header "📊 SUMMARY"
echo "🏗️  Total Apps: $(ls /etc/laravel-apps/*.conf 2>/dev/null | wc -l)"
echo "📱 Total Instances: $total_instances"
echo "🧵 Total Threads: $total_threads"
echo "💾 Total Memory Used: ${total_memory_used}MB"
echo ""

# System comparison
system_memory=$(free -m | awk 'NR==2{print $2}')
system_cpu=$(nproc)
memory_percent=$(($total_memory_used * 100 / $system_memory))

echo "📈 System Usage:"
echo "   💾 Memory: ${memory_percent}% of ${system_memory}MB"
echo "   🧵 Thread Efficiency: $total_threads threads on $system_cpu CPU cores"
echo ""
EOF

chmod +x /usr/local/bin/analyze-app-resources

# Create resource prediction script
cat > /usr/local/bin/predict-resource-impact <<'EOF'
#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Usage: $0 <action> [app-name] [params...]"
    echo "Actions:"
    echo "  new-app <app-name> [threads]     - Predict impact of new app"
    echo "  scale-up <app-name> [threads]    - Predict impact of scaling up"
    echo "  scale-down <app-name>            - Predict impact of scaling down"
    echo "  remove-app <app-name>            - Predict impact of removing app"
    echo ""
    echo "Examples:"
    echo "  predict-resource-impact new-app web_new_app 4"
    echo "  predict-resource-impact scale-up web_sam_l12 6"
    echo "  predict-resource-impact remove-app web_old_app"
    exit 1
fi

ACTION="$1"
APP_NAME="$2"
THREADS="${3:-4}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_header() {
    echo -e "${BLUE}$1${NC}"
}

# Resource constants and limits
MEMORY_SAFETY_MARGIN=20  # Reserve 20% of total memory
CPU_SAFETY_MARGIN=25     # Reserve 25% of total CPU
MIN_MEMORY_PER_APP=512   # Minimum MB per app
MAX_MEMORY_PER_APP=2048  # Maximum MB per app
MIN_CPU_PER_APP=0.5      # Minimum CPU cores per app
THREAD_MEMORY_USAGE=80   # Average MB per thread
MAX_APPS_PER_SERVER=10   # Hard limit for apps per server

# Function to get current system resources
get_system_resources() {
    local total_memory_mb=$(free -m | awk 'NR==2{print $2}')
    local available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    local total_cpu_cores=$(nproc)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    # Calculate usable resources (after safety margins)
    local usable_memory_mb=$(($total_memory_mb * (100 - $MEMORY_SAFETY_MARGIN) / 100))
    local usable_cpu_cores=$(echo "$total_cpu_cores * (100 - $CPU_SAFETY_MARGIN) / 100" | bc -l)

    echo "$total_memory_mb $available_memory_mb $total_cpu_cores $cpu_usage $usable_memory_mb $usable_cpu_cores"
}

# Function to count existing apps and their resource usage
get_app_resource_usage() {
    local total_apps=0
    local total_threads=0
    local total_memory_used=0
    local total_instances=0

    # Count main apps
    for config in /etc/laravel-apps/*.conf; do
        if [ -f "$config" ]; then
            source "$config"
            total_apps=$((total_apps + 1))

            # Count threads from Caddyfile if exists
            if [ -f "$APP_DIR/Caddyfile" ]; then
                local app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
                total_threads=$((total_threads + app_threads))
                total_memory_used=$((total_memory_used + (app_threads * THREAD_MEMORY_USAGE)))
            fi

            # Count scaled instances
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

# Smart thread allocation based on total apps
calculate_smart_threads() {
    local base_threads=$1
    local existing_apps=$2
    local total_memory_mb=$3
    local available_memory_mb=$4
    local total_cpu_cores=$5

    # Base allocation
    local smart_threads=$base_threads

    # Reduce threads based on number of existing apps
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
            smart_threads=$((smart_threads * 70 / 100))  # 30% reduction for 5+ apps
        elif [ $existing_apps -ge 3 ]; then
            smart_threads=$((smart_threads * 80 / 100))  # 20% reduction for 3-4 apps
        elif [ $existing_apps -ge 1 ]; then
            smart_threads=$((smart_threads * 90 / 100))  # 10% reduction for 1-2 apps
        fi
    fi

    # Ensure minimum viable threads
    if [ $smart_threads -lt 2 ]; then
        smart_threads=2
    fi

    echo $smart_threads
}

# Get current resources
resources=($(get_system_resources))
usage=($(get_app_resource_usage))

total_memory_mb=${resources[0]}
available_memory_mb=${resources[1]}
total_cpu_cores=${resources[2]}
cpu_usage=${resources[3]}

existing_apps=${usage[0]}
total_threads=${usage[1]}
total_memory_used=${usage[2]}
total_instances=${usage[3]}

current_memory_percent=$(($total_memory_used * 100 / $total_memory_mb))

echo ""
log_header "🔮 RESOURCE IMPACT PREDICTION"
log_header "=============================="
echo ""

echo "📊 Current State:"
echo "   🏗️  Apps: $existing_apps"
echo "   🧵 Threads: $total_threads"
echo "   💾 Memory: ${total_memory_used}MB (${current_memory_percent}%)"
echo ""

case $ACTION in
    "new-app")
        # Calculate smart threads for new app
        smart_threads=$(calculate_smart_threads $THREADS $existing_apps $total_memory_mb $available_memory_mb $total_cpu_cores)

        new_memory_used=$(($total_memory_used + ($smart_threads * 80)))
        new_memory_percent=$(($new_memory_used * 100 / $total_memory_mb))
        new_threads=$(($total_threads + $smart_threads))
        new_apps=$(($existing_apps + 1))

        echo "🔮 Predicted Impact (New App: $APP_NAME):"
        echo "   🏗️  Apps: $existing_apps → $new_apps"
        echo "   🧵 Threads: $total_threads → $new_threads (+$smart_threads)"
        echo "   💾 Memory: ${total_memory_used}MB → ${new_memory_used}MB (+$(($smart_threads * 80))MB)"
        echo "   📈 Memory Usage: ${current_memory_percent}% → ${new_memory_percent}%"
        echo ""

        # Warnings
        if [ $new_memory_percent -gt 80 ]; then
            echo -e "${RED}⚠️  WARNING: High memory usage projected${NC}"
        elif [ $new_memory_percent -gt 70 ]; then
            echo -e "${YELLOW}⚠️  WARNING: Moderate memory usage projected${NC}"
        else
            echo -e "${GREEN}✅ Memory usage looks good${NC}"
        fi

        if [ $new_apps -gt 8 ]; then
            echo -e "${RED}⚠️  WARNING: High app count${NC}"
        fi
        ;;

    "scale-up")
        # Find current app config
        config_file="/etc/laravel-apps/$APP_NAME.conf"
        if [ ! -f "$config_file" ]; then
            echo -e "${RED}Error: App $APP_NAME not found${NC}"
            exit 1
        fi

        source "$config_file"
        current_app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")

        new_memory_used=$(($total_memory_used + ($THREADS * 80)))
        new_memory_percent=$(($new_memory_used * 100 / $total_memory_mb))
        new_threads=$(($total_threads + $THREADS))
        new_instances=$(($total_instances + 1))

        echo "🔮 Predicted Impact (Scale Up: $APP_NAME):"
        echo "   📱 Instances: $total_instances → $new_instances (+1)"
        echo "   🧵 Threads: $total_threads → $new_threads (+$THREADS)"
        echo "   💾 Memory: ${total_memory_used}MB → ${new_memory_used}MB (+$(($THREADS * 80))MB)"
        echo "   📈 Memory Usage: ${current_memory_percent}% → ${new_memory_percent}%"
        echo ""

        # Warnings
        if [ $new_memory_percent -gt 80 ]; then
            echo -e "${RED}⚠️  WARNING: High memory usage projected${NC}"
        elif [ $new_memory_percent -gt 70 ]; then
            echo -e "${YELLOW}⚠️  WARNING: Moderate memory usage projected${NC}"
        else
            echo -e "${GREEN}✅ Memory usage looks good${NC}"
        fi
        ;;

    "scale-down")
        # Find current app config
        config_file="/etc/laravel-apps/$APP_NAME.conf"
        if [ ! -f "$config_file" ]; then
            echo -e "${RED}Error: App $APP_NAME not found${NC}"
            exit 1
        fi

        source "$config_file"
        current_app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")

        # Count current instances
        instance_count=0
        for service in /etc/systemd/system/frankenphp-$APP_NAME-*.service; do
            if [ -f "$service" ]; then
                instance_count=$((instance_count + 1))
            fi
        done

        if [ $instance_count -eq 0 ]; then
            echo -e "${YELLOW}⚠️  No scaled instances found for $APP_NAME${NC}"
            exit 1
        fi

        new_memory_used=$(($total_memory_used - ($current_app_threads * 80)))
        new_memory_percent=$(($new_memory_used * 100 / $total_memory_mb))
        new_threads=$(($total_threads - $current_app_threads))
        new_instances=$(($total_instances - 1))

        echo "🔮 Predicted Impact (Scale Down: $APP_NAME):"
        echo "   📱 Instances: $total_instances → $new_instances (-1)"
        echo "   🧵 Threads: $total_threads → $new_threads (-$current_app_threads)"
        echo "   💾 Memory: ${total_memory_used}MB → ${new_memory_used}MB (-$(($current_app_threads * 80))MB)"
        echo "   📈 Memory Usage: ${current_memory_percent}% → ${new_memory_percent}%"
        echo ""

        echo -e "${GREEN}✅ Resources will be freed up${NC}"
        ;;

    "remove-app")
        # Find current app config
        config_file="/etc/laravel-apps/$APP_NAME.conf"

        if [ ! -f "$config_file" ]; then
            echo -e "${RED}Error: App $APP_NAME not found${NC}"
            exit 1
        fi

        source "$config_file"
        current_app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")

        # Count total instances for this app
        app_instances=1
        for service in /etc/systemd/system/frankenphp-$APP_NAME-*.service; do
            if [ -f "$service" ]; then
                app_instances=$((app_instances + 1))
            fi
        done

        total_app_threads=$(($current_app_threads * $app_instances))
        total_app_memory=$(($total_app_threads * 80))

        new_memory_used=$(($total_memory_used - $total_app_memory))
        new_memory_percent=$(($new_memory_used * 100 / $total_memory_mb))
        new_threads=$(($total_threads - $total_app_threads))
        new_instances=$(($total_instances - $app_instances))
        new_apps=$(($existing_apps - 1))

        echo "🔮 Predicted Impact (Remove App: $APP_NAME):"
        echo "   🏗️  Apps: $existing_apps → $new_apps (-1)"
        echo "   📱 Instances: $total_instances → $new_instances (-$app_instances)"
        echo "   🧵 Threads: $total_threads → $new_threads (-$total_app_threads)"
        echo "   💾 Memory: ${total_memory_used}MB → ${new_memory_used}MB (-${total_app_memory}MB)"
        echo "   📈 Memory Usage: ${current_memory_percent}% → ${new_memory_percent}%"
        echo ""

        echo -e "${GREEN}✅ Significant resources will be freed up${NC}"
        ;;

    *)
        echo -e "${RED}Error: Unknown action $ACTION${NC}"
        exit 1
        ;;
esac

echo ""
EOF

chmod +x /usr/local/bin/predict-resource-impact

# Create resource optimization script
cat > /usr/local/bin/optimize-server-resources <<'EOF'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Resource constants and limits
MEMORY_SAFETY_MARGIN=20  # Reserve 20% of total memory
CPU_SAFETY_MARGIN=25     # Reserve 25% of total CPU
MIN_MEMORY_PER_APP=512   # Minimum MB per app
MAX_MEMORY_PER_APP=2048  # Maximum MB per app
MIN_CPU_PER_APP=0.5      # Minimum CPU cores per app
THREAD_MEMORY_USAGE=80   # Average MB per thread
MAX_APPS_PER_SERVER=10   # Hard limit for apps per server

# Function to get current system resources
get_system_resources() {
    local total_memory_mb=$(free -m | awk 'NR==2{print $2}')
    local available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    local total_cpu_cores=$(nproc)
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    # Calculate usable resources (after safety margins)
    local usable_memory_mb=$(($total_memory_mb * (100 - $MEMORY_SAFETY_MARGIN) / 100))
    local usable_cpu_cores=$(echo "$total_cpu_cores * (100 - $CPU_SAFETY_MARGIN) / 100" | bc -l)

    echo "$total_memory_mb $available_memory_mb $total_cpu_cores $cpu_usage $usable_memory_mb $usable_cpu_cores"
}

# Function to count existing apps and their resource usage
get_app_resource_usage() {
    local total_apps=0
    local total_threads=0
    local total_memory_used=0
    local total_instances=0

    # Count main apps
    for config in /etc/laravel-apps/*.conf; do
        if [ -f "$config" ]; then
            source "$config"
            total_apps=$((total_apps + 1))

            # Count threads from Caddyfile if exists
            if [ -f "$APP_DIR/Caddyfile" ]; then
                local app_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
                total_threads=$((total_threads + app_threads))
                total_memory_used=$((total_memory_used + (app_threads * THREAD_MEMORY_USAGE)))
            fi

            # Count scaled instances
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

# Smart thread allocation based on total apps
calculate_smart_threads() {
    local base_threads=$1
    local existing_apps=$2
    local total_memory_mb=$3
    local available_memory_mb=$4
    local total_cpu_cores=$5

    # Base allocation
    local smart_threads=$base_threads

    # Reduce threads based on number of existing apps
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
            smart_threads=$((smart_threads * 70 / 100))  # 30% reduction for 5+ apps
        elif [ $existing_apps -ge 3 ]; then
            smart_threads=$((smart_threads * 80 / 100))  # 20% reduction for 3-4 apps
        elif [ $existing_apps -ge 1 ]; then
            smart_threads=$((smart_threads * 90 / 100))  # 10% reduction for 1-2 apps
        fi
    fi

    # Ensure minimum viable threads
    if [ $smart_threads -lt 2 ]; then
        smart_threads=2
    fi

    echo $smart_threads
}

# Function to calculate optimal FrankenPHP thread count
calculate_optimal_threads() {
    local cpu_cores=$(nproc)
    local available_memory_gb=$(free -g | awk 'NR==2{print $7}')
    local optimal_threads

    # Base calculation: Start with CPU cores
    if [ $cpu_cores -eq 1 ]; then
        # Single core: Use 2 threads to avoid blocking
        optimal_threads=2
    elif [ $cpu_cores -eq 2 ]; then
        # Dual core: Use 3 threads (1.5x cores)
        optimal_threads=3
    elif [ $cpu_cores -le 4 ]; then
        # Quad core or less: Use cores + 1
        optimal_threads=$((cpu_cores + 1))
    elif [ $cpu_cores -le 8 ]; then
        # 6-8 cores: Use cores + 2
        optimal_threads=$((cpu_cores + 2))
    else
        # High core count: Use 75% of cores + 4 (to avoid overloading)
        optimal_threads=$(((cpu_cores * 3 / 4) + 4))
    fi

    # Memory constraint check (each thread can use ~50-100MB)
    # Conservative estimate: 80MB per thread
    local max_threads_by_memory=$((available_memory_gb * 1024 / 80))

    # Use the lower of CPU-based or memory-based calculation
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

echo ""
log_header "🔧 SERVER RESOURCE OPTIMIZATION"
log_header "==============================="
echo ""

# Get current resources
resources=($(get_system_resources))
usage=($(get_app_resource_usage))

total_memory_mb=${resources[0]}
available_memory_mb=${resources[1]}
total_cpu_cores=${resources[2]}
cpu_usage=${resources[3]}

existing_apps=${usage[0]}
total_threads=${usage[1]}
total_memory_used=${usage[2]}

memory_usage_percent=$(($total_memory_used * 100 / $total_memory_mb))

log_info "Current resource usage: ${memory_usage_percent}% memory, ${cpu_usage}% CPU"

if [ $memory_usage_percent -lt 70 ] && [ $(echo "$cpu_usage < 70" | bc -l) -eq 1 ]; then
    log_info "✅ System is well optimized - no action needed"
    exit 0
fi

echo ""
log_header "🔍 OPTIMIZATION RECOMMENDATIONS"
echo ""

# Check for over-allocated threads
log_info "Analyzing thread allocation..."
for config in /etc/laravel-apps/*.conf; do
    if [ -f "$config" ]; then
        source "$config"

        if [ -f "$APP_DIR/Caddyfile" ]; then
            current_threads=$(grep -oP 'num_threads \K\d+' "$APP_DIR/Caddyfile" 2>/dev/null || echo "2")
            optimal_threads=$(calculate_smart_threads $current_threads $existing_apps $total_memory_mb $available_memory_mb $total_cpu_cores)

            if [ $current_threads -gt $optimal_threads ]; then
                log_warning "App $APP_NAME: Using $current_threads threads, optimal is $optimal_threads"
                echo "   💡 Run: sed -i 's/num_threads $current_threads/num_threads $optimal_threads/' $APP_DIR/Caddyfile"
                echo "   💡 Then: systemctl restart frankenphp-$APP_NAME"
            fi
        fi
    fi
done

echo ""

# Check for inactive apps
log_info "Checking for inactive apps..."
for config in /etc/laravel-apps/*.conf; do
    if [ -f "$config" ]; then
        source "$config"
        status=$(systemctl is-active frankenphp-$APP_NAME 2>/dev/null || echo "inactive")

        if [ "$status" = "inactive" ] || [ "$status" = "failed" ]; then
            log_warning "App $APP_NAME is $status"
            echo "   💡 Consider removing: remove-laravel-app $APP_NAME"
        fi
    fi
done

echo ""

# Check for memory optimization
if [ $memory_usage_percent -gt 80 ]; then
    log_warning "High memory usage detected"
    echo "   💡 Consider:"
    echo "      - Reducing thread counts"
    echo "      - Removing unused apps"
    echo "      - Adding more RAM"
    echo "      - Scaling horizontally"
fi

# Check for CPU optimization
cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)
if [ $cpu_usage_int -gt 80 ]; then
    log_warning "High CPU usage detected"
    echo "   💡 Consider:"
    echo "      - Optimizing application code"
    echo "      - Using Redis/caching more effectively"
    echo "      - Scaling horizontally"
    echo "      - Adding more CPU cores"
fi

# Check for app consolidation opportunities
if [ $existing_apps -gt 6 ]; then
    log_warning "High app count detected"
    echo "   💡 Consider consolidating similar apps or using subdomains"
fi

echo ""
log_header "📊 QUICK STATS"
echo "🏗️  Total Apps: $existing_apps"
echo "🧵 Total Threads: $total_threads"
echo "💾 Memory Usage: ${memory_usage_percent}%"
echo "🔥 CPU Usage: ${cpu_usage}%"
echo ""

EOF

chmod +x /usr/local/bin/optimize-server-resources

# =============================================
# 10. Create backup script for all apps
# =============================================
log_info "Creating backup script for all apps..."
cat > /usr/local/bin/backup-all-laravel-apps <<'EOF'
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
EOF

chmod +x /usr/local/bin/backup-all-laravel-apps

# Setup daily backup cron (idempotent)
if ! crontab -l 2>/dev/null | grep -q "backup-all-laravel-apps"; then
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-all-laravel-apps") | crontab -
    log_info "✅ Daily backup cron job added"
else
    log_info "✅ Daily backup cron job already exists"
fi

# =============================================
# 11. Final setup
# =============================================
log_info "Setting up logrotate..."
cat > /etc/logrotate.d/laravel-apps <<EOF
/opt/laravel-apps/*/storage/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 www-data www-data
}

/var/log/frankenphp/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 www-data www-data
}
EOF

# Optimize PHP for FrankenPHP
log_info "Optimizing PHP configuration for FrankenPHP..."

# Create optimized php.ini for FrankenPHP embedded PHP
cat > /etc/php/8.3/cli/conf.d/99-frankenphp-optimizations.ini <<PHP_INI
; FrankenPHP Optimizations
; OPcache settings for embedded PHP
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
opcache.save_comments=1
opcache.fast_shutdown=1

; Memory settings
memory_limit=512M
max_execution_time=300
max_input_time=300

; File upload settings
upload_max_filesize=100M
post_max_size=100M

; Session settings
session.gc_maxlifetime=7200
session.cookie_lifetime=7200

; Error reporting for production
display_errors=Off
log_errors=On
error_reporting=E_ALL & ~E_DEPRECATED & ~E_STRICT

; Realpath cache (important for performance)
realpath_cache_size=4096k
realpath_cache_ttl=600
PHP_INI

log_info "✅ PHP optimized for FrankenPHP embedded server"

# Start services
systemctl start supervisor
systemctl enable supervisor

log_info "✅ FrankenPHP Multi-App setup completed!"
log_info ""
log_info "📚 Available commands:"
log_info "  create-laravel-app <name> <domain> [github-repo] [db-name]"
log_info "  deploy-laravel-app <name>"
log_info "  list-laravel-apps"
log_info "  remove-laravel-app <name>"
log_info "  enable-https-app <name>"
log_info "  scale-laravel-app <name> <scale-up|scale-down> <port>"
log_info "  status-laravel-app <name>"
log_info "  backup-all-laravel-apps"
log_info ""
log_info "🔥 Laravel Octane Helper (install.sh):"
log_info "  install.sh octane:install [directory]    - Install Laravel Octane with FrankenPHP"
log_info "  install.sh octane:start [directory]      - Start Laravel Octane server"
log_info "  install.sh octane:stop [directory]       - Stop Laravel Octane server"
log_info "  install.sh octane:restart [directory]    - Restart Laravel Octane server"
log_info "  install.sh octane:status [directory]     - Check Octane server status"
log_info "  install.sh octane:optimize [directory]   - Optimize Laravel app for Octane"
log_info "  install.sh debug [directory]             - Debug Octane installation issues"
log_info ""
log_info "🔍 Resource Monitoring & Optimization:"
log_info "  monitor-server-resources             - Real-time server resource monitoring"
log_info "  analyze-app-resources                - Detailed app resource analysis"
log_info "  predict-resource-impact <action>     - Predict impact before making changes"
log_info "  optimize-server-resources            - Get optimization recommendations"
log_info ""
log_info "🎯 Example usage:"
log_info "  create-laravel-app web_sam testingsetup.rizqis.com https://github.com/CompleteLabs/web-app-sam.git"
log_info "  create-laravel-app web_crm_app crm.completelabs.com https://github.com/user/laravel-crm.git"
log_info "  create-laravel-app web_api_service api.completelabs.com"
log_info ""
log_info "🔥 Laravel Octane examples:"
log_info "  ./install.sh octane:install /opt/laravel-apps/web_sam"
log_info "  ./install.sh octane:start ."
log_info "  ./install.sh octane:optimize /var/www/laravel-app"
log_info "  ./install.sh debug                                   # Debug installation issues"
log_info ""
log_info "📝 App naming rules:"
log_info "  - Use underscores instead of dashes (web_sam not web-sam)"
log_info "  - Start with letter, only letters/numbers/underscores"
log_info "  - Examples: web_sam_l12, websaml12, webSamL12"
log_info ""
log_info "🔄 Horizontal Scaling examples:"
log_info "  scale-laravel-app web_sam_l12 scale-up 8001"
log_info "  scale-laravel-app web_sam_l12 scale-up 8002"
log_info "  status-laravel-app web_sam_l12"
log_info "  scale-laravel-app web_sam_l12 scale-down 8002"
log_info ""
log_info "🔍 Resource Monitoring examples:"
log_info "  monitor-server-resources                          # Check server capacity"
log_info "  analyze-app-resources                             # Detailed app analysis"
log_info "  predict-resource-impact new-app web_new_app       # Predict new app impact"
log_info "  predict-resource-impact scale-up web_sam_l12      # Predict scaling impact"
log_info "  predict-resource-impact remove-app web_old_app    # Predict removal impact"
log_info "  optimize-server-resources                         # Get optimization tips"
log_info ""
log_info "🔐 MySQL root password saved in: /root/.mysql_credentials"
log_info "🎉 Ready for FrankenPHP multi-app deployment!"
log_info ""
log_info "🚀 FrankenPHP + Laravel Octane Benefits:"
log_info "  - ⚡ Laravel Octane with FrankenPHP server (automatic binary download)"
log_info "  - 🌐 Built-in Caddy web server with reverse proxy"
log_info "  - 🔒 Auto HTTPS with Let's Encrypt"
log_info "  - 📈 Horizontal scaling with load balancer"
log_info "  - 🔧 Smart deployment detection (Octane vs standalone)"
log_info "  - 🎯 Optimized Laravel performance"
log_info "  - 🚀 Better memory management with workers"
log_info "  - 📦 GitHub integration with automatic Octane setup"
log_info "  - 🔄 Zero-downtime deployment"
log_info "  - 🧠 Dynamic worker optimization (CPU: $(nproc) cores → $OPTIMAL_THREADS workers)"
log_info ""
log_info "🎭 Deployment Modes:"
log_info "  - 🔥 Laravel Apps: Automatically use Laravel Octane with FrankenPHP"
log_info "  - 📁 Non-Laravel Apps: Fallback to standalone FrankenPHP"
log_info "  - 🔄 Mixed Environment: Support both modes simultaneously"
log_info ""
log_info "🔍 Resource Awareness System Benefits:"
log_info "  - 🛡️  Pre-flight checks prevent resource overcommitment"
log_info "  - 🧠 Smart thread allocation based on server capacity"
log_info "  - ⚠️  Warning system for resource thresholds"
log_info "  - 🚫 Hard limits prevent server crashes"
log_info "  - 📊 Real-time resource monitoring"
log_info "  - 🔮 Impact prediction for changes"
log_info "  - 💡 Optimization recommendations"
log_info "  - 📈 Capacity planning tools"
log_info "  - 🎯 Dynamic scaling decisions"
log_info "  - 🔧 Automated resource management"

# Display current resource warnings
display_resource_warnings
