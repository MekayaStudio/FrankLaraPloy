#!/bin/bash

# =============================================
# App Management Module
# Berisi fungsi-fungsi untuk operasi CRUD aplikasi Laravel
# =============================================

# Load dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/resource_management.sh"

# Fungsi untuk membuat aplikasi Laravel baru
create_laravel_app() {
    local app_name="$1"
    local domain="$2"
    local github_repo="$3"
    local db_name="${4:-${app_name}_db}"

    # Validasi input
    if ! validate_app_name "$app_name"; then
        return 1
    fi

    # Set current app name untuk rollback
    export CURRENT_APP_NAME="$app_name"

    # Cek apakah app sudah ada
    if app_exists "$app_name"; then
        log_error "App $app_name sudah ada!"
        return 1
    fi

    # Jalankan pre-flight resource check
    if ! preflight_resource_check "$app_name" "$github_repo"; then
        log_error "Pre-flight check gagal! Tidak dapat membuat app."
        return 1
    fi

    log_info "Membuat FrankenPHP Laravel app: $app_name"
    log_info "Domain: $domain"
    log_info "Database: $db_name"
    if [ -n "$github_repo" ]; then
        log_info "GitHub Repository: $github_repo"
    fi

    # Buat direktori aplikasi
    local app_dir="$APPS_BASE_DIR/$app_name"
    create_directory "$app_dir" "www-data:www-data" "755"
    export CREATED_APP_DIR="$app_dir"

    # Generate credentials database
    local db_user="${app_name}_user"
    local db_pass=$(generate_password)
    local db_name_clean=$(clean_mysql_name "$db_name")

    # Buat database dan user
    create_database "$db_name_clean" "$db_user" "$db_pass"

    # Simpan konfigurasi aplikasi
    save_app_config "$app_name" "$app_dir" "$domain" "$db_name_clean" "$db_user" "$db_pass" "$github_repo"

    # Clone atau setup Laravel app
    if [ -n "$github_repo" ]; then
        setup_laravel_from_github "$app_name" "$app_dir" "$github_repo" "$domain" "$db_name_clean" "$db_user" "$db_pass"
    else
        log_info "⚠️  Tidak ada GitHub repository yang diberikan, membuat direktori kosong"
        log_info "   Anda dapat deploy aplikasi Laravel secara manual ke: $app_dir"
    fi

    # Buat Caddyfile
    create_caddyfile "$app_name" "$app_dir" "$domain"

    # Download FrankenPHP binary
    download_frankenphp "$app_dir"

    # Buat systemd service
    create_systemd_service "$app_name" "$app_dir"

    # Buat supervisor config untuk queue workers
    create_supervisor_config "$app_name" "$app_dir"

    # Setup cron untuk Laravel scheduler
    setup_laravel_cron "$app_name" "$app_dir"

    # Reload dan enable services
    systemctl daemon-reload
    systemctl enable "frankenphp-$app_name"
    supervisorctl reread && supervisorctl update

    log_info "✅ FrankenPHP Laravel app $app_name berhasil dibuat!"
    log_info "📁 Directory: $app_dir"
    log_info "🌐 Domain: $domain"
    log_info "🗄️ Database: $db_name_clean"
    log_info "👤 DB User: $db_user"
    log_info "🔑 DB Pass: $db_pass"
    
    if [ -n "$github_repo" ]; then
        log_info "📦 GitHub Repo: $github_repo"
        log_info "🔧 Environment: Dikonfigurasi otomatis"
        log_info ""
        log_info "🚀 Aplikasi Laravel Anda siap untuk dijalankan!"
        log_info "   Jalankan: systemctl start frankenphp-$app_name"
        log_info "   Kunjungi: https://$domain (atau http://$domain untuk development)"
    else
        log_info ""
        log_info "Langkah selanjutnya:"
        log_info "1. Deploy aplikasi Anda ke $app_dir"
        log_info "2. Konfigurasi file .env"
        log_info "3. Jalankan: systemctl start frankenphp-$app_name"
        log_info "4. Kunjungi: https://$domain (atau http://$domain untuk development)"
    fi
}

# Fungsi untuk membuat database
create_database() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"

    # Dapatkan MySQL root password
    source /root/.mysql_credentials

    # Buat database dan user
    mysql -u root -p$MYSQL_ROOT_PASS <<MYSQL_EOF
