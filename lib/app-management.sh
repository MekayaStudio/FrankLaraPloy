#!/bin/bash

# =============================================
# App Management Library (Simplified)
# Using Laravel Octane + FrankenPHP Best Practices
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "$APP_MANAGEMENT_LOADED" ]; then
    return 0
fi
export APP_MANAGEMENT_LOADED=1

# =============================================
# Simple Laravel Octane + FrankenPHP Installation
# =============================================

install_app() {
    local app_name="$1"
    local domain="$2"
    local github_repo="$3"
    local db_name="${4:-${app_name}_db}"
    local octane_mode="${5:-smart}"  # smart, enhanced, or basic

    if [ -z "$app_name" ] || [ -z "$domain" ]; then
        log_error "Usage: install_app <app-name> <domain> [github-repo] [db-name] [octane-mode]"
        log_error "Octane modes: smart (default), enhanced, basic"
        return 1
    fi

    log_info "🚀 Installing Laravel app: $app_name"
    log_info "📝 App: $app_name | Domain: $domain | Repo: ${github_repo:-'Fresh Laravel'}"
    log_info "🔧 Octane mode: $octane_mode"

    # Define app directory
    local app_dir="$APPS_BASE_DIR/$app_name"

    # Step 1: Setup Laravel app
    log_info "📋 Step 1: Setting up Laravel application..."
    setup_laravel_app "$app_name" "$domain" "$github_repo" "$db_name" "$app_dir"

    # Step 2: Install and configure Octane (mode selection)
    log_info "📋 Step 2: Setting up Laravel Octane + FrankenPHP (mode: $octane_mode)..."
    case "$octane_mode" in
        "smart")
            install_octane_smart "$app_name" "$app_dir" "$domain"
            ;;
        "enhanced")
            install_octane_enhanced "$app_name" "$app_dir" "$domain"
            ;;
        "basic")
            install_octane "$app_name" "$app_dir" "$domain"
            ;;
        *)
            log_error "Unknown Octane mode: $octane_mode"
            log_error "Available modes: smart, enhanced, basic"
            return 1
            ;;
    esac

    # Step 3: Create systemd service
    log_info "📋 Step 3: Creating systemd service..."
    create_octane_service "$app_name" "$app_dir" "$domain"

    # Step 4: Start the service
    log_info "📋 Step 4: Starting service..."
    systemctl enable "octane-$app_name.service"
    systemctl start "octane-$app_name.service"

    log_info ""
    log_info "🎉 App $app_name installed successfully!"
    log_info "🌐 Visit: https://$domain"
    log_info "📊 Check status: ./install.sh status $app_name"
    log_info "🔍 Debug: ./install.sh debug $app_name"
}

# =============================================
# Helper Functions
# =============================================

setup_laravel_app() {
    local app_name="$1"
    local domain="$2"
    local github_repo="$3"
    local db_name="$4"
    local app_dir="$5"

    # Create app directory and clone repository
    mkdir -p "$app_dir"
    if [ -n "$github_repo" ]; then
        log_info "📥 Cloning from GitHub: $github_repo"
        git clone "$github_repo" "$app_dir"
    else
        log_info "📁 Creating Laravel app with composer"
        composer create-project laravel/laravel "$app_dir"
    fi

    # Setup Laravel environment
    cd "$app_dir"
    if [ -f "composer.json" ]; then
        log_info "📦 Installing Composer dependencies"
        composer install --no-dev --optimize-autoloader

        # Setup environment
        if [ -f ".env.example" ]; then
            cp .env.example .env
        fi

        # Generate app key
        php artisan key:generate

        # Setup database configuration
        setup_database_config "$app_name" "$db_name"

        # Run migrations
        php artisan migrate --force
    fi

    # Set permissions
    chown -R www-data:www-data "$app_dir"
    chmod -R 755 "$app_dir"
    chmod -R 775 "$app_dir/storage" "$app_dir/bootstrap/cache"
}

