#!/bin/bash

# =============================================
# FrankenPHP Multi-App Installer
# One-command installer untuk FrankenPHP + Laravel Octane
# =============================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Simple functions for help
log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Load dependencies only for non-help commands
load_dependencies() {
    if [ -f "$SCRIPT_DIR/lib/shared-functions.sh" ]; then
        source "$SCRIPT_DIR/lib/shared-functions.sh"
        source "$SCRIPT_DIR/lib/error-handler.sh"
        source "$SCRIPT_DIR/lib/validation.sh"
        
        # Load configuration
        if [ -f "$SCRIPT_DIR/config/frankenphp-config.conf" ]; then
            source "$SCRIPT_DIR/config/frankenphp-config.conf"
        fi
    else
        log_error "Required libraries not found in $SCRIPT_DIR/lib/"
        exit 1
    fi
}

# Initialize for commands that need system directories
init_system_dirs() {
    if [ "$EUID" -eq 0 ]; then
        init_shared_functions
        init_error_handler
    fi
}

# =============================================
# Main Commands
# =============================================

show_help() {
    echo -e "\033[0;34m🚀 FrankenPHP Multi-App Installer\033[0m"
    echo -e "\033[0;34m=================================\033[0m"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "🏗️  System Commands:"
    echo "  setup                       - Setup sistem (install dependencies)"
    echo "  install <app> <domain> [repo] - Install Laravel app baru"
    echo "  deploy <app>                - Deploy ulang app"
    echo "  remove <app>                - Hapus app"
    echo ""
    echo "🔧 Laravel Octane Commands:"
    echo "  octane:install [dir]        - Install Laravel Octane + FrankenPHP"
    echo "  octane:start [dir]          - Start Octane server"
    echo "  octane:stop [dir]           - Stop Octane server"
    echo "  octane:restart [dir]        - Restart Octane server"
    echo "  octane:status [dir]         - Check Octane status"
    echo "  octane:optimize [dir]       - Optimize untuk production"
    echo ""
    echo "📊 Management Commands:"
    echo "  list                        - List semua apps"
    echo "  status <app>                - Status app"
    echo "  scale <app> <up|down> <port> - Scale app"
    echo "  monitor                     - Monitor resources"
    echo "  backup                      - Backup semua apps"
    echo ""
    echo "🔍 Debug Commands:"
    echo "  debug [app]                 - Debug app atau system"
    echo "  test                        - Test semua components"
    echo ""
    echo "🗄️  Database Commands:"
    echo "  db:check <app>              - Check database access untuk app"
    echo "  db:fix <app>                - Fix database access untuk app"
    echo "  db:reset <app>              - Reset database untuk app"
    echo "  db:list                     - List semua apps dan status database"
    echo "  db:status                   - Check MySQL service status"
    echo ""
    echo "Examples:"
    echo "  $0 setup                                    # Setup sistem"
    echo "  $0 install web_sam example.com             # Install app tanpa repo"
    echo "  $0 install web_sam example.com https://github.com/user/repo.git"
    echo "  $0 octane:install                           # Install Octane di current dir"
    echo "  $0 list                                     # List semua apps"
    echo "  $0 monitor                                  # Monitor resources"
    echo "  $0 db:fix web_sam                           # Fix database access"
    echo ""
}

# =============================================
# System Setup
# =============================================

setup_system() {
    log_info "🏗️ Setting up FrankenPHP Multi-App System..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run setup as root: sudo $0 setup"
        return 1
    fi
    
    # Initialize system directories
    init_system_dirs
    
    # Validate system requirements
    if ! validate_system_requirements "system_setup"; then
        display_validation_results
        return 1
    fi
    
    # Run the main deployer script
    log_info "Running system setup..."
    bash "$SCRIPT_DIR/frankenphp-multiapp-deployer.sh"
    
    log_info "✅ System setup completed!"
    log_info "🔧 You can now use: $0 install <app> <domain> [repo]"
}

