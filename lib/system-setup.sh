#!/bin/bash

# =============================================
# System Setup Library
# Library untuk setup system dan dependencies
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${SYSTEM_SETUP_LOADED:-}" ]; then
    return 0
fi
export SYSTEM_SETUP_LOADED=1

# Load dependencies
if [ -z "${SHARED_FUNCTIONS_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/shared-functions.sh"
fi
if [ -z "${ERROR_HANDLER_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/error-handler.sh"
fi
if [ -z "${VALIDATION_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/validation.sh"
fi

# =============================================
# System Validation Functions
# =============================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        handle_error "This script must be run as root. Use: sudo $0 $*" $ERROR_PERMISSION
        return 1
    fi
}

check_ubuntu() {
    if ! command -v apt-get &> /dev/null; then
        handle_error "This script requires Ubuntu/Debian with apt-get" $ERROR_VALIDATION
        return 1
    fi
    
    local version=$(lsb_release -rs 2>/dev/null || echo "unknown")
    log_info "Detected Ubuntu/Debian version: $version"
}

check_system_requirements() {
    log_info "🔍 Checking system requirements..."
    
    # Check if running as root
    check_root || return 1
    
    # Check OS
    check_ubuntu || return 1
    
    # Check available disk space (minimum 2GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then
        handle_error "Insufficient disk space. At least 2GB required." $ERROR_RESOURCE
        return 1
    fi
    
    # Check memory (minimum 1GB)
    local available_memory=$(free -m | awk 'NR==2{print $2}')
    if [[ $available_memory -lt 1024 ]]; then
        log_warning "Low memory detected ($available_memory MB). 1GB+ recommended."
    fi
    
    log_info "✅ System requirements check passed"
}

# =============================================
# System Setup Functions
# =============================================

update_system() {
    log_info "📦 Updating system packages..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Update package list
    if ! apt-get update -qq; then
        handle_error "Failed to update package list" $ERROR_NETWORK
        return 1
    fi
    
    # Upgrade critical packages
    if ! apt-get upgrade -y -qq; then
        handle_error "Failed to upgrade packages" $ERROR_NETWORK
        return 1
    fi
    
    # Install essential packages
    if ! apt-get install -y -qq \
        curl \
        wget \
        git \
        unzip \
        zip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        ufw \
        fail2ban \
        htop \
        tree \
        nano \
        vim \
        supervisor; then
        handle_error "Failed to install essential packages" $ERROR_DEPENDENCY
        return 1
    fi
    
    log_info "✅ System updated successfully"
}

install_php() {
    log_info "🐘 Installing PHP ${PHP_VERSION}..."
    
    # Skip adding PPA repository, use default Ubuntu repository
    log_info "Using default Ubuntu PHP repository..."
    
    if ! apt-get update -qq; then
        handle_error "Failed to update package list" $ERROR_NETWORK
        return 1
    fi
    
    # Install PHP and extensions
    local php_packages=(
        "php${PHP_VERSION}"
        "php${PHP_VERSION}-cli"
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-redis"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-bcmath"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-soap"
        "php${PHP_VERSION}-imagick"
        "php${PHP_VERSION}-opcache"
        "php${PHP_VERSION}-pdo"
        "php${PHP_VERSION}-sqlite3"
        "php${PHP_VERSION}-tokenizer"
        "php${PHP_VERSION}-fileinfo"
        "php${PHP_VERSION}-posix"
        "php${PHP_VERSION}-sockets"
    )
    
    if ! apt-get install -y -qq "${php_packages[@]}"; then
        handle_error "Failed to install PHP packages" $ERROR_DEPENDENCY
        return 1
    fi
    
    # Configure PHP for Laravel Octane
    configure_php_for_octane || return 1
    
    log_info "✅ PHP ${PHP_VERSION} installed successfully"
}

configure_php_for_octane() {
    log_info "🔧 Configuring PHP for Laravel Octane..."
    
    local php_ini="/etc/php/${PHP_VERSION}/cli/php.ini"
    local fpm_ini="/etc/php/${PHP_VERSION}/fpm/php.ini"
    
    # Configure PHP CLI (used by Octane)
    if [ -f "$php_ini" ]; then
        sed -i 's/memory_limit = .*/memory_limit = 512M/' "$php_ini"
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$php_ini"
        sed -i 's/post_max_size = .*/post_max_size = 100M/' "$php_ini"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' "$php_ini"
        sed -i 's/;pcntl.enabled = .*/pcntl.enabled = 1/' "$php_ini"
        sed -i 's/;opcache.enable = .*/opcache.enable = 1/' "$php_ini"
        sed -i 's/;opcache.enable_cli = .*/opcache.enable_cli = 1/' "$php_ini"
        sed -i 's/;opcache.memory_consumption = .*/opcache.memory_consumption = 128/' "$php_ini"
        sed -i 's/;opcache.interned_strings_buffer = .*/opcache.interned_strings_buffer = 8/' "$php_ini"
        sed -i 's/;opcache.max_accelerated_files = .*/opcache.max_accelerated_files = 4000/' "$php_ini"
        sed -i 's/;opcache.revalidate_freq = .*/opcache.revalidate_freq = 2/' "$php_ini"
        sed -i 's/;opcache.fast_shutdown = .*/opcache.fast_shutdown = 1/' "$php_ini"
    fi
    
    # Configure PHP-FPM as backup
    if [ -f "$fpm_ini" ]; then
        sed -i 's/memory_limit = .*/memory_limit = 512M/' "$fpm_ini"
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$fpm_ini"
        sed -i 's/post_max_size = .*/post_max_size = 100M/' "$fpm_ini"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' "$fpm_ini"
        sed -i 's/;opcache.enable = .*/opcache.enable = 1/' "$fpm_ini"
        sed -i 's/;opcache.memory_consumption = .*/opcache.memory_consumption = 128/' "$fpm_ini"
        sed -i 's/;opcache.interned_strings_buffer = .*/opcache.interned_strings_buffer = 8/' "$fpm_ini"
        sed -i 's/;opcache.max_accelerated_files = .*/opcache.max_accelerated_files = 4000/' "$fpm_ini"
        sed -i 's/;opcache.revalidate_freq = .*/opcache.revalidate_freq = 2/' "$fpm_ini"
        sed -i 's/;opcache.fast_shutdown = .*/opcache.fast_shutdown = 1/' "$fpm_ini"
    fi
    
    log_info "✅ PHP configured for Laravel Octane"
}

install_composer() {
    log_info "🎼 Installing Composer..."
    
    # Download and install Composer
    if ! curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php; then
        handle_error "Failed to download Composer installer" $ERROR_NETWORK
        return 1
    fi
    
    if ! php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer; then
        handle_error "Failed to install Composer" $ERROR_DEPENDENCY
        return 1
    fi
    
    rm -f /tmp/composer-setup.php
    
    # Make sure composer is executable
    chmod +x /usr/local/bin/composer
    
    log_info "✅ Composer installed successfully"
}

install_nodejs() {
    log_info "🟢 Installing Node.js ${NODE_VERSION}..."
    
    # Install Node.js repository
    if ! curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -; then
        handle_error "Failed to add Node.js repository" $ERROR_NETWORK
        return 1
    fi
    
    # Install Node.js and npm
    if ! apt-get install -y -qq nodejs; then
        handle_error "Failed to install Node.js" $ERROR_DEPENDENCY
        return 1
    fi
    
    # Install yarn
    if ! npm install -g yarn; then
        handle_error "Failed to install Yarn" $ERROR_DEPENDENCY
        return 1
    fi
    
    log_info "✅ Node.js ${NODE_VERSION} installed successfully"
}

install_mysql() {
    log_info "🐬 Installing MySQL..."
    
    # Set MySQL root password non-interactively
    local mysql_root_password=$(openssl rand -base64 32)
    
    # Pre-configure MySQL
    echo "mysql-server mysql-server/root_password password $mysql_root_password" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $mysql_root_password" | debconf-set-selections
    
    # Install MySQL
    if ! apt-get install -y -qq mysql-server; then
        handle_error "Failed to install MySQL" $ERROR_DEPENDENCY
        return 1
    fi
    
    # Save MySQL root password
    ensure_directory "/root/.laravel-apps"
    echo "$mysql_root_password" > "/root/.laravel-apps/mysql_root_password"
    chmod 600 "/root/.laravel-apps/mysql_root_password"
    
    # Enable and start MySQL
    systemctl enable mysql
    systemctl start mysql
    
    log_info "✅ MySQL installed successfully"
    log_info "📝 MySQL root password saved to /root/.laravel-apps/mysql_root_password"
}

install_redis() {
    log_info "🔴 Installing Redis..."
    
    # Install Redis
    if ! apt-get install -y -qq redis-server; then
        handle_error "Failed to install Redis" $ERROR_DEPENDENCY
        return 1
    fi
    
    # Configure Redis
    local redis_conf="/etc/redis/redis.conf"
    if [ -f "$redis_conf" ]; then
        sed -i 's/# maxmemory <bytes>/maxmemory 256mb/' "$redis_conf"
        sed -i 's/# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' "$redis_conf"
        sed -i 's/save 900 1/# save 900 1/' "$redis_conf"
        sed -i 's/save 300 10/# save 300 10/' "$redis_conf"
        sed -i 's/save 60 10000/# save 60 10000/' "$redis_conf"
    fi
    
    # Enable and start Redis
    systemctl enable redis-server
    systemctl start redis-server
    
    log_info "✅ Redis installed successfully"
}

prepare_frankenphp_directories() {
    log_info "� Preparing FrankenPHP directories..."
    
    # Create FrankenPHP directories
    ensure_directory "/var/lib/frankenphp"
    ensure_directory "/var/log/frankenphp"
    
    # Set permissions
    chown -R www-data:www-data /var/lib/frankenphp
    chown -R www-data:www-data /var/log/frankenphp
    
    log_info "✅ FrankenPHP directories prepared"
}

setup_firewall() {
    log_info "🔥 Setting up firewall..."
    
    # Reset UFW to default
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80
    ufw allow 443
    
    # Allow MySQL (only from localhost)
    ufw allow from 127.0.0.1 to any port 3306
    
    # Allow Redis (only from localhost)
    ufw allow from 127.0.0.1 to any port 6379
    
    # Enable UFW
    ufw --force enable
    
    log_info "✅ Firewall configured successfully"
}

setup_fail2ban() {
    log_info "🛡️  Setting up fail2ban..."
    
    # Configure fail2ban for SSH
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
    
    # Enable and start fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    log_info "✅ Fail2ban configured successfully"
}

create_directories() {
    log_info "📁 Creating required directories..."
    
    # Create base directories
    ensure_directory "$APPS_BASE_DIR"
    ensure_directory "$CONFIG_DIR"
    ensure_directory "$LOG_DIR"
    ensure_directory "$BACKUP_DIR"
    
    # Set proper permissions
    chown -R www-data:www-data "$APPS_BASE_DIR"
    chown -R www-data:www-data "$LOG_DIR"
    chown -R root:root "$CONFIG_DIR"
    chown -R root:root "$BACKUP_DIR"
    
    log_info "✅ Directories created successfully"
}

setup_system() {
    log_info "🚀 Starting FrankenPHP Multi-App system setup..."
    
    # System validation
    check_system_requirements || return 1
    
    # System setup steps
    update_system || return 1
    install_php || return 1
    install_composer || return 1
    install_nodejs || return 1
    install_mysql || return 1
    install_redis || return 1
    prepare_frankenphp_directories || return 1
    setup_firewall || return 1
    setup_fail2ban || return 1
    create_directories || return 1
    
    log_info "✅ System setup completed successfully!"
    log_info ""
    log_info "🎉 You can now install Laravel applications:"
    log_info "   sudo $0 install <app-name> <domain> [github-repo]"
    log_info ""
    log_info "🚀 FrankenPHP Features:"
    log_info "   • Laravel Octane with FrankenPHP server"
    log_info "   • Built-in PHP runtime (no PHP-FPM needed)"
    log_info "   • Pure Go performance with embedded Caddy"
    log_info "   • Automatic HTTPS with Let's Encrypt"  
    log_info "   • HTTP/2 and HTTP/3 support"
    log_info "   • Built-in compression and caching"
    log_info "   • Worker-based PHP processing"
    log_info "   • No reverse proxy needed"
}