CREATE DATABASE IF NOT EXISTS \`$db_name\`;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF

    export CREATED_DATABASE="$db_name"
    export CREATED_DB_USER="$db_user"
    
    log_info "✅ Database $db_name dan user $db_user berhasil dibuat"
}

# Fungsi untuk menyimpan konfigurasi aplikasi
save_app_config() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"
    local db_name="$4"
    local db_user="$5"
    local db_pass="$6"
    local github_repo="$7"

    local config_file="$CONFIG_DIR/$app_name.conf"
    
    cat > "$config_file" <<CONFIG_EOF
APP_NAME=$app_name
APP_DIR=$app_dir
DOMAIN=$domain
DB_NAME=$db_name
DB_USER=$db_user
DB_PASS=$db_pass
GITHUB_REPO=$github_repo
CONFIG_EOF

    export CREATED_CONFIG_FILE="$config_file"
    log_info "✅ Konfigurasi aplikasi disimpan"
}

# Fungsi untuk setup Laravel dari GitHub
setup_laravel_from_github() {
    local app_name="$1"
    local app_dir="$2"
    local github_repo="$3"
    local domain="$4"
    local db_name="$5"
    local db_user="$6"
    local db_pass="$7"

    log_info "📦 Mengclone aplikasi Laravel dari GitHub..."
    
    cd "$app_dir"
    git clone "$github_repo" .
    chown -R www-data:www-data "$app_dir"

    # Setup environment Laravel
    log_info "🔧 Menyiapkan environment Laravel..."

    # Copy .env.example ke .env jika ada
    if [ -f ".env.example" ]; then
        cp .env.example .env
        log_info "✅ Membuat .env dari .env.example"
    else
        log_info "⚠️  Tidak ditemukan .env.example, membuat .env dasar"
        create_basic_env_file "$domain" "$db_name" "$db_user" "$db_pass"
    fi

    # Update credentials database di .env
    update_env_database_credentials "$db_name" "$db_user" "$db_pass" "$domain"

    # Install dependencies jika composer.json ada
    if [ -f "composer.json" ]; then
        log_info "📦 Menginstall dependencies Composer..."
        composer install --no-dev --optimize-autoloader

        # Generate Laravel app key
        php artisan key:generate
        log_info "✅ Laravel app key dihasilkan"
    else
        log_info "⚠️  Tidak ditemukan composer.json, melewati composer install"
    fi

    # Install npm dependencies jika package.json ada
    if [ -f "package.json" ]; then
        log_info "📦 Menginstall dependencies NPM..."
        npm ci

        # Cek build scripts
        if npm run --silent 2>&1 | grep -q "build"; then
            log_info "🔨 Membangun frontend assets..."
            npm run build
            log_info "✅ Frontend assets berhasil dibangun"
        else
            log_info "⚠️  Tidak ditemukan build script, melewati npm build"
        fi
    else
        log_info "⚠️  Tidak ditemukan package.json, melewati npm install"
    fi

    # Jalankan migrasi database jika tersedia
    if [ -f "artisan" ]; then
        log_info "🗄️  Menjalankan migrasi database..."
        php artisan migrate --force || log_info "⚠️  Migrasi gagal atau tidak ada migrasi untuk dijalankan"

        # Clear dan cache konfigurasi
        php artisan config:clear
        php artisan config:cache
        php artisan route:clear
        php artisan route:cache
        php artisan view:clear
        php artisan view:cache

        log_info "✅ Optimasi Laravel selesai"
    fi

    # Set permission yang tepat
    chown -R www-data:www-data "$app_dir"
    chmod -R 755 "$app_dir"

    # Buat direktori storage dan cache jika tidak ada
    create_directory "$app_dir/storage/logs" "www-data:www-data" "775"
    create_directory "$app_dir/bootstrap/cache" "www-data:www-data" "775"

    log_info "✅ Aplikasi Laravel berhasil diclone dan dikonfigurasi"
}

# Fungsi untuk membuat file .env dasar
create_basic_env_file() {
    local domain="$1"
    local db_name="$2"
    local db_user="$3"
    local db_pass="$4"

    cat > .env <<ENV_EOF
APP_NAME=Laravel
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://$domain

LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$db_name
DB_USERNAME=$db_user
DB_PASSWORD=$db_pass

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
}

# Fungsi untuk update credentials database di .env
update_env_database_credentials() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"
    local domain="$4"

    log_info "🔧 Memperbarui credentials database di .env..."
    
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$db_name/" .env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$db_user/" .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_pass/" .env
    sed -i "s|APP_URL=.*|APP_URL=https://$domain|" .env
}

# Fungsi untuk membuat Caddyfile
create_caddyfile() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"

    # Gunakan smart threads jika tersedia
    local optimal_threads=$(calculate_optimal_threads)
    if [ -n "$SMART_THREADS" ]; then
        optimal_threads=$SMART_THREADS
    fi

    cat > "$app_dir/Caddyfile" <<CADDY_EOF
{
    frankenphp {
        num_threads $optimal_threads
    }
    # Auto HTTPS akan diaktifkan untuk domain asli
    auto_https off
}

# Konfigurasi domain utama
$domain {
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
        # Tambahkan HSTS untuk production
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # Logging
    log {
        format json
        output file $LOG_DIR/$app_name.log
        level INFO
    }

    # Handle upload file besar
    request_body {
        max_size 100MB
    }
}

# Opsional: Redirect www ke non-www
www.$domain {
    redir https://$domain{uri} permanent
}
CADDY_EOF

    log_info "✅ Caddyfile dibuat dengan $optimal_threads threads"
}

# Fungsi untuk download FrankenPHP binary
download_frankenphp() {
    local app_dir="$1"

    if [ ! -f "$app_dir/frankenphp" ]; then
        log_info "📥 Mendownload FrankenPHP binary..."
        cd "$app_dir"

        # Deteksi arsitektur
        local arch=$(uname -m)
        case $arch in
            x86_64)
                local franken_arch="x86_64"
                ;;
            aarch64|arm64)
                local franken_arch="aarch64"
                ;;
            *)
                log_error "Arsitektur tidak didukung: $arch"
                return 1
                ;;
        esac

        # Download FrankenPHP terbaru
        local franken_version=$(curl -s https://api.github.com/repos/dunglas/frankenphp/releases/latest | grep -oP '"tag_name": "\K[^"]+')
        local franken_url="https://github.com/dunglas/frankenphp/releases/download/${franken_version}/frankenphp-linux-${franken_arch}"

        if download_with_retry "$franken_url" "frankenphp"; then
            chmod +x frankenphp
            chown www-data:www-data frankenphp
            log_info "✅ FrankenPHP binary berhasil didownload: $franken_version"
        else
            log_error "❌ Gagal download FrankenPHP binary"
            return 1
        fi
    fi
}

# Fungsi untuk membuat systemd service
create_systemd_service() {
    local app_name="$1"
    local app_dir="$2"

    local service_file="/etc/systemd/system/frankenphp-$app_name.service"
    
    cat > "$service_file" <<SERVICE_EOF
[Unit]
Description=FrankenPHP Web Server for $app_name
After=network.target mysql.service redis.service
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=$app_dir/frankenphp run --config Caddyfile
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=10
Restart=always
RestartSec=5
SyslogIdentifier=frankenphp-$app_name

Environment=APP_ENV=production
Environment=APP_DEBUG=false

LimitNOFILE=65536
LimitNPROC=32768

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$app_dir/storage
ReadWritePaths=$app_dir/bootstrap/cache
ReadWritePaths=$app_dir/public/storage

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    export CREATED_SERVICE_FILE="$service_file"
    log_info "✅ Systemd service dibuat"
}

# Fungsi untuk membuat supervisor config
create_supervisor_config() {
    local app_name="$1"
    local app_dir="$2"

    local supervisor_file="/etc/supervisor/conf.d/laravel-worker-$app_name.conf"
    
    cat > "$supervisor_file" <<SUPERVISOR_EOF
[program:laravel-worker-$app_name]
process_name=%(program_name)s_%(process_num)02d
command=php $app_dir/artisan queue:work --sleep=3 --tries=3 --max-time=3600
directory=$app_dir
user=www-data
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
numprocs=2
redirect_stderr=true
stdout_logfile=$app_dir/storage/logs/worker.log
stopwaitsecs=3600
SUPERVISOR_EOF

    export CREATED_SUPERVISOR_FILE="$supervisor_file"
    log_info "✅ Supervisor config dibuat"
}

# Fungsi untuk setup cron Laravel
setup_laravel_cron() {
    local app_name="$1"
    local app_dir="$2"

    # Tambahkan cron job untuk Laravel scheduler
    (crontab -u www-data -l 2>/dev/null; echo "* * * * * cd $app_dir && php artisan schedule:run >> /dev/null 2>&1") | crontab -u www-data -
    
    export CREATED_CRON_JOBS="$app_name"
    log_info "✅ Cron job Laravel scheduler dibuat"
}

# Fungsi untuk deploy aplikasi
deploy_laravel_app() {
    local app_name="$1"
    local config_file="$CONFIG_DIR/$app_name.conf"

    if [ ! -f "$config_file" ]; then
        log_error "App $app_name tidak ditemukan!"
        return 1
    fi

    # Load konfigurasi aplikasi
    source "$config_file"

    cd "$APP_DIR"

    log_info "🚀 Deploying $app_name..."

    # Cek apakah ini aplikasi berbasis GitHub
    if [ -n "$GITHUB_REPO" ] && [ "$GITHUB_REPO" != "" ]; then
        log_info "📦 GitHub repository terdeteksi: $GITHUB_REPO"

        # Cek apakah git repository sudah diinisialisasi
        if [ -d ".git" ]; then
            log_info "🔄 Menarik perubahan terbaru dari GitHub..."
            git pull origin main || git pull origin master || log_info "⚠️  Gagal pull, melanjutkan dengan kode yang ada"
        else
            log_info "⚠️  Tidak ditemukan git repository, melewati pull"
        fi
    else
        log_info "📁 Deployment lokal (tidak ada GitHub repository yang dikonfigurasi)"
    fi

    # Install dependencies jika composer.json ada
    if [ -f "composer.json" ]; then
        log_info "📦 Menginstall dependencies Composer..."
        composer install --no-dev --optimize-autoloader
    else
        log_info "⚠️  Tidak ditemukan composer.json, melewati composer install"
    fi

    # Install npm dependencies dan build jika package.json ada
    if [ -f "package.json" ]; then
        log_info "📦 Menginstall dependencies NPM..."
        npm ci

        # Cek build scripts
        if npm run --silent 2>&1 | grep -q "build"; then
            log_info "🔨 Membangun frontend assets..."
            npm run build
        else
            log_info "⚠️  Tidak ditemukan build script, melewati npm build"
        fi
    else
        log_info "⚠️  Tidak ditemukan package.json, melewati npm install"
    fi

    # Optimasi Laravel jika artisan ada
    if [ -f "artisan" ]; then
        log_info "⚡ Menjalankan optimasi Laravel..."
        php artisan config:cache
        php artisan route:cache
        php artisan view:cache
        php artisan event:cache

        # Jalankan migrasi
        log_info "🗄️  Menjalankan migrasi database..."
        php artisan migrate --force

        # Clear cache
        php artisan cache:clear
        php artisan queue:restart
    else
        log_info "⚠️  Tidak ditemukan file artisan, melewati optimasi Laravel"
    fi

    # Perbaiki permissions
    chown -R www-data:www-data "$APP_DIR"
    chmod -R 755 "$APP_DIR"
    chmod -R 775 "$APP_DIR/storage" "$APP_DIR/bootstrap/cache"

    # Restart services
    restart_service "frankenphp-$app_name"
    supervisorctl restart "laravel-worker-$app_name:*"

    log_info "✅ Deployment selesai untuk $app_name!"
    log_info "🌐 Kunjungi: https://$DOMAIN"
}

# Fungsi untuk list aplikasi Laravel
list_laravel_apps() {
    log_info "📋 FrankenPHP Laravel Apps:"
    echo "=================================="

    for config in $CONFIG_DIR/*.conf; do
        if [ -f "$config" ]; then
            source "$config"
            local status=$(systemctl is-active "frankenphp-$APP_NAME" 2>/dev/null || echo "inactive")
            echo "🔸 $APP_NAME"
            echo "   Domain: $DOMAIN"
            echo "   Status: $status"
            echo "   Directory: $APP_DIR"
            echo "   URL: https://$DOMAIN"
            echo ""
        fi
    done
}

# Fungsi untuk menghapus aplikasi
remove_laravel_app() {
    local app_name="$1"
    local config_file="$CONFIG_DIR/$app_name.conf"

    if [ ! -f "$config_file" ]; then
        log_error "App $app_name tidak ditemukan!"
        return 1
    fi

    # Load konfigurasi aplikasi
    source "$config_file"

    log_info "🗑️ Menghapus Laravel app: $app_name"

    # Stop services
    systemctl stop "frankenphp-$app_name" || true
    systemctl disable "frankenphp-$app_name" || true
    supervisorctl stop "laravel-worker-$app_name:*" || true

    # Hapus service files
    rm -f "/etc/systemd/system/frankenphp-$app_name.service"
    rm -f "/etc/supervisor/conf.d/laravel-worker-$app_name.conf"

    # Hapus cron jobs
    crontab -u www-data -l 2>/dev/null | grep -v "$APP_DIR" | crontab -u www-data - || true

    # Hapus direktori aplikasi (dengan konfirmasi)
    read -p "Hapus direktori aplikasi $APP_DIR? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$APP_DIR"
        log_info "Direktori dihapus."
    fi

    # Hapus database (dengan konfirmasi)
    read -p "Hapus database $DB_NAME? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        source /root/.mysql_credentials
        mysql -u root -p$MYSQL_ROOT_PASS <<MYSQL_EOF
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
MYSQL_EOF
        log_info "Database dihapus."
    fi

    # Hapus config
    rm -f "$config_file"

    # Reload services
    systemctl daemon-reload
    supervisorctl reread && supervisorctl update

    log_info "✅ App $app_name berhasil dihapus!"
}

# Export fungsi
export -f create_laravel_app create_database save_app_config setup_laravel_from_github
export -f create_basic_env_file update_env_database_credentials create_caddyfile
export -f download_frankenphp create_systemd_service create_supervisor_config
export -f setup_laravel_cron deploy_laravel_app list_laravel_apps remove_laravel_app 