# =============================================
# App Management
# =============================================

install_app() {
    local app_name="$1"
    local domain="$2"
    local github_repo="$3"
    local db_name="${4:-${app_name}_db}"
    
    if [ -z "$app_name" ] || [ -z "$domain" ]; then
        log_error "Usage: $0 install <app-name> <domain> [github-repo]"
        return 1
    fi
    
    # Validate parameters
    if ! validate_new_app_params "$app_name" "$domain" "$github_repo" "$db_name"; then
        display_validation_results
        return 1
    fi
    
    # Check if create-laravel-app command exists
    if ! command_exists create-laravel-app; then
        log_error "System not setup yet. Run: $0 setup"
        return 1
    fi
    
    # Install app
    log_info "🚀 Installing app: $app_name"
    create-laravel-app "$app_name" "$domain" "$github_repo" "$db_name"
    
    log_info "✅ App $app_name installed successfully!"
    log_info "🌐 Visit: https://$domain"
}

deploy_app() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "Usage: $0 deploy <app-name>"
        return 1
    fi
    
    # Check if app exists
    if [ ! -f "/etc/laravel-apps/$app_name.conf" ]; then
        log_error "App $app_name not found!"
        return 1
    fi
    
    # Deploy app
    log_info "🚀 Deploying app: $app_name"
    deploy-laravel-app "$app_name"
    
    log_info "✅ App $app_name deployed successfully!"
}

remove_app() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "Usage: $0 remove <app-name>"
        return 1
    fi
    
    # Check if app exists
    if [ ! -f "/etc/laravel-apps/$app_name.conf" ]; then
        log_error "App $app_name not found!"
        return 1
    fi
    
    # Confirm removal
    echo -n "Are you sure you want to remove $app_name? (y/N): "
    read -r confirmation
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        log_info "Removal cancelled"
        return 0
    fi
    
    # Remove app
    log_info "🗑️ Removing app: $app_name"
    remove-laravel-app "$app_name"
    
    log_info "✅ App $app_name removed successfully!"
}

# =============================================
# Laravel Octane Commands
# =============================================

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
    
    log_info "✅ Laravel app ditemukan di $dir"
    return 0
}

octane_install() {
    local dir="${1:-.}"
    
    log_info "🚀 Menginstal Laravel Octane dengan FrankenPHP..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Check if Octane is already installed
    if grep -q "laravel/octane" composer.json; then
        log_info "✅ Laravel Octane sudah terinstal"
    else
        log_info "📦 Menginstal Laravel Octane package..."
        if ! composer require laravel/octane; then
            log_error "Gagal menginstal Laravel Octane package"
            log_error "Pastikan:"
            log_error "  - Koneksi internet stabil"
            log_error "  - Composer sudah terinstal"
            log_error "  - PHP version kompatibel (8.1+)"
            return 1
        fi
        log_info "✅ Laravel Octane package berhasil diinstal"
    fi
    
    # Install FrankenPHP via Octane
    log_info "⬇️  Menginstal FrankenPHP via Laravel Octane..."
    log_info "Ini akan otomatis mendownload FrankenPHP binary yang sesuai dengan sistem Anda"
    
    # Run octane:install with proper error handling
    if php artisan octane:install --server=frankenphp --force; then
        log_info "✅ FrankenPHP berhasil diinstal via Laravel Octane"
    else
        log_error "Gagal menginstal FrankenPHP via Laravel Octane"
        log_error "Kemungkinan penyebab:"
        log_error "  - Koneksi internet bermasalah"
        log_error "  - GitHub API rate limit"
        log_error "  - Arsitektur sistem tidak didukung"
        log_error "  - Tidak ada akses write ke direktori"
        return 1
    fi
    
    # Publish Octane config
    if [ ! -f "config/octane.php" ]; then
        log_info "📝 Mempublish konfigurasi Octane..."
        if php artisan vendor:publish --provider="Laravel\Octane\OctaneServiceProvider" --tag=config; then
            log_info "✅ Konfigurasi Octane berhasil dipublish"
        else
            log_warning "⚠️  Gagal mempublish konfigurasi Octane"
        fi
    else
        log_info "✅ Konfigurasi Octane sudah ada"
    fi
    
    # Verify installation
    if [ -f "frankenphp" ]; then
        log_info "✅ FrankenPHP binary ditemukan di direktori app"
        chmod +x frankenphp
        # Check if we can get version
        if ./frankenphp version >/dev/null 2>&1; then
            FRANKEN_VERSION=$(./frankenphp version | head -1)
            log_info "🔧 FrankenPHP version: $FRANKEN_VERSION"
        fi
    else
        log_warning "⚠️  FrankenPHP binary tidak ditemukan di direktori app"
        log_info "Laravel Octane mungkin menginstalnya di lokasi lain"
    fi
    
    log_info "✅ Laravel Octane dengan FrankenPHP berhasil diinstal!"
    log_info "🔧 Untuk memulai server: php artisan octane:start --server=frankenphp"
    log_info "🔧 Atau gunakan: $0 octane:start"
}

