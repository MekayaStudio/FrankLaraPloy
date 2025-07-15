#!/bin/bash

# =============================================
# System Setup Module
# Berisi fungsi-fungsi untuk instalasi dan konfigurasi sistem
# =============================================

# Load dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Fungsi untuk mengkonfigurasi mirror Ubuntu Indonesia
configure_ubuntu_mirror() {
    log_info "🇮🇩 Mengkonfigurasi mirror Ubuntu Indonesia untuk download yang lebih cepat..."
    
    # Backup sources.list asli
    cp /etc/apt/sources.list /etc/apt/sources.list.backup
    
    # Dapatkan versi Ubuntu
    local ubuntu_version=$(lsb_release -cs)
    
    # Konfigurasi mirror Indonesia
    cat > /etc/apt/sources.list <<EOF
# Mirror Ubuntu Indonesia - UNPAD (Universitas Padjadjaran)
deb $UBUNTU_MIRROR $ubuntu_version main restricted universe multiverse
deb $UBUNTU_MIRROR $ubuntu_version-updates main restricted universe multiverse
deb $UBUNTU_MIRROR $ubuntu_version-backports main restricted universe multiverse
deb $UBUNTU_SECURITY_MIRROR $ubuntu_version-security main restricted universe multiverse

# Mirror alternatif - UNEJ (Universitas Jember)
deb http://mirror.unej.ac.id/ubuntu/ $ubuntu_version main restricted universe multiverse
deb http://mirror.unej.ac.id/ubuntu/ $ubuntu_version-updates main restricted universe multiverse
deb http://mirror.unej.ac.id/ubuntu/ $ubuntu_version-backports main restricted universe multiverse
deb http://mirror.unej.ac.id/ubuntu/ $ubuntu_version-security main restricted universe multiverse

# Mirror alternatif - Repository.id
deb http://mirror.repository.id/ubuntu/ $ubuntu_version main restricted universe multiverse
deb http://mirror.repository.id/ubuntu/ $ubuntu_version-updates main restricted universe multiverse
deb http://mirror.repository.id/ubuntu/ $ubuntu_version-backports main restricted universe multiverse
deb http://mirror.repository.id/ubuntu/ $ubuntu_version-security main restricted universe multiverse
EOF

    log_info "✅ Mirror Ubuntu Indonesia dikonfigurasi"
}

# Fungsi untuk update sistem
update_system() {
    log_info "🔄 Memperbarui sistem packages..."
    
    # Update package list
    apt update || {
        log_warning "⚠️ Gagal update dari mirror UNPAD, mencoba mirror alternatif..."
        # Coba dengan mirror UNEJ sebagai fallback
        sed -i 's|mirror.unpad.ac.id|mirror.unej.ac.id|g' /etc/apt/sources.list
        apt update || {
            log_warning "⚠️ Gagal update dari mirror UNEJ, menggunakan mirror default..."
            cp /etc/apt/sources.list.backup /etc/apt/sources.list
            apt update
        }
    }
    
    # Upgrade packages
    apt upgrade -y
    
    log_info "✅ Sistem berhasil diperbarui"
}

# Fungsi untuk install packages essential
install_essential_packages() {
    log_info "📦 Menginstall packages essential..."
    
    apt install -y \
        curl \
        wget \
        unzip \
        git \
        supervisor \
        ufw \
        htop \
        nano \
        jq \
        net-tools \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        bc \
        zip \
        vim \
        tree \
        screen \
        tmux \
        fail2ban
    
    log_info "✅ Essential packages terinstall"
}

# Fungsi untuk install PHP
install_php() {
    log_info "🐘 Menginstall PHP $PHP_VERSION dan extensions..."
    
    # Tambahkan repository Ondrej PHP
    add-apt-repository -y ppa:ondrej/php
    apt update
    
    # Install PHP dan extensions
    apt install -y \
        php$PHP_VERSION \
        php$PHP_VERSION-cli \
        php$PHP_VERSION-common \
        php$PHP_VERSION-curl \
        php$PHP_VERSION-zip \
        php$PHP_VERSION-gd \
        php$PHP_VERSION-mysql \
        php$PHP_VERSION-pgsql \
        php$PHP_VERSION-sqlite3 \
        php$PHP_VERSION-xml \
        php$PHP_VERSION-mbstring \
        php$PHP_VERSION-bcmath \
        php$PHP_VERSION-intl \
        php$PHP_VERSION-redis \
        php$PHP_VERSION-imagick \
        php$PHP_VERSION-soap \
        php$PHP_VERSION-xdebug
    
    log_info "✅ PHP $PHP_VERSION terinstall"
}

# Fungsi untuk install Composer
install_composer() {
    log_info "🎼 Menginstall Composer..."
    
    # Download dan install Composer
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    
    # Verifikasi instalasi
    if composer --version >/dev/null 2>&1; then
        log_info "✅ Composer berhasil diinstall"
    else
        log_error "❌ Gagal menginstall Composer"
        return 1
    fi
}

# Fungsi untuk install Node.js
install_nodejs() {
    log_info "🟢 Menginstall Node.js $NODE_VERSION LTS..."
    
    # Tambahkan repository NodeSource
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
    
    # Install Node.js
    apt install -y nodejs
    
    # Install yarn sebagai alternatif npm
    npm install -g yarn
    
    # Verifikasi instalasi
    if node --version >/dev/null 2>&1; then
        log_info "✅ Node.js $(node --version) dan npm $(npm --version) terinstall"
    else
        log_error "❌ Gagal menginstall Node.js"
        return 1
    fi
}