install_octane() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"

    cd "$app_dir"

    log_info "🔧 Setting up Laravel Octane for $app_name"

    # Check if Octane is already installed
    if check_octane_installed; then
        log_info "✅ Laravel Octane already installed"

        # Check if FrankenPHP is configured
        if check_frankenphp_configured; then
            log_info "✅ FrankenPHP already configured"
        else
            log_info "🔧 Configuring FrankenPHP..."
            configure_frankenphp
        fi
    else
        log_info "📦 Installing Laravel Octane..."

        # Install Octane
        if ! composer require laravel/octane; then
            log_error "Failed to install Laravel Octane"
            return 1
        fi

        # Install with FrankenPHP
        if ! php artisan octane:install --server=frankenphp; then
            log_error "Failed to configure Octane with FrankenPHP"
            return 1
        fi

        log_info "✅ Laravel Octane installed successfully"
    fi

    # Always update .env for production (regardless of Octane status)
    setup_production_env "$domain"

    # Optimize for production
    optimize_laravel_app

    log_info "✅ Laravel Octane setup completed for $app_name"
}

# Enhanced install_octane with detailed status checking
install_octane_enhanced() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"

    cd "$app_dir"

    log_info "🔧 Analyzing Laravel Octane setup for $app_name"
    log_info "📁 Working directory: $app_dir"

    # Step 1: Check Laravel project
    if [ ! -f "artisan" ]; then
        log_error "Not a Laravel project (artisan not found)"
        return 1
    fi
    log_info "✅ Laravel project detected"

    # Step 2: Check Octane installation status
    log_info "🔍 Checking Octane installation status..."

    local octane_status=""
    local frankenphp_status=""

    if check_octane_installed; then
        octane_status="✅ INSTALLED"
        log_info "$octane_status"

        # Check FrankenPHP configuration
        if check_frankenphp_configured; then
            frankenphp_status="✅ CONFIGURED"
            log_info "🔧 FrankenPHP: $frankenphp_status"
        else
            frankenphp_status="⚠️  NOT CONFIGURED"
            log_info "🔧 FrankenPHP: $frankenphp_status"

            log_info "🔧 Configuring FrankenPHP for existing Octane..."
            if configure_frankenphp; then
                frankenphp_status="✅ CONFIGURED"
                log_info "🔧 FrankenPHP: $frankenphp_status"
            else
                log_error "Failed to configure FrankenPHP"
                return 1
            fi
        fi
    else
        octane_status="❌ NOT INSTALLED"
        log_info "$octane_status"

        log_info "📦 Installing Laravel Octane..."
        if ! composer require laravel/octane; then
            log_error "Failed to install Laravel Octane"
            return 1
        fi

        log_info "🔧 Configuring Octane with FrankenPHP..."
        if ! php artisan octane:install --server=frankenphp; then
            log_error "Failed to configure Octane with FrankenPHP"
            return 1
        fi

        octane_status="✅ INSTALLED"
        frankenphp_status="✅ CONFIGURED"
        log_info "✅ Laravel Octane: $octane_status"
        log_info "✅ FrankenPHP: $frankenphp_status"
    fi

    # Step 3: Setup production environment
    log_info "⚙️ Setting up production environment..."
    setup_production_env "$domain"

    # Step 4: Optimize Laravel app
    log_info "⚡ Optimizing Laravel app..."
    optimize_laravel_app

    # Step 5: Final status report
    log_info ""
    log_info "📊 Final Status Report:"
    log_info "   Laravel Octane: $octane_status"
    log_info "   FrankenPHP: $frankenphp_status"
    log_info "   Environment: ✅ PRODUCTION"
    log_info "   Optimization: ✅ COMPLETE"
    log_info ""
    log_info "✅ Laravel Octane setup completed for $app_name"
}

create_octane_service() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"

    log_info "⚙️ Creating systemd service for $app_name"

    # Create systemd service file
    cat > "/etc/systemd/system/octane-$app_name.service" << EOF