octane_start() {
    local dir="${1:-.}"
    
    log_info "🚀 Memulai Laravel Octane server..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Check if Octane is installed
    if ! grep -q "laravel/octane" composer.json; then
        log_error "Laravel Octane belum terinstal!"
        log_info "Jalankan: $0 octane:install"
        return 1
    fi
    
    # Get configuration from .env
    local host="0.0.0.0"
    local port="8000"
    local workers="4"
    
    if [ -f ".env" ]; then
        if grep -q "OCTANE_HOST" .env; then
            host=$(grep "OCTANE_HOST" .env | cut -d'=' -f2)
        fi
        if grep -q "OCTANE_PORT" .env; then
            port=$(grep "OCTANE_PORT" .env | cut -d'=' -f2)
        fi
        if grep -q "OCTANE_WORKERS" .env; then
            workers=$(grep "OCTANE_WORKERS" .env | cut -d'=' -f2)
        fi
    fi
    
    log_info "🌐 Starting server pada $host:$port dengan $workers workers..."
    
    # Start Octane server
    php artisan octane:start --server=frankenphp --host=$host --port=$port --workers=$workers
}

octane_stop() {
    local dir="${1:-.}"
    
    log_info "🛑 Menghentikan Laravel Octane server..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Stop Octane server
    php artisan octane:stop || log_info "Server mungkin sudah berhenti"
    
    log_info "✅ Laravel Octane server dihentikan"
}

octane_restart() {
    local dir="${1:-.}"
    
    log_info "🔄 Restarting Laravel Octane server..."
    octane_stop "$dir"
    sleep 2
    octane_start "$dir"
}

octane_status() {
    local dir="${1:-.}"
    
    log_info "📊 Memeriksa status Laravel Octane server..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Check Octane status
    php artisan octane:status || log_info "Server tidak berjalan"
}

octane_optimize() {
    local dir="${1:-.}"
    
    log_info "⚡ Mengoptimalkan Laravel app untuk Octane..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Laravel optimizations
    log_info "🔧 Menjalankan optimisasi Laravel..."
    
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache
    
    # Octane specific optimizations
    if grep -q "laravel/octane" composer.json; then
        log_info "🚀 Menjalankan optimisasi Octane..."
        
        # Clear Octane cache
        php artisan octane:clear
        
        # Reload workers if running
        php artisan octane:reload || log_info "Server tidak berjalan, skip reload"
    fi
    
    log_info "✅ Optimisasi selesai!"
}

# =============================================
# Management Commands
# =============================================

list_apps() {
    log_info "📋 Listing all Laravel apps..."
    
    # Check if apps directory exists
    if [ ! -d "$APPS_BASE_DIR" ]; then
        log_error "Apps directory not found: $APPS_BASE_DIR"
        log_error "System not setup yet. Run: sudo $0 setup"
        return 1
    fi
    
    if command_exists list-laravel-apps; then
        list-laravel-apps
    else
        log_error "System not setup yet. Run: sudo $0 setup"
        return 1
    fi
}