# Fungsi untuk install MySQL
install_mysql() {
    log_info "🗄️ Menginstall MySQL $MYSQL_VERSION..."
    
    # Install MySQL Server
    apt install -y mysql-server
    
    # Generate root password
    local mysql_root_pass=$(generate_password)
    
    # Secure MySQL installation
    mysql_secure_installation <<EOF

y
2
$mysql_root_pass
$mysql_root_pass
y
y
y
y
EOF
    
    # Simpan credentials
    echo "MYSQL_ROOT_PASS=$mysql_root_pass" > /root/.mysql_credentials
    chmod 600 /root/.mysql_credentials
    
    log_info "✅ MySQL terinstall dengan password tersimpan di /root/.mysql_credentials"
}

# Fungsi untuk install Redis
install_redis() {
    log_info "🔴 Menginstall Redis..."
    
    apt install -y redis-server
    
    # Konfigurasi Redis untuk multi-app usage
    sed -i 's/^# maxmemory <bytes>/maxmemory 512mb/' /etc/redis/redis.conf
    sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
    
    # Start dan enable Redis
    systemctl enable redis-server
    systemctl start redis-server
    
    log_info "✅ Redis terinstall dan dikonfigurasi"
}

# Fungsi untuk setup direktori struktur
setup_directory_structure() {
    log_info "📁 Menyiapkan struktur direktori..."
    
    # Buat direktori utama
    create_directory "$APPS_BASE_DIR" "www-data:www-data" "755"
    create_directory "$LOG_DIR" "www-data:www-data" "755"
    create_directory "$BACKUP_DIR" "www-data:www-data" "755"
    create_directory "$CONFIG_DIR" "root:root" "755"
    
    log_info "✅ Struktur direktori berhasil dibuat"
}

# Fungsi untuk konfigurasi firewall
configure_firewall() {
    log_info "🔥 Mengkonfigurasi firewall..."
    
    # Enable UFW
    ufw --force enable
    
    # Allow essential ports
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 22/tcp
    
    # Allow MySQL dari localhost saja
    ufw allow from 127.0.0.1 to any port 3306
    
    # Allow Redis dari localhost saja
    ufw allow from 127.0.0.1 to any port 6379
    
    log_info "✅ Firewall dikonfigurasi"
}

# Fungsi untuk optimasi PHP untuk FrankenPHP
optimize_php() {
    log_info "⚡ Mengoptimasi PHP untuk FrankenPHP..."
    
    # Buat konfigurasi optimasi
    cat > /etc/php/$PHP_VERSION/cli/conf.d/99-frankenphp-optimizations.ini <<PHP_INI
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
    
    log_info "✅ PHP dioptimasi untuk FrankenPHP"
}

# Fungsi untuk setup logrotate
setup_logrotate() {
    log_info "🔄 Mengkonfigurasi logrotate..."
    
    cat > /etc/logrotate.d/laravel-apps <<EOF
$APPS_BASE_DIR/*/storage/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 www-data www-data
}

$LOG_DIR/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 www-data www-data
}
EOF
    
    log_info "✅ Logrotate dikonfigurasi"
}

# Fungsi untuk setup backup cron
setup_backup_cron() {
    log_info "📅 Mengkonfigurasi backup cron job..."
    
    # Tambahkan cron job untuk backup harian
    echo "0 2 * * * /usr/local/bin/backup-all-laravel-apps" | crontab -
    
    log_info "✅ Backup cron job dikonfigurasi (daily 2AM)"
}

# Fungsi untuk memulai services
start_services() {
    log_info "🚀 Memulai services..."
    
    # Start dan enable supervisor
    systemctl start supervisor
    systemctl enable supervisor
    
    # Verifikasi services
    if check_service_status "mysql"; then
        log_info "✅ MySQL berjalan"
    else
        log_error "❌ MySQL tidak berjalan"
    fi
    
    if check_service_status "redis-server"; then
        log_info "✅ Redis berjalan"
    else
        log_error "❌ Redis tidak berjalan"
    fi
    
    if check_service_status "supervisor"; then
        log_info "✅ Supervisor berjalan"
    else
        log_error "❌ Supervisor tidak berjalan"
    fi
}

# Fungsi utama untuk setup sistem lengkap
setup_system() {
    log_header "🚀 Memulai setup sistem FrankenPHP Multi-App..."
    
    # Cek koneksi internet
    if ! check_internet_connection; then
        log_error "❌ Koneksi internet diperlukan untuk instalasi"
        return 1
    fi
    
    # Cek disk space
    if ! check_disk_space 10; then
        log_error "❌ Minimal 10GB disk space diperlukan"
        return 1
    fi
    
    # Jalankan setup langkah demi langkah
    configure_ubuntu_mirror
    update_system
    install_essential_packages
    install_php
    install_composer
    install_nodejs
    install_mysql
    install_redis
    setup_directory_structure
    configure_firewall
    optimize_php
    setup_logrotate
    setup_backup_cron
    start_services
    
    log_info "✅ Setup sistem berhasil diselesaikan!"
}

# Export fungsi
export -f configure_ubuntu_mirror update_system install_essential_packages
export -f install_php install_composer install_nodejs install_mysql
export -f install_redis setup_directory_structure configure_firewall
export -f optimize_php setup_logrotate setup_backup_cron start_services
export -f setup_system 