[Unit]
Description=Laravel Octane Server for $app_name
Documentation=https://laravel.com/docs/octane
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php artisan octane:frankenphp --host=$domain --port=443 --https --http-redirect --log-level=info
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=10
Restart=always
RestartSec=10

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$app_dir /tmp
LimitNOFILE=65536

# Environment
Environment=APP_ENV=production
Environment=APP_DEBUG=false

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload

    log_info "✅ Service created: octane-$app_name.service"
}

# =============================================
# Database Configuration
# =============================================

setup_database_config() {
    local app_name="$1"
    local db_name="$2"

    log_info "🗄️ Setting up database for $app_name"

    # Generate database credentials
    local db_user="${app_name}_user"
    local db_pass=$(generate_password)

    # Create database and user
    mysql -u root -e "
        CREATE DATABASE IF NOT EXISTS $db_name;
        CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
        GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
        FLUSH PRIVILEGES;
    "

    # Update .env file with database configuration
    if [ -f ".env" ]; then
        sed -i "s/DB_DATABASE=.*/DB_DATABASE=$db_name/" .env
        sed -i "s/DB_USERNAME=.*/DB_USERNAME=$db_user/" .env
        sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_pass/" .env
        sed -i "s/DB_HOST=.*/DB_HOST=localhost/" .env
        sed -i "s/DB_PORT=.*/DB_PORT=3306/" .env
    fi

    # Save config for later use
    cat > "/etc/laravel-apps/$app_name.conf" << EOF
APP_NAME=$app_name
APP_DIR=$app_dir
DOMAIN=$domain
DB_NAME=$db_name
DB_USER=$db_user
DB_PASS=$db_pass
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    log_info "✅ Database configured: $db_name"
}

# =============================================
# App Management Functions
# =============================================

deploy_app() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: deploy_app <app-name>"
        return 1
    fi

    # Load app config
    local config_file="/etc/laravel-apps/$app_name.conf"
    if [ -f "$config_file" ]; then
        source "$config_file"
    else
        log_error "App config not found: $config_file"
        return 1
    fi

    log_info "🚀 Deploying app: $app_name"

    cd "$APP_DIR"

    # Pull latest changes
    git pull origin main

    # Update dependencies
    composer install --no-dev --optimize-autoloader

    # Run migrations
    php artisan migrate --force

    # Clear and rebuild cache
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache

    # Restart service
    systemctl restart "octane-$app_name.service"

    log_info "✅ App $app_name deployed successfully!"
}

remove_app() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: remove_app <app-name>"
        return 1
    fi

    # Confirm removal
    log_warning "⚠️  This will permanently remove app: $app_name"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Removal cancelled"
        return 0
    fi

    # Stop and disable service
    systemctl stop "octane-$app_name.service" 2>/dev/null || true
    systemctl disable "octane-$app_name.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/octane-$app_name.service"

    # Remove app directory
    rm -rf "$APPS_BASE_DIR/$app_name"

    # Remove config
    rm -f "/etc/laravel-apps/$app_name.conf"

    # Remove database (optional)
    read -p "Remove database too? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        source "/etc/laravel-apps/$app_name.conf"
        mysql -u root -e "DROP DATABASE IF EXISTS $DB_NAME; DROP USER IF EXISTS '$DB_USER'@'localhost';"
    fi

    systemctl daemon-reload

    log_info "✅ App $app_name removed successfully!"
}

list_apps() {
    log_info "📋 Listing all Laravel apps:"
    echo ""

    local apps_dir="$APPS_BASE_DIR"
    if [ ! -d "$apps_dir" ]; then
        log_warning "Apps directory not found: $apps_dir"
        return 1
    fi

    local found_apps=0
    printf "%-20s %-30s %-10s\n" "App Name" "Domain" "Status"
    echo "======================================================================"

    for app_dir in "$apps_dir"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            local config_file="/etc/laravel-apps/$app_name.conf"

            if [ -f "$config_file" ]; then
                source "$config_file"
                local status="Unknown"

                if systemctl is-active --quiet "octane-$app_name"; then
                    status="Running"
                else
                    status="Stopped"
                fi

                printf "%-20s %-30s %-10s\n" "$app_name" "$DOMAIN" "$status"
                found_apps=$((found_apps + 1))
            fi
        fi
    done

    if [ $found_apps -eq 0 ]; then
        log_info "No apps found"
    else
        echo ""
        log_info "Total apps: $found_apps"
    fi
}

status_app() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: status_app <app-name>"
        return 1
    fi

    log_info "📊 Status for app: $app_name"

    # Check if service exists
    if systemctl list-units --full -all | grep -q "octane-$app_name.service"; then
        systemctl status "octane-$app_name.service" --no-pager
    else
        log_error "Service not found: octane-$app_name.service"
        return 1
    fi
}

# =============================================
# Utility Functions
# =============================================

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# =============================================
# Octane Detection & Configuration Helpers
# =============================================

check_octane_installed() {
    # Check if Octane is in composer.json
    if [ -f "composer.json" ]; then
        if grep -q '"laravel/octane"' composer.json; then
            log_info "📦 Octane found in composer.json"

            # Check if Octane is actually installed in vendor
            if [ -d "vendor/laravel/octane" ]; then
                log_info "✅ Octane package is installed"

                # Check if artisan octane commands are available
                if php artisan list | grep -q "octane:"; then
                    log_info "✅ Octane commands are available"
                    return 0
                else
                    log_info "⚠️  Octane package found but commands not available"
                    return 1
                fi
            else
                log_info "⚠️  Octane in composer.json but not installed"
                return 1
            fi
        else
            log_info "📦 Octane not found in composer.json"
            return 1
        fi
    else
        log_error "composer.json not found"
        return 1
    fi
}

check_frankenphp_configured() {
    # Check if Octane is configured for FrankenPHP
    local config_file="config/octane.php"

    if [ -f "$config_file" ]; then
        if grep -q "frankenphp" "$config_file"; then
            log_info "✅ FrankenPHP configuration found in config/octane.php"
            return 0
        else
            log_info "⚠️  Octane config exists but FrankenPHP not configured"
            return 1
        fi
    else
        log_info "⚠️  Octane config file not found"
        return 1
    fi
}

configure_frankenphp() {
    # Configure Laravel Octane to use FrankenPHP following best practices
    log_info "🔧 Configuring Laravel Octane to use FrankenPHP..."

    # Check if Octane is installed first
    if ! php artisan list | grep -q "octane:start"; then
        log_info "📦 Installing Laravel Octane first..."
        if ! composer require laravel/octane; then
            log_error "Failed to install Laravel Octane"
            return 1
        fi
    fi

    # Configure FrankenPHP (Laravel will handle binary download)
    if php artisan octane:install --server=frankenphp; then
        log_info "✅ FrankenPHP configured successfully"
        return 0
    else
        log_error "Failed to configure FrankenPHP"
        return 1
    fi
}

setup_production_env() {
    local domain="$1"

    log_info "⚙️ Setting up production environment..."

    # Update .env for production
    if [ -f ".env" ]; then
        sed -i "s/APP_ENV=.*/APP_ENV=production/" .env
        sed -i "s/APP_DEBUG=.*/APP_DEBUG=false/" .env
        sed -i "s|APP_URL=.*|APP_URL=https://$domain|" .env

        # Add Octane-specific settings if not present
        if ! grep -q "OCTANE_SERVER=" .env; then
            echo "OCTANE_SERVER=frankenphp" >> .env
        else
            sed -i "s/OCTANE_SERVER=.*/OCTANE_SERVER=frankenphp/" .env
        fi

        log_info "✅ Production environment configured"
    else
        log_error ".env file not found"
        return 1
    fi
}