status_app() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "Usage: $0 status <app-name>"
        return 1
    fi
    
    log_info "📊 Checking status for: $app_name"
    if command_exists status-laravel-app; then
        status-laravel-app "$app_name"
    else
        log_error "System not setup yet. Run: $0 setup"
        return 1
    fi
}

scale_app() {
    local app_name="$1"
    local action="$2"
    local port="$3"
    
    if [ -z "$app_name" ] || [ -z "$action" ] || [ -z "$port" ]; then
        log_error "Usage: $0 scale <app-name> <up|down> <port>"
        return 1
    fi
    
    log_info "📈 Scaling app: $app_name"
    if command_exists scale-laravel-app; then
        scale-laravel-app "$app_name" "scale-$action" "$port"
    else
        log_error "System not setup yet. Run: $0 setup"
        return 1
    fi
}

monitor_resources() {
    log_info "📊 Monitoring server resources..."
    
    # Check if apps directory exists
    if [ ! -d "$APPS_BASE_DIR" ]; then
        log_error "Apps directory not found: $APPS_BASE_DIR"
        log_error "System not setup yet. Run: sudo $0 setup"
        return 1
    fi
    
    if command_exists monitor-server-resources; then
        monitor-server-resources
    else
        log_error "System not setup yet. Run: sudo $0 setup"
        return 1
    fi
}

backup_apps() {
    log_info "💾 Backing up all apps..."
    if command_exists backup-all-laravel-apps; then
        backup-all-laravel-apps
    else
        log_error "System not setup yet. Run: $0 setup"
        return 1
    fi
}

# =============================================
# Database Troubleshooting Commands
# =============================================

check_mysql_service() {
    log_info "Checking MySQL service..."
    
    if systemctl is-active --quiet mysql; then
        log_info "✅ MySQL service is running"
        return 0
    elif systemctl is-active --quiet mysqld; then
        log_info "✅ MySQL service is running (mysqld)"
        return 0
    else
        log_error "❌ MySQL service is not running"
        log_info "Try: sudo systemctl start mysql"
        return 1
    fi
}

get_mysql_root_password() {
    local root_pass=""
    
    # Check if credentials file exists
    if [ -f "/root/.mysql_credentials" ]; then
        source /root/.mysql_credentials
        root_pass="$MYSQL_ROOT_PASS"
        log_info "✅ Found MySQL root credentials file"
    else
        log_warning "⚠️  MySQL root credentials file not found"
        echo -n "Enter MySQL root password: "
        read -s root_pass
        echo ""
    fi
    
    # Test connection
    if mysql -u root -p"$root_pass" -e "SELECT 1;" >/dev/null 2>&1; then
        log_info "✅ MySQL root connection successful"
        echo "$root_pass"
        return 0
    else
        log_error "❌ MySQL root connection failed"
        return 1
    fi
}

check_app_database() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "App name is required"
        return 1
    fi
    
    log_info "Checking database access for app: $app_name"
    
    # Check if app config exists
    local config_file="/etc/laravel-apps/$app_name.conf"
    if [ ! -f "$config_file" ]; then
        log_error "App configuration not found: $config_file"
        log_info "Available apps:"
        ls -1 /etc/laravel-apps/*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$||' | sed 's/^/  - /' || log_info "  No apps found"
        return 1
    fi
    
    # Load app config
    source "$config_file"
    
    log_info "App configuration:"
    log_info "  - Database: $DB_NAME"
    log_info "  - User: $DB_USER"
    log_info "  - App Dir: $APP_DIR"
    
    # Get MySQL root password
    local root_pass
    if ! root_pass=$(get_mysql_root_password); then
        return 1
    fi
    
    # Check if database exists
    local db_exists
    db_exists=$(mysql -u root -p"$root_pass" -e "SHOW DATABASES LIKE '$DB_NAME';" 2>/dev/null | grep -c "$DB_NAME" || echo "0")
    
    if [ "$db_exists" -gt 0 ]; then
        log_info "✅ Database '$DB_NAME' exists"
    else
        log_error "❌ Database '$DB_NAME' does not exist"
        return 1
    fi
    
    # Check if user exists
    local user_exists
    user_exists=$(mysql -u root -p"$root_pass" -e "SELECT COUNT(*) FROM mysql.user WHERE User='$DB_USER' AND Host='localhost';" 2>/dev/null | tail -1)
    
    if [ "$user_exists" -gt 0 ]; then
        log_info "✅ User '$DB_USER' exists"
    else
        log_error "❌ User '$DB_USER' does not exist"
        return 1
    fi
    
    # Test user connection
    if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" >/dev/null 2>&1; then
        log_info "✅ User '$DB_USER' can access database '$DB_NAME'"
        return 0
    else
        log_error "❌ User '$DB_USER' cannot access database '$DB_NAME'"
        return 1
    fi
}

fix_app_database() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "App name is required"
        return 1
    fi
    
    log_info "Fixing database access for app: $app_name"
    
    # Check if app config exists
    local config_file="/etc/laravel-apps/$app_name.conf"
    if [ ! -f "$config_file" ]; then
        log_error "App configuration not found: $config_file"
        return 1
    fi
    
    # Load app config
    source "$config_file"
    
    # Get MySQL root password
    local root_pass
    if ! root_pass=$(get_mysql_root_password); then
        return 1
    fi
    
    log_info "Creating/fixing database and user..."
    
    # Create database and user with proper permissions
    mysql -u root -p"$root_pass" <<MYSQL_EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF
    
    if [ $? -eq 0 ]; then
        log_info "✅ Database and user created/fixed successfully"
        
        # Test connection
        if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" >/dev/null 2>&1; then
            log_info "✅ Database connection test successful"
            
            # Update .env file if app directory exists
            if [ -d "$APP_DIR" ] && [ -f "$APP_DIR/.env" ]; then
                log_info "Updating .env file..."
                
                # Create backup
                cp "$APP_DIR/.env" "$APP_DIR/.env.backup"
                
                # Update database credentials
                sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" "$APP_DIR/.env"
                sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USER/" "$APP_DIR/.env"
                sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" "$APP_DIR/.env"
                
                log_info "✅ .env file updated"
            fi
            
            return 0
        else
            log_error "❌ Database connection test failed"
            return 1
        fi
    else
        log_error "❌ Failed to create/fix database and user"
        return 1
    fi
}

reset_app_database() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "App name is required"
        return 1
    fi
    
    log_warning "⚠️  This will completely reset the database for app: $app_name"
    echo -n "Are you sure? (y/N): "
    read -r confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Operation cancelled"
        return 0
    fi
    
    # Check if app config exists
    local config_file="/etc/laravel-apps/$app_name.conf"
    if [ ! -f "$config_file" ]; then
        log_error "App configuration not found: $config_file"
        return 1
    fi
    
    # Load app config
    source "$config_file"
    
    # Get MySQL root password
    local root_pass
    if ! root_pass=$(get_mysql_root_password); then
        return 1
    fi
    
    log_info "Resetting database and user..."
    
    # Drop database and user, then recreate
    mysql -u root -p"$root_pass" <<MYSQL_EOF
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
CREATE DATABASE \`$DB_NAME\`;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF
    
    if [ $? -eq 0 ]; then
        log_info "✅ Database and user reset successfully"
        
        # Run migrations if Laravel app exists
        if [ -d "$APP_DIR" ] && [ -f "$APP_DIR/artisan" ]; then
            log_info "Running Laravel migrations..."
            cd "$APP_DIR"
            
            # Make sure .env is correct
            sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
            sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
            sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" .env
            
            # Run migrations
            php artisan migrate --force
            
            if [ $? -eq 0 ]; then
                log_info "✅ Laravel migrations completed"
            else
                log_warning "⚠️  Laravel migrations failed, but database was reset"
            fi
        fi
        
        return 0
    else
        log_error "❌ Failed to reset database and user"
        return 1
    fi
}

list_apps_database() {
    log_info "📋 Listing all apps and their database status..."
    
    if [ ! -d "/etc/laravel-apps" ]; then
        log_error "No apps directory found. System may not be setup."
        return 1
    fi
    
    local apps_found=0
    
    for config_file in /etc/laravel-apps/*.conf; do
        if [ -f "$config_file" ]; then
            apps_found=1
            local app_name=$(basename "$config_file" .conf)
            
            echo ""
            log_header "📱 App: $app_name"
            
            # Load config
            source "$config_file"
            
            echo "  Database: $DB_NAME"
            echo "  User: $DB_USER"
            echo "  Directory: $APP_DIR"
            
            # Quick check
            if check_app_database "$app_name" >/dev/null 2>&1; then
                echo "  Status: ✅ Database access OK"
            else
                echo "  Status: ❌ Database access FAILED"
            fi
        fi
    done
    
    if [ $apps_found -eq 0 ]; then
        log_info "No apps found."
    fi
}

mysql_status() {
    log_info "📊 Checking MySQL status..."
    
    check_mysql_service
    
    # Check if we can connect as root
    if get_mysql_root_password >/dev/null 2>&1; then
        log_info "✅ MySQL root access OK"
    else
        log_error "❌ MySQL root access FAILED"
    fi
    
    # Show MySQL version
    local mysql_version
    mysql_version=$(mysql --version 2>/dev/null || echo "MySQL not found")
    log_info "MySQL version: $mysql_version"
}

# =============================================
# Debug Commands
# =============================================

debug_octane_detailed() {
    local dir="${1:-.}"
    
    log_info "🔍 Debugging Laravel Octane installation..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    echo ""
    log_header "📊 SYSTEM INFORMATION"
    echo "OS: $(uname -s)"
    echo "Architecture: $(uname -m)"
    echo "PHP Version: $(php -v | head -1)"
    echo "Composer Version: $(composer --version 2>/dev/null || echo 'Not installed')"
    
    echo ""
    log_header "📦 LARAVEL INFORMATION"
    if [ -f "artisan" ]; then
        echo "Laravel Version: $(php artisan --version 2>/dev/null || echo 'Unknown')"
    fi
    
    echo ""
    log_header "🔧 OCTANE STATUS"
    if grep -q "laravel/octane" composer.json; then
        echo "✅ Laravel Octane package: Installed"
        
        # Get Octane version
        OCTANE_VERSION=$(composer show laravel/octane 2>/dev/null | grep "versions" | head -1 || echo "Unknown")
        echo "Octane Version: $OCTANE_VERSION"
    else
        echo "❌ Laravel Octane package: Not installed"
    fi
    
    if [ -f "config/octane.php" ]; then
        echo "✅ Octane config: Published"
    else
        echo "❌ Octane config: Not published"
    fi
    
    echo ""
    log_header "🚀 FRANKENPHP STATUS"
    if [ -f "frankenphp" ]; then
        echo "✅ FrankenPHP binary: Found in app directory"
        echo "File size: $(ls -lh frankenphp | awk '{print $5}')"
        echo "Permissions: $(ls -l frankenphp | awk '{print $1}')"
        
        if [ -x "frankenphp" ]; then
            echo "✅ Executable: Yes"
            if ./frankenphp version >/dev/null 2>&1; then
                echo "✅ Working: Yes"
                echo "Version: $(./frankenphp version | head -1)"
            else
                echo "❌ Working: No (might be missing dependencies)"
            fi
        else
            echo "❌ Executable: No"
        fi
    else
        echo "❌ FrankenPHP binary: Not found in app directory"
        
        # Check if it's in vendor directory
        if [ -f "vendor/bin/frankenphp" ]; then
            echo "✅ FrankenPHP binary: Found in vendor/bin"
        else
            echo "❌ FrankenPHP binary: Not found in vendor/bin either"
        fi
    fi
    
    echo ""
    log_header "🌐 NETWORK CONNECTIVITY"
    if ping -c 1 google.com >/dev/null 2>&1; then
        echo "✅ Internet connectivity: OK"
    else
        echo "❌ Internet connectivity: Failed"
    fi
    
    if curl -s https://api.github.com/repos/php/frankenphp/releases/latest >/dev/null 2>&1; then
        echo "✅ GitHub API access: OK"
    else
        echo "❌ GitHub API access: Failed"
    fi
    
    echo ""
    log_header "📝 ENVIRONMENT VARIABLES"
    if [ -f ".env" ]; then
        echo "✅ .env file: Found"
        
        if grep -q "OCTANE_SERVER" .env; then
            echo "✅ OCTANE_SERVER: $(grep OCTANE_SERVER .env | cut -d'=' -f2)"
        else
            echo "❌ OCTANE_SERVER: Not set"
        fi
        
        if grep -q "OCTANE_HOST" .env; then
            echo "✅ OCTANE_HOST: $(grep OCTANE_HOST .env | cut -d'=' -f2)"
        else
            echo "❌ OCTANE_HOST: Not set"
        fi
        
        if grep -q "OCTANE_PORT" .env; then
            echo "✅ OCTANE_PORT: $(grep OCTANE_PORT .env | cut -d'=' -f2)"
        else
            echo "❌ OCTANE_PORT: Not set"
        fi
        
        if grep -q "OCTANE_WORKERS" .env; then
            echo "✅ OCTANE_WORKERS: $(grep OCTANE_WORKERS .env | cut -d'=' -f2)"
        else
            echo "❌ OCTANE_WORKERS: Not set"
        fi
    else
        echo "❌ .env file: Not found"
    fi
    
    echo ""
    log_header "💡 RECOMMENDATIONS"
    
    if ! grep -q "laravel/octane" composer.json; then
        echo "🔧 Run: $0 octane:install"
    fi
    
    if [ ! -f "config/octane.php" ]; then
        echo "🔧 Run: $0 octane:install"
    fi
    
    if [ ! -f "frankenphp" ] && [ ! -f "vendor/bin/frankenphp" ]; then
        echo "🔧 Run: php artisan octane:install --server=frankenphp --force"
    fi
    
    if [ -f ".env" ] && ! grep -q "OCTANE_SERVER" .env; then
        echo "🔧 Run: $0 octane:install"
    fi
    
    echo ""
    log_info "🔍 Debug completed. Check the information above for any issues."
}

debug_system() {
    local app_name="$1"
    
    if [ -n "$app_name" ]; then
        log_info "🔍 Debugging app: $app_name"
        if [ -f "/etc/laravel-apps/$app_name.conf" ]; then
            source "/etc/laravel-apps/$app_name.conf"
            debug_octane_detailed "$APP_DIR"
        else
            log_error "App $app_name not found!"
            return 1
        fi
    else
        log_info "🔍 Debugging system..."
        debug_octane_detailed
    fi
}

test_components() {
    log_info "🧪 Testing all components..."
    
    # Test basic functionality without requiring special permissions
    log_info "Testing basic validation..."
    
    # Test app name validation (simple)
    if [[ "test_app" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
        log_info "✅ App name validation test passed"
    else
        log_error "❌ App name validation test failed"
    fi
    
    # Test domain validation (simple)
    if [[ "example.com" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_info "✅ Domain validation test passed"
    else
        log_error "❌ Domain validation test failed"
    fi
    
    # Test system info
    log_info "Testing system info..."
    local cpu_cores=$(nproc 2>/dev/null || echo "unknown")
    local memory_mb=$(free -m 2>/dev/null | awk 'NR==2{print $2}' || echo "unknown")
    log_info "✅ System info: ${memory_mb}MB memory, ${cpu_cores} CPU cores"
    
    # Test file existence
    log_info "Testing file structure..."
    if [ -f "$SCRIPT_DIR/lib/shared-functions.sh" ]; then
        log_info "✅ Shared functions library found"
    else
        log_error "❌ Shared functions library not found"
    fi
    
    if [ -f "$SCRIPT_DIR/lib/error-handler.sh" ]; then
        log_info "✅ Error handler library found"
    else
        log_error "❌ Error handler library not found"
    fi
    
    if [ -f "$SCRIPT_DIR/lib/validation.sh" ]; then
        log_info "✅ Validation library found"
    else
        log_error "❌ Validation library not found"
    fi
    
    if [ -f "$SCRIPT_DIR/config/frankenphp-config.conf" ]; then
        log_info "✅ Configuration file found"
    else
        log_error "❌ Configuration file not found"
    fi
    
    log_info "✅ All component tests completed!"
}

# =============================================
# Quick Commands (shortcuts)
# =============================================

quick_setup_and_install() {
    local app_name="$1"
    local domain="$2"
    local github_repo="$3"
    
    if [ -z "$app_name" ] || [ -z "$domain" ]; then
        log_error "Usage: $0 quick <app-name> <domain> [github-repo]"
        return 1
    fi
    
    log_info "🚀 Quick setup and install..."
    
    # Setup system if not already done
    if ! command_exists create-laravel-app; then
        log_info "Setting up system first..."
        setup_system
    fi
    
    # Install app
    install_app "$app_name" "$domain" "$github_repo"
    
    log_info "✅ Quick setup completed!"
    log_info "🌐 Your app is ready at: https://$domain"
}

# =============================================
# Main Command Router
# =============================================

main() {
    local command="$1"
    
    # Show help for empty command or help commands
    if [ -z "$command" ] || [ "$command" = "help" ] || [ "$command" = "--help" ] || [ "$command" = "-h" ]; then
        show_help
        exit 0
    fi
    
    # Test command doesn't need dependencies
    if [ "$command" = "test" ]; then
        test_components
        exit 0
    fi
    
    shift
    
    # Load dependencies for other commands
    load_dependencies
    
    case "$command" in
        # System commands
        "setup")
            setup_system
            ;;
        "install")
            install_app "$@"
            ;;
        "deploy")
            deploy_app "$@"
            ;;
        "remove")
            remove_app "$@"
            ;;
            
        # Laravel Octane commands
        "octane:install")
            octane_install "$@"
            ;;
        "octane:start")
            octane_start "$@"
            ;;
        "octane:stop")
            octane_stop "$@"
            ;;
        "octane:restart")
            octane_restart "$@"
            ;;
        "octane:status")
            octane_status "$@"
            ;;
        "octane:optimize")
            octane_optimize "$@"
            ;;
            
        # Management commands
        "list")
            list_apps
            ;;
        "status")
            status_app "$@"
            ;;
        "scale")
            scale_app "$@"
            ;;
        "monitor")
            monitor_resources
            ;;
        "backup")
            backup_apps
            ;;
            
        # Debug commands
        "debug")
            debug_system "$@"
            ;;
        "test")
            # Test command doesn't need full dependencies
            test_components
            exit 0
            ;;
            
        # Database commands
        "db:check")
            check_mysql_service
            check_app_database "$2"
            ;;
        "db:fix")
            check_mysql_service
            fix_app_database "$2"
            ;;
        "db:reset")
            check_mysql_service
            reset_app_database "$2"
            ;;
        "db:list")
            check_mysql_service
            list_apps_database
            ;;
        "db:status")
            mysql_status
            ;;
            
        # Quick commands
        "quick")
            quick_setup_and_install "$@"
            ;;
            
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# =============================================
# Script Execution
# =============================================

# Run main function
main "$@" 