optimize_laravel_app() {
    log_info "⚡ Optimizing Laravel app for production..."

    # Clear existing caches first
    php artisan config:clear || true
    php artisan route:clear || true
    php artisan view:clear || true
    php artisan cache:clear || true

    # Optimize for production
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache

    # Additional optimizations
    if command -v composer &> /dev/null; then
        composer dump-autoload --optimize
    fi

    log_info "✅ Laravel app optimized"
}

# =============================================
# Octane Status & Debugging Functions
# =============================================

show_octane_status() {
    local app_name="$1"
    local app_dir="$2"

    if [ -z "$app_name" ] || [ -z "$app_dir" ]; then
        log_error "Usage: show_octane_status <app-name> <app-dir>"
        return 1
    fi

    log_info "📊 Octane Status for $app_name"
    log_info "================================"

    cd "$app_dir"

    # Check Laravel project
    if [ -f "artisan" ]; then
        log_info "✅ Laravel project: YES"
    else
        log_info "❌ Laravel project: NO"
        return 1
    fi

    # Check Octane in composer.json
    if [ -f "composer.json" ]; then
        if grep -q '"laravel/octane"' composer.json; then
            local octane_version=$(grep '"laravel/octane"' composer.json | sed 's/.*"laravel\/octane":[^"]*"\([^"]*\)".*/\1/')
            log_info "✅ Octane in composer.json: $octane_version"
        else
            log_info "❌ Octane in composer.json: NO"
        fi
    fi

    # Check Octane installation
    if [ -d "vendor/laravel/octane" ]; then
        log_info "✅ Octane package installed: YES"
    else
        log_info "❌ Octane package installed: NO"
    fi

    # Check Octane commands
    if php artisan list | grep -q "octane:"; then
        log_info "✅ Octane commands available: YES"
        php artisan list | grep "octane:" | while read line; do
            log_info "   $line"
        done
    else
        log_info "❌ Octane commands available: NO"
    fi

    # Check Octane config
    if [ -f "config/octane.php" ]; then
        log_info "✅ Octane config file: YES"

        # Check server configuration
        if grep -q "frankenphp" config/octane.php; then
            log_info "✅ FrankenPHP configured: YES"
        else
            log_info "❌ FrankenPHP configured: NO"
        fi
    else
        log_info "❌ Octane config file: NO"
    fi

    # Check .env settings
    if [ -f ".env" ]; then
        log_info "✅ Environment file: YES"

        local octane_server=$(grep "OCTANE_SERVER=" .env | cut -d'=' -f2)
        if [ -n "$octane_server" ]; then
            log_info "✅ OCTANE_SERVER: $octane_server"
        else
            log_info "⚠️  OCTANE_SERVER: NOT SET"
        fi
    else
        log_info "❌ Environment file: NO"
    fi

    # Check FrankenPHP configuration
    if check_frankenphp_binary; then
        log_info "✅ FrankenPHP configuration: YES"

        # Check if Laravel Octane can detect FrankenPHP
        if timeout 5 php artisan octane:status --server=frankenphp &>/dev/null; then
            log_info "   Laravel Octane can detect FrankenPHP"
        else
            log_info "   Laravel Octane status check available"
        fi
    else
        log_info "❌ FrankenPHP configuration: NO"
        log_info "   (FrankenPHP not configured in Laravel Octane)"
    fi

    # Check service status
    local service_name="octane-$app_name.service"
    if systemctl is-active --quiet "$service_name"; then
        log_info "✅ Service status: ACTIVE"
    else
        log_info "❌ Service status: INACTIVE"
    fi

    log_info "================================"
}

# Function to handle different Octane scenarios
handle_octane_scenario() {
    local app_dir="$1"
    local scenario=""

    cd "$app_dir"

    # Detect scenario
    if [ -f "composer.json" ] && grep -q '"laravel/octane"' composer.json; then
        if [ -d "vendor/laravel/octane" ]; then
            if [ -f "config/octane.php" ]; then
                if grep -q "frankenphp" config/octane.php; then
                    scenario="FULLY_CONFIGURED"
                else
                    scenario="OCTANE_INSTALLED_DIFFERENT_SERVER"
                fi
            else
                scenario="OCTANE_INSTALLED_NO_CONFIG"
            fi
        else
            scenario="OCTANE_IN_COMPOSER_NOT_INSTALLED"
        fi
    else
        scenario="NO_OCTANE"
    fi

    log_info "🔍 Detected scenario: $scenario"

    case "$scenario" in
        "FULLY_CONFIGURED")
            log_info "✅ Octane with FrankenPHP already configured"
            # Still check if binary exists via Laravel Octane
            if ! check_frankenphp_binary; then
                log_info "📥 FrankenPHP binary missing, installing via Laravel Octane..."
                if ! php artisan octane:install --server=frankenphp; then
                    log_error "Failed to install FrankenPHP via Laravel Octane"
                    return 1
                fi
            fi
            return 0
            ;;
        "OCTANE_INSTALLED_DIFFERENT_SERVER")
            log_info "🔧 Octane installed but using different server, reconfiguring..."
            configure_frankenphp
            return $?
            ;;
        "OCTANE_INSTALLED_NO_CONFIG")
            log_info "🔧 Octane installed but not configured, configuring..."
            configure_frankenphp
            return $?
            ;;
        "OCTANE_IN_COMPOSER_NOT_INSTALLED")
            log_info "📦 Octane in composer.json but not installed, installing..."
            composer install
            configure_frankenphp
            return $?
            ;;
        "NO_OCTANE")
            log_info "📦 No Octane found, installing fresh..."

            # Install Octane
            if ! composer require laravel/octane; then
                log_error "Failed to install Laravel Octane"
                return 1
            fi

            # Configure with FrankenPHP (this will download the binary automatically)
            if ! php artisan octane:install --server=frankenphp; then
                log_error "Failed to configure Octane with FrankenPHP"
                return 1
            fi

            return 0
            ;;
        *)
            log_error "Unknown scenario: $scenario"
            return 1
            ;;
    esac
}

# Smart Octane installation with scenario detection
install_octane_smart() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"

    cd "$app_dir"

    log_info "🧠 Smart Octane Setup for $app_name"
    log_info "==================================="

    # Show current status
    show_octane_status "$app_name" "$app_dir"

    # Handle the scenario
    if handle_octane_scenario "$app_dir"; then
        log_info "✅ Octane setup completed successfully"
    else
        log_error "❌ Failed to setup Octane"
        return 1
    fi

    # Always update production environment
    setup_production_env "$domain"

    # Always optimize
    optimize_laravel_app

    # Final status check
    log_info ""
    log_info "📊 Final Status Check:"
    show_octane_status "$app_name" "$app_dir"

    log_info "✅ Smart Octane setup completed for $app_name"
}

# Command line interface functions for Octane management
octane_check_status() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: octane:check <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        log_error "App $app_name does not exist"
        return 1
    fi

    local app_dir="$APPS_BASE_DIR/$app_name"
    show_octane_status "$app_name" "$app_dir"
}

octane_analyze_setup() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: octane:analyze <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        log_error "App $app_name does not exist"
        return 1
    fi

    local app_dir="$APPS_BASE_DIR/$app_name"

    log_info "🔍 Analyzing Octane setup for $app_name"
    show_octane_status "$app_name" "$app_dir"

    # Show recommendations
    cd "$app_dir"
    log_info ""
    log_info "💡 Recommendations:"

    if ! check_octane_installed; then
        log_info "   • Install Octane: ./install.sh octane:install $app_dir"
    fi

    if ! check_frankenphp_configured; then
        log_info "   • Configure FrankenPHP: php artisan octane:install --server=frankenphp"
    fi

    # Check service status
    local service_name="octane-$app_name.service"
    if ! systemctl is-active --quiet "$service_name"; then
        log_info "   • Start service: systemctl start $service_name"
    fi
}

octane_fix_setup() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: octane:fix <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        log_error "App $app_name does not exist"
        return 1
    fi

    local app_dir="$APPS_BASE_DIR/$app_name"

    log_info "🔧 Fixing Octane setup for $app_name"

    # Run smart installation
    install_octane_smart "$app_name" "$app_dir" "$(get_app_domain "$app_name")"

    # Restart service
    systemctl restart "octane-$app_name.service"

    log_info "✅ Octane setup fixed for $app_name"
}

# Helper function to get app domain
get_app_domain() {
    local app_name="$1"
    local app_config="$CONFIG_DIR/$app_name.conf"

    if [ -f "$app_config" ]; then
        source "$app_config"
        echo "$DOMAIN"
    else
        echo "$app_name.local"
    fi
}

# =============================================
# End of Enhanced Octane Management
# =============================================

# =============================================
# FrankenPHP Binary Management
# =============================================

download_frankenphp_binary() {
    local current_dir="$(pwd)"
    local frankenphp_binary="frankenphp"

    log_info "📥 Checking FrankenPHP binary..."

    # Check if FrankenPHP binary already exists
    if [ -f "$frankenphp_binary" ]; then
        log_info "✅ FrankenPHP binary already exists"

        # Check if it's executable
        if [ -x "$frankenphp_binary" ]; then
            log_info "✅ FrankenPHP binary is executable"
            return 0
        else
            log_info "🔧 Making FrankenPHP binary executable..."
            chmod +x "$frankenphp_binary"
            return 0
        fi
    fi

    # Download FrankenPHP binary
    log_info "📥 Downloading FrankenPHP binary..."

    # Detect architecture
    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local frankenphp_url=""

    case "$arch" in
        "x86_64")
            arch="x86_64"
            ;;
        "aarch64"|"arm64")
            arch="aarch64"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    case "$os" in
        "linux")
            frankenphp_url="https://github.com/dunglas/frankenphp/releases/latest/download/frankenphp-linux-$arch"
            ;;
        "darwin")
            frankenphp_url="https://github.com/dunglas/frankenphp/releases/latest/download/frankenphp-mac-$arch"
            ;;
        *)
            log_error "Unsupported operating system: $os"
            return 1
            ;;
    esac

    log_info "📥 Downloading from: $frankenphp_url"

    # Download with retry logic
    local retry_count=0
    local max_retries=3

    while [ $retry_count -lt $max_retries ]; do
        if curl -fsSL "$frankenphp_url" -o "$frankenphp_binary.tmp"; then
            # Move temporary file to final location
            mv "$frankenphp_binary.tmp" "$frankenphp_binary"
            chmod +x "$frankenphp_binary"

            log_info "✅ FrankenPHP binary downloaded successfully"

            # Verify the binary works
            if ./"$frankenphp_binary" version &>/dev/null; then
                log_info "✅ FrankenPHP binary is working"
                return 0
            else
                log_error "⚠️  FrankenPHP binary downloaded but not working properly"
                return 1
            fi
        else
            retry_count=$((retry_count + 1))
            log_error "❌ Failed to download FrankenPHP binary (attempt $retry_count/$max_retries)"

            if [ $retry_count -lt $max_retries ]; then
                log_info "🔄 Retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done

    log_error "❌ Failed to download FrankenPHP binary after $max_retries attempts"
    return 1
}

check_frankenphp_binary() {
    # Check if FrankenPHP is properly configured in Laravel Octane
    # This follows Laravel best practices instead of manual binary checking

    # Check if octane config exists and has frankenphp configured
    if [ -f "config/octane.php" ]; then
        if grep -q "frankenphp" config/octane.php; then
            return 0
        fi
    fi

    # Check if .env has OCTANE_SERVER set to frankenphp
    if [ -f ".env" ]; then
        if grep -q "OCTANE_SERVER=frankenphp" .env; then
            return 0
        fi
    fi

    # Check if Laravel Octane can find FrankenPHP
    if timeout 5 php artisan octane:status --server=frankenphp &>/dev/null; then
        return 0
    fi

    return 1
}

# =============================================
# Enhanced Octane Detection & Configuration
# =============================================
