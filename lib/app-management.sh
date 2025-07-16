#!/bin/bash

# =============================================
# App Management Library (Simplified)
# Using Laravel Octane + FrankenPHP Best Practices
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${APP_MANAGEMENT_LOADED:-}" ]; then
    return 0
fi
export APP_MANAGEMENT_LOADED=1

# =============================================
# Simple Laravel Octane + FrankenPHP Installation
# =============================================

install_app() {
    local app_name="$1"
    local domain="$2"
    local github_repo="${3:-}"
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

    # Save app configuration
    save_app_config "$app_name" "$domain" "$app_dir" "$db_name"

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

    log_info "🏗️ Setting up Laravel application: $app_name"

    # Create app directory with proper permissions from the start
    mkdir -p "$app_dir"
    
    # Clone or create Laravel app
    if [ -n "$github_repo" ]; then
        log_info "📥 Cloning from GitHub: $github_repo"
        
        # Clone as root first, then fix permissions
        if ! git clone "$github_repo" "$app_dir"; then
            log_error "Failed to clone repository: $github_repo"
            return 1
        fi
        
        # Set ownership to www-data immediately after clone
        chown -R www-data:www-data "$app_dir"
        
        # Navigate to directory
        cd "$app_dir"
        
        # Install dependencies as www-data
        log_info "📦 Installing Composer dependencies..."
        sudo -u www-data composer install --no-dev --optimize-autoloader
        
    else
        log_info "📁 Creating fresh Laravel app with composer"
        
        # Ensure APPS_BASE_DIR is defined
        if [ -z "$APPS_BASE_DIR" ]; then
            APPS_BASE_DIR="/opt/laravel-apps"
        fi
        
        # Create parent directory if it doesn't exist
        mkdir -p "$APPS_BASE_DIR"
        
        # Set proper ownership for the base directory
        chown -R www-data:www-data "$APPS_BASE_DIR"
        
        # Create Laravel project as www-data user with absolute path
        cd "$APPS_BASE_DIR"
        
        # Create the project in the base directory
        if ! sudo -u www-data composer create-project laravel/laravel "$app_name"; then
            log_error "Failed to create Laravel project"
            return 1
        fi
        
        # Navigate to the created directory
        cd "$app_name"
    fi

    # Setup Laravel environment (as www-data)
    if [ -f "composer.json" ]; then
        log_info "⚙️ Configuring Laravel environment..."
        
        # Setup environment file
        if [ -f ".env.example" ] && [ ! -f ".env" ]; then
            sudo -u www-data cp .env.example .env
        fi

        # Generate app key
        sudo -u www-data php artisan key:generate --force

        # Setup database configuration
        setup_database_config "$app_name" "$db_name"

        # Create necessary directories with proper permissions
        sudo -u www-data mkdir -p storage/logs storage/framework/{cache,sessions,views}
        sudo -u www-data mkdir -p bootstrap/cache
        
        # Run migrations
        log_info "🗄️ Running database migrations..."
        sudo -u www-data php artisan migrate --force
        
        # Cache configuration for better performance
        log_info "⚡ Caching configuration..."
        sudo -u www-data php artisan config:cache
        sudo -u www-data php artisan route:cache
        sudo -u www-data php artisan view:cache
        
    else
        log_error "Invalid Laravel project (composer.json not found)"
        return 1
    fi

    # Set final permissions properly
    log_info "🔧 Setting proper file permissions..."
    
    # Set directory ownership
    chown -R www-data:www-data "$app_dir"
    
    # Set directory permissions
    find "$app_dir" -type d -exec chmod 755 {} \;
    find "$app_dir" -type f -exec chmod 644 {} \;
    
    # Set executable permissions for artisan
    chmod +x "$app_dir/artisan"
    
    # Set proper permissions for storage and bootstrap/cache
    chmod -R 775 "$app_dir/storage"
    chmod -R 775 "$app_dir/bootstrap/cache"
    
    # Secure sensitive files
    chmod 600 "$app_dir/.env"
    
    log_info "✅ Laravel application setup completed"
}

install_octane() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"

    cd "$app_dir"

    log_info "🔧 Setting up Laravel Octane with FrankenPHP for $app_name"

    # Check if Octane is already installed
    if check_octane_installed; then
        log_info "✅ Laravel Octane already installed"

        # Check if FrankenPHP is configured
        if check_frankenphp_configured; then
            log_info "✅ FrankenPHP already configured"
        else
            log_info "🔧 Configuring FrankenPHP..."
            configure_frankenphp_proper "$app_name" "$domain"
        fi
    else
        log_info "📦 Installing Laravel Octane..."

        # Install Octane as www-data user
        if ! sudo -u www-data composer require laravel/octane; then
            log_error "Failed to install Laravel Octane"
            return 1
        fi

        # Install with FrankenPHP
        log_info "🔧 Configuring Octane with FrankenPHP..."
        if ! sudo -u www-data php artisan octane:install --server=frankenphp; then
            log_error "Failed to configure Octane with FrankenPHP"
            return 1
        fi

        log_info "✅ Laravel Octane installed successfully"
    fi

    # Setup production environment
    setup_production_env "$domain"

    # Setup FrankenPHP-specific configuration
    setup_frankenphp_config "$app_name" "$domain"

    # Create TLS storage directory
    setup_tls_storage "$app_name"

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

# Smart install with automatic detection and optimization
install_octane_smart() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"

    cd "$app_dir"

    log_info "🧠 Smart Laravel Octane installation for $app_name"
    log_info "📁 Working directory: $app_dir"

    # Step 1: Detect Laravel version and current setup
    local laravel_version=""
    if [ -f "composer.json" ]; then
        laravel_version=$(grep -o '"laravel/framework": "[^"]*"' composer.json | sed 's/.*": "//' | sed 's/".*//')
        log_info "🔍 Laravel version detected: $laravel_version"
    fi

    # Step 2: Check if Octane is already installed
    if check_octane_installed; then
        log_info "✅ Laravel Octane already installed"
        
        # Check if FrankenPHP is properly configured
        if check_frankenphp_configured; then
            log_info "✅ FrankenPHP already configured"
        else
            log_info "🔧 Configuring FrankenPHP for existing Octane..."
            configure_frankenphp_proper "$app_name" "$domain"
        fi
    else
        log_info "📦 Installing Laravel Octane with FrankenPHP..."
        
        # Install Octane as www-data user
        if ! sudo -u www-data composer require laravel/octane; then
            log_error "Failed to install Laravel Octane"
            return 1
        fi

        # Configure Octane with FrankenPHP
        log_info "🔧 Configuring Octane with FrankenPHP..."
        if ! sudo -u www-data php artisan octane:install --server=frankenphp; then
            log_error "Failed to configure Octane with FrankenPHP"
            return 1
        fi
        
        log_info "✅ Laravel Octane with FrankenPHP installed successfully"
    fi

    # Step 3: Smart configuration based on environment
    log_info "🔧 Applying smart configurations..."
    
    # Setup production environment
    setup_production_env "$domain"
    
    # Setup FrankenPHP-specific configuration
    setup_frankenphp_config "$app_name" "$domain"
    
    # Create TLS storage directory
    setup_tls_storage "$app_name"
    
    # Optimize Laravel app
    optimize_laravel_app
    
    # Step 4: Performance optimization based on system resources
    optimize_for_system_resources "$app_name"
    
    log_info "✅ Smart Laravel Octane installation completed for $app_name"
}

# Performance optimization based on system resources and existing apps
optimize_for_system_resources() {
    local app_name="$1"
    
    log_info "⚡ Optimizing for system resources with multi-app awareness..."
    
    # Get system resources
    local total_memory=$(free -m | awk 'NR==2{print $2}')
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    local used_memory=$(free -m | awk 'NR==2{print $3}')
    local cpu_cores=$(nproc)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    # Calculate memory usage percentage
    local memory_usage_percent=$(echo "scale=2; $used_memory * 100 / $total_memory" | bc -l 2>/dev/null || echo "0")
    
    # Count existing running apps
    local running_apps=$(count_running_apps)
    local total_apps_after_install=$((running_apps + 1))
    
    log_info "📊 System resources: ${total_memory}MB RAM, ${cpu_cores} CPU cores"
    log_info "📊 Memory usage: ${memory_usage_percent}%, Load average: ${load_avg}"
    log_info "📊 Running apps: ${running_apps}, Total after install: ${total_apps_after_install}"
    
    # Calculate safe resource allocation for multi-app
    local safe_memory_per_app=$(calculate_safe_memory_per_app "$total_memory" "$total_apps_after_install")
    local safe_workers_per_app=$(calculate_safe_workers_per_app "$cpu_cores" "$total_apps_after_install")
    
    # Check if we can safely install another app
    if ! check_resource_availability "$total_memory" "$cpu_cores" "$total_apps_after_install"; then
        log_error "⚠️  RESOURCE WARNING: Installing another app may cause performance issues!"
        log_error "   Current apps: $running_apps"
        log_error "   Recommended max apps for this server: $(get_recommended_max_apps "$total_memory" "$cpu_cores")"
        
        read -p "Do you want to continue with reduced performance? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled for safety"
            return 1
        fi
    fi
    
    # Calculate workers and max_requests based on available resources
    local workers=$safe_workers_per_app
    local max_requests=$(calculate_max_requests "$safe_memory_per_app")
    
    # Apply minimum and maximum limits
    [ $workers -lt 1 ] && workers=1
    [ $workers -gt 8 ] && workers=8
    [ $max_requests -lt 100 ] && max_requests=100
    [ $max_requests -gt 3000 ] && max_requests=3000
    
    log_info "🎯 Multi-app optimized settings:"
    log_info "   Workers: ${workers} (safe allocation for ${total_apps_after_install} apps)"
    log_info "   Max requests: ${max_requests}"
    log_info "   Estimated memory per app: ${safe_memory_per_app}MB"
    log_info "   Estimated total memory usage: $((safe_memory_per_app * total_apps_after_install))MB"
    
    # Update .env with optimized settings
    if [ -f ".env" ]; then
        # Remove existing Octane settings
        sed -i '/^OCTANE_/d' .env
        
        # Add multi-app optimized settings
        cat >> .env << EOF

# Multi-App Optimized FrankenPHP Settings
OCTANE_SERVER=frankenphp
OCTANE_WORKERS=$workers
OCTANE_MAX_REQUESTS=$max_requests
OCTANE_LOG_LEVEL=info

# Performance Settings
OCTANE_TICK_INTERVAL=1000
OCTANE_TASK_WORKERS=auto
OCTANE_WATCH=false

# Multi-app metadata
OCTANE_MULTIAPP_TOTAL_APPS=$total_apps_after_install
OCTANE_MULTIAPP_MEMORY_ALLOCATION=${safe_memory_per_app}MB
EOF
        
        # Set proper ownership
        chown www-data:www-data .env
        chmod 600 .env
    fi
    
    # Save resource allocation info
    save_resource_allocation "$app_name" "$workers" "$max_requests" "$safe_memory_per_app" "$total_apps_after_install"
    
    log_info "✅ Multi-app performance optimization completed"
}

configure_frankenphp_proper() {
    local app_name="$1"
    local domain="$2"
    
    log_info "🔧 Configuring FrankenPHP properly for $app_name"
    
    # Update config/octane.php for FrankenPHP
    if [ -f "config/octane.php" ]; then
        log_info "⚙️ Updating Octane configuration..."
        
        # Create proper FrankenPHP configuration
        sudo -u www-data php artisan octane:install --server=frankenphp
        
        # Update .env for FrankenPHP
        update_env_for_frankenphp "$domain"
    fi
}

setup_frankenphp_config() {
    local app_name="$1"
    local domain="$2"
    
    log_info "📝 Setting up FrankenPHP configuration for $app_name"
    
    # Create Caddyfile for FrankenPHP
    create_caddyfile "$app_name" "$domain"
    
    # Update .env for FrankenPHP settings
    update_env_for_frankenphp "$domain"
}

create_caddyfile() {
    local app_name="$1"
    local domain="$2"
    
    log_info "📝 Creating Caddyfile for $app_name"
    
    # Create Caddyfile with proper configuration
    cat > "Caddyfile" << EOF
{
    # Global options
    auto_https on
    admin off
    
    # Logging
    log {
        level INFO
        output file /var/log/frankenphp/$app_name.log
    }
}

# Main site
$domain {
    # Document root
    root * public
    
    # Security headers
    header {
        -Server
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
    }
    
    # Enable compression
    encode gzip
    
    # PHP handling
    php_fastcgi unix//run/php/php8.3-fpm.sock
    
    # Laravel-specific rules
    try_files {path} {path}/ /index.php?{query}
    
    # Static assets caching
    @static {
        path *.css *.js *.ico *.png *.jpg *.jpeg *.gif *.svg *.woff *.woff2 *.ttf *.otf
    }
    header @static Cache-Control "public, max-age=31536000"
    
    # Deny sensitive files
    respond /storage/app/private/* 404
    respond /.env* 404
    respond /composer.* 404
    respond /artisan 404
}

# Redirect www to non-www
www.$domain {
    redir https://$domain{uri} permanent
}
EOF
    
    # Set proper ownership
    chown www-data:www-data "Caddyfile"
    chmod 644 "Caddyfile"
    
    log_info "✅ Caddyfile created"
}

update_env_for_frankenphp() {
    local domain="$1"
    
    log_info "⚙️ Updating .env for FrankenPHP"
    
    # Update .env file with FrankenPHP settings
    if [ -f ".env" ]; then
        # Remove existing Octane settings
        sed -i '/OCTANE_/d' .env
        
        # Add FrankenPHP settings
        cat >> .env << EOF

# FrankenPHP Settings
OCTANE_SERVER=frankenphp
OCTANE_HOST=$domain
OCTANE_PORT=443
OCTANE_HTTPS=true
OCTANE_HTTP_REDIRECT=true
OCTANE_WORKERS=4
OCTANE_MAX_REQUESTS=1000
OCTANE_LOG_LEVEL=info
EOF
        
        # Set proper ownership
        chown www-data:www-data .env
        chmod 600 .env
    fi
}

setup_tls_storage() {
    local app_name="$1"
    
    log_info "🔐 Setting up TLS storage for $app_name"
    
    # Create TLS storage directory
    local tls_storage_dir="/var/lib/frankenphp/$app_name"
    mkdir -p "$tls_storage_dir"
    mkdir -p "$tls_storage_dir/certificates"
    
    # Set proper ownership and permissions
    chown -R www-data:www-data "$tls_storage_dir"
    chmod 755 "$tls_storage_dir"
    chmod 700 "$tls_storage_dir/certificates"
    
    log_info "✅ TLS storage directory created"
}

optimize_laravel_app() {
    log_info "⚡ Optimizing Laravel application..."
    
    # Clear all caches first
    sudo -u www-data php artisan cache:clear
    sudo -u www-data php artisan config:clear
    sudo -u www-data php artisan route:clear
    sudo -u www-data php artisan view:clear
    
    # Optimize for production
    sudo -u www-data php artisan config:cache
    sudo -u www-data php artisan route:cache
    sudo -u www-data php artisan view:cache
    
    # Optimize Composer autoloader
    sudo -u www-data composer dump-autoload --optimize
    
    log_info "✅ Laravel optimization completed"
}

setup_production_env() {
    local domain="$1"
    
    log_info "🔧 Setting up production environment"
    
    if [ -f ".env" ]; then
        # Set production values
        sed -i 's/APP_ENV=.*/APP_ENV=production/' .env
        sed -i 's/APP_DEBUG=.*/APP_DEBUG=false/' .env
        sed -i "s/APP_URL=.*/APP_URL=https:\/\/$domain/" .env
        
        # Set proper ownership
        chown www-data:www-data .env
        chmod 600 .env
        
        log_info "✅ Production environment configured"
    fi
}

create_octane_service() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"
    
    # If called with just app_name, get other parameters from config
    if [ -z "$app_dir" ]; then
        app_dir="$APPS_BASE_DIR/$app_name"
    fi
    
    if [ -z "$domain" ]; then
        if [ -f "/etc/laravel-apps/$app_name.conf" ]; then
            domain=$(grep "DOMAIN=" "/etc/laravel-apps/$app_name.conf" | cut -d'=' -f2 | tr -d '"')
        fi
    fi
    
    if [ -z "$domain" ]; then
        log_error "Domain not specified and not found in config"
        return 1
    fi
    
    log_info "🔧 Creating systemd service for $app_name"
    
    # Create service file
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

# Capabilities for binding to privileged ports
AmbientCapabilities=CAP_NET_BIND_SERVICE

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$app_dir /tmp /var/lib/frankenphp/$app_name /var/log/frankenphp
LimitNOFILE=65536

# Environment
Environment=APP_ENV=production
Environment=APP_DEBUG=false
Environment=XDG_DATA_HOME=/var/lib/frankenphp/$app_name

[Install]
WantedBy=multi-user.target
EOF
    
    # Set proper ownership
    chmod 644 "/etc/systemd/system/octane-$app_name.service"
    
    # Allow www-data to bind to privileged ports
    if command -v setcap >/dev/null 2>&1; then
        # Find actual PHP binary (not symlink)
        local php_binary=$(readlink -f /usr/bin/php)
        if [ -f "$php_binary" ]; then
            setcap 'cap_net_bind_service=+ep' "$php_binary"
        fi
    fi
    
    log_info "✅ Systemd service created"
}

# =============================================
# Database Configuration
# =============================================

setup_database_config() {
    local app_name="$1"
    local db_name="$2"

    log_info "🗄️ Setting up database configuration for $app_name"

    # Create database if it doesn't exist
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS $db_name;" 2>/dev/null || true

    # Update .env with database settings
    if [ -f ".env" ]; then
        sed -i "s/DB_DATABASE=.*/DB_DATABASE=$db_name/" .env
        sed -i "s/DB_USERNAME=.*/DB_USERNAME=root/" .env
        sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=/" .env
        
        # Set proper ownership
        chown www-data:www-data .env
        chmod 600 .env
    fi

    log_info "✅ Database configuration completed"
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

    log_info "🗑️  Starting removal process for $app_name"

    # Step 1: Load database config BEFORE removing anything
    local db_name=""
    local db_user=""
    local db_pass=""
    local config_file="/etc/laravel-apps/$app_name.conf"

    if [ -f "$config_file" ]; then
        log_info "📖 Loading database configuration..."
        # Use separate shell to avoid variables pollution
        eval "$(grep -E '^(DB_NAME|DB_USER|DB_PASS)=' "$config_file" 2>/dev/null || true)"
        db_name="$DB_NAME"
        db_user="$DB_USER"
        db_pass="$DB_PASS"
    else
        log_warning "⚠️  Config file not found: $config_file"
        log_info "💡 Will attempt to derive database info from app name"
        db_name="${app_name}_db"
        db_user="${app_name}_user"
    fi

    # Step 2: Ask about database removal first
    local remove_database=false
    if [ -n "$db_name" ]; then
        read -p "Remove database '$db_name' too? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remove_database=true
        fi
    fi

    # Step 3: Stop and disable systemd service
    log_info "🛑 Stopping systemd service..."
    systemctl stop "octane-$app_name.service" 2>/dev/null || true
    systemctl disable "octane-$app_name.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/octane-$app_name.service"
    log_info "✅ Service stopped and removed"

    # Step 4: Remove database if requested
    if [ "$remove_database" = true ]; then
        log_info "🗄️  Removing database..."
        
        # Get MySQL root password using the database manager function
        local root_password=$(get_mysql_root_password)
        if [ $? -eq 0 ]; then
            local mysql_cmd
            if [ -n "$root_password" ]; then
                mysql_cmd="mysql -u root -p$root_password"
            else
                mysql_cmd="mysql -u root"
            fi

            # Remove database and user
            $mysql_cmd -e "DROP DATABASE IF EXISTS $db_name;" 2>/dev/null || log_warning "Could not drop database $db_name"
            $mysql_cmd -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null || log_warning "Could not drop user $db_user"
            $mysql_cmd -e "FLUSH PRIVILEGES;" 2>/dev/null || true

            log_info "✅ Database $db_name and user $db_user removed"
        else
            log_warning "⚠️  Could not connect to MySQL as root, skipping database removal"
        fi
    fi

    # Step 5: Remove app directory
    log_info "📁 Removing app directory..."
    local app_dir="$APPS_BASE_DIR/$app_name"
    if [ -d "$app_dir" ]; then
        rm -rf "$app_dir"
        log_info "✅ App directory removed: $app_dir"
    else
        log_warning "⚠️  App directory not found: $app_dir"
    fi

    # Step 6: Remove config file
    log_info "⚙️  Removing config file..."
    if [ -f "$config_file" ]; then
        rm -f "$config_file"
        log_info "✅ Config file removed: $config_file"
    else
        log_warning "⚠️  Config file not found: $config_file"
    fi

    # Step 7: Reload systemd daemon
    systemctl daemon-reload

    log_info "✅ App $app_name removed successfully!"
    log_info "📋 Removal summary:"
    log_info "   - Systemd service: removed"
    log_info "   - App directory: removed"
    log_info "   - Config file: removed"
    if [ "$remove_database" = true ]; then
        log_info "   - Database: removed"
    else
        log_info "   - Database: preserved"
    fi
}

remove_app_force() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: remove_app_force <app-name>"
        return 1
    fi

    # Confirm force removal
    log_warning "⚠️  FORCE REMOVAL: This will remove app $app_name even if configs are missing"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Force removal cancelled"
        return 0
    fi

    log_info "🗑️  Starting force removal process for $app_name"

    # Step 1: Stop and disable systemd service (force)
    log_info "🛑 Force stopping systemd service..."
    systemctl stop "octane-$app_name.service" 2>/dev/null || true
    systemctl disable "octane-$app_name.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/octane-$app_name.service"

    # Also try to kill any remaining processes
    pkill -f "octane.*$app_name" 2>/dev/null || true
    log_info "✅ Service force stopped"

    # Step 2: Remove app directory (force)
    log_info "📁 Force removing app directory..."
    local app_dir="$APPS_BASE_DIR/$app_name"
    if [ -d "$app_dir" ]; then
        rm -rf "$app_dir"
        log_info "✅ App directory removed: $app_dir"
    else
        log_warning "⚠️  App directory not found: $app_dir"
    fi

    # Step 3: Remove config file (force)
    log_info "⚙️  Force removing config file..."
    local config_file="/etc/laravel-apps/$app_name.conf"
    if [ -f "$config_file" ]; then
        rm -f "$config_file"
        log_info "✅ Config file removed: $config_file"
    else
        log_warning "⚠️  Config file not found: $config_file"
    fi

    # Step 4: Try to remove database with common naming conventions
    read -p "Attempt to remove database with common naming? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "🗄️  Attempting database removal with common naming..."
        
        local root_password=$(get_mysql_root_password)
        if [ $? -eq 0 ]; then
            local mysql_cmd
            if [ -n "$root_password" ]; then
                mysql_cmd="mysql -u root -p$root_password"
            else
                mysql_cmd="mysql -u root"
            fi

            # Try common database naming patterns
            local common_db_names=(
                "${app_name}_db"
                "${app_name}db"
                "$app_name"
            )

            local common_user_names=(
                "${app_name}_user"
                "${app_name}user"
                "$app_name"
            )

            for db_name in "${common_db_names[@]}"; do
                $mysql_cmd -e "DROP DATABASE IF EXISTS $db_name;" 2>/dev/null && log_info "✅ Dropped database: $db_name"
            done

            for user_name in "${common_user_names[@]}"; do
                $mysql_cmd -e "DROP USER IF EXISTS '$user_name'@'localhost';" 2>/dev/null && log_info "✅ Dropped user: $user_name"
            done

            $mysql_cmd -e "FLUSH PRIVILEGES;" 2>/dev/null || true
            log_info "✅ Database cleanup completed"
        else
            log_warning "⚠️  Could not connect to MySQL as root, skipping database removal"
        fi
    fi

    # Step 5: Clean up any remaining files
    log_info "🧹 Cleaning up remaining files..."

    # Remove log files
    rm -f "/var/log/frankenphp/$app_name.log" 2>/dev/null || true
    rm -f "/var/log/$app_name"* 2>/dev/null || true

    # Remove any backup files
    rm -f "/etc/laravel-apps/$app_name.conf.backup"* 2>/dev/null || true

    # Reload systemd daemon
    systemctl daemon-reload

    log_info "✅ Force removal of $app_name completed!"
    log_info "📋 Force removal summary:"
    log_info "   - Systemd service: force removed"
    log_info "   - App directory: force removed"
    log_info "   - Config file: force removed"
    log_info "   - Database: attempted cleanup"
    log_info "   - Log files: cleaned up"
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
        # Get service status without failing the script
        local service_status
        service_status=$(systemctl is-active "octane-$app_name.service" 2>/dev/null)
        
        echo "🔍 Service Status: $service_status"
        
        # Show detailed status
        systemctl status "octane-$app_name.service" --no-pager || true
        
        # If service is failing, show recent logs
        if [ "$service_status" = "failed" ] || [ "$service_status" = "activating" ]; then
            log_info "📋 Recent logs:"
            journalctl -u "octane-$app_name.service" -n 10 --no-pager || true
            
            # Check for common issues
            log_info "🔍 Checking for common issues..."
            check_service_issues "$app_name"
        fi
        
        return 0
    else
        log_error "Service not found: octane-$app_name.service"
        return 1
    fi
}

# =============================================
# Service Issue Detection and Fixing
# =============================================

check_service_issues() {
    local app_name="$1"
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    # Check for permission issues
    if journalctl -u "octane-$app_name.service" -n 50 --no-pager | grep -q "permission denied"; then
        log_error "🚫 Permission denied issue detected!"
        log_info "💡 Possible solutions:"
        log_info "   1. Run: sudo ./install.sh fix:permissions $app_name"
        log_info "   2. Use non-privileged ports (8000, 8080, etc.)"
        log_info "   3. Setup proper capabilities for binding to ports < 1024"
    fi
    
    # Check for port binding issues
    if journalctl -u "octane-$app_name.service" -n 50 --no-pager | grep -q "bind: permission denied"; then
        log_error "🚫 Port binding issue detected!"
        log_info "💡 The service is trying to bind to privileged ports (80/443) with user www-data"
        log_info "   Solutions:"
        log_info "   1. Use sudo ./install.sh fix:ports $app_name"
        log_info "   2. Configure reverse proxy (nginx/apache)"
        log_info "   3. Use systemd socket activation"
    fi
    
    # Check for TLS storage issues
    if journalctl -u "octane-$app_name.service" -n 50 --no-pager | grep -q "read-only file system"; then
        log_error "🚫 TLS storage issue detected!"
        log_info "💡 Run: sudo ./install.sh fix:tls-storage $app_name"
    fi
    
    # Check if app directory exists
    if [ ! -d "$app_dir" ]; then
        log_error "🚫 App directory not found: $app_dir"
        return 1
    fi
    
    # Check if Laravel app is properly configured
    if [ ! -f "$app_dir/.env" ]; then
        log_error "🚫 .env file not found in $app_dir"
        log_info "💡 Run: sudo ./install.sh fix:env $app_name"
    fi
}

# =============================================
# Fix Functions
# =============================================

fix_permissions() {
    local app_name="$1"
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    log_info "🔧 Fixing permissions for $app_name..."
    
    # Create necessary directories
    mkdir -p /var/lib/caddy
    mkdir -p /var/log/frankenphp
    
    # Set proper ownership
    chown -R www-data:www-data "$app_dir"
    chown -R www-data:www-data /var/lib/caddy
    chown -R www-data:www-data /var/log/frankenphp
    
    # Set proper permissions
    chmod -R 755 "$app_dir"
    chmod -R 755 /var/lib/caddy
    chmod -R 755 /var/log/frankenphp
    
    # Fix storage permissions
    if [ -d "$app_dir/storage" ]; then
        chmod -R 775 "$app_dir/storage"
    fi
    
    # Fix bootstrap/cache permissions
    if [ -d "$app_dir/bootstrap/cache" ]; then
        chmod -R 775 "$app_dir/bootstrap/cache"
    fi
    
    log_info "✅ Permissions fixed"
}

fix_ports() {
    local app_name="$1"
    local app_dir="$APPS_BASE_DIR/$app_name"
    local service_file="/etc/systemd/system/octane-$app_name.service"
    
    log_info "🔧 Fixing port binding issues for $app_name..."
    
    # Option 1: Use capabilities to allow binding to privileged ports
    if command -v setcap >/dev/null 2>&1; then
        log_info "🔧 Setting capabilities for PHP binary..."
        setcap 'cap_net_bind_service=+ep' /usr/bin/php
        
        # Also set for FrankenPHP binary if it exists
        if [ -f "/usr/local/bin/frankenphp" ]; then
            setcap 'cap_net_bind_service=+ep' /usr/local/bin/frankenphp
        fi
    fi
    
    # Option 2: Update systemd service to use non-privileged ports with reverse proxy
    log_info "🔧 Creating reverse proxy configuration..."
    create_reverse_proxy_config "$app_name"
    
    # Update service to use non-privileged ports
    log_info "🔧 Updating service to use port 8000..."
    update_service_ports "$app_name" "8000"
    
    systemctl daemon-reload
    systemctl restart "octane-$app_name.service"
    
    log_info "✅ Port configuration fixed"
}

fix_tls_storage() {
    local app_name="$1"
    
    log_info "🔧 Fixing TLS storage issues for $app_name..."
    
    # Create proper TLS storage directories
    mkdir -p /var/lib/caddy/.local/share/caddy
    mkdir -p /var/lib/caddy/.local/share/caddy/locks
    
    # Set proper ownership
    chown -R www-data:www-data /var/lib/caddy
    
    # Set proper permissions
    chmod -R 755 /var/lib/caddy
    
    # Update service to use proper data directory
    local service_file="/etc/systemd/system/octane-$app_name.service"
    if [ -f "$service_file" ]; then
        # Add environment variable for Caddy data directory
        if ! grep -q "Environment=XDG_DATA_HOME" "$service_file"; then
            sed -i '/Environment=APP_DEBUG=false/a Environment=XDG_DATA_HOME=/var/lib/caddy/.local/share' "$service_file"
        fi
        
        # Update ReadWritePaths
        sed -i 's|ReadWritePaths=/opt/laravel-apps/.*|ReadWritePaths=/opt/laravel-apps/'$app_name' /tmp /var/lib/caddy|' "$service_file"
    fi
    
    systemctl daemon-reload
    systemctl restart "octane-$app_name.service"
    
    log_info "✅ TLS storage fixed"
}

create_reverse_proxy_config() {
    local app_name="$1"
    local domain=$(grep "host=" "/etc/systemd/system/octane-$app_name.service" | sed 's/.*--host=\([^ ]*\).*/\1/')
    
    # Create nginx configuration
    cat > "/etc/nginx/sites-available/$app_name" << EOF
server {
    listen 80;
    server_name $domain;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl;
    server_name $domain;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Enable the site
    ln -sf "/etc/nginx/sites-available/$app_name" "/etc/nginx/sites-enabled/$app_name"
    
    # Test nginx configuration
    if nginx -t; then
        systemctl reload nginx
        log_info "✅ Nginx reverse proxy configured"
    else
        log_error "❌ Nginx configuration test failed"
    fi
}

update_service_ports() {
    local app_name="$1"
    local port="$2"
    local service_file="/etc/systemd/system/octane-$app_name.service"
    
    if [ -f "$service_file" ]; then
        # Update the ExecStart line to use the new port
        sed -i "s|--port=[0-9]*|--port=$port|" "$service_file"
        # Remove --https flag since we're using reverse proxy
        sed -i "s|--https ||" "$service_file"
        # Remove --http-redirect flag
        sed -i "s|--http-redirect ||" "$service_file"
        
        log_info "✅ Service updated to use port $port"
    fi
}

fix_env() {
    local app_name="$1"
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    log_info "🔧 Fixing .env configuration for $app_name..."
    
    cd "$app_dir"
    
    # Copy .env.example if .env doesn't exist
    if [ ! -f ".env" ] && [ -f ".env.example" ]; then
        cp ".env.example" ".env"
    fi
    
    # Generate app key if not set
    if [ -f ".env" ]; then
        if ! grep -q "APP_KEY=" ".env" || grep -q "APP_KEY=$" ".env"; then
            php artisan key:generate --force
        fi
    fi
    
    # Set proper permissions
    chown www-data:www-data ".env"
    chmod 600 ".env"
    
    log_info "✅ .env configuration fixed"
}

# =============================================
# Comprehensive Fix Function
# =============================================

fix_app_issues() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "Usage: fix_app_issues <app-name>"
        return 1
    fi
    
    log_info "🔧 Comprehensive fix for app: $app_name"
    
    # Stop the service first
    systemctl stop "octane-$app_name.service" || true
    
    # Run all fixes
    fix_permissions "$app_name"
    fix_tls_storage "$app_name"
    fix_ports "$app_name"
    fix_env "$app_name"
    
    # Start the service
    systemctl start "octane-$app_name.service"
    
    log_info "✅ Comprehensive fix completed for $app_name"
    log_info "🔍 Check status: ./install.sh status $app_name"
}

# =============================================
# Setup Commands for Existing Apps
# =============================================

setup_octane_for_existing_app() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "Usage: octane:setup <app-name>"
        return 1
    fi
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    if [ ! -d "$app_dir" ]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi
    
    log_info "🔧 Setting up Octane for existing app: $app_name"
    
    # Get domain from config
    local domain=""
    if [ -f "/etc/laravel-apps/$app_name.conf" ]; then
        domain=$(grep "DOMAIN=" "/etc/laravel-apps/$app_name.conf" | cut -d'=' -f2 | tr -d '"')
    fi
    
    if [ -z "$domain" ]; then
        log_error "Domain not found in config. Please provide domain:"
        read -p "Domain: " domain
    fi
    
    # Setup Octane
    cd "$app_dir"
    install_octane "$app_name" "$app_dir" "$domain"
    
    log_info "✅ Octane setup completed for $app_name"
}

configure_octane_settings() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "Usage: octane:config <app-name>"
        return 1
    fi
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    if [ ! -d "$app_dir" ]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi
    
    log_info "⚙️ Configuring Octane settings for: $app_name"
    
    # Get domain from config
    local domain=""
    if [ -f "/etc/laravel-apps/$app_name.conf" ]; then
        domain=$(grep "DOMAIN=" "/etc/laravel-apps/$app_name.conf" | cut -d'=' -f2 | tr -d '"')
    fi
    
    if [ -z "$domain" ]; then
        log_error "Domain not found in config"
        return 1
    fi
    
    cd "$app_dir"
    
    # Setup FrankenPHP configuration
    setup_frankenphp_config "$app_name" "$domain"
    
    # Setup TLS storage
    setup_tls_storage "$app_name"
    
    log_info "✅ Octane configuration completed for $app_name"
}

check_octane_installed() {
    # Check if Octane is in composer.json
    if [ -f "composer.json" ]; then
        if grep -q '"laravel/octane"' composer.json; then
            log_info "📦 Octane found in composer.json"

            # Check if Octane is actually installed in vendor
            if [ -d "vendor/laravel/octane" ]; then
                log_info "✅ Octane package is installed"

                # Check if artisan octane commands are available
                if sudo -u www-data php artisan list | grep -q "octane:"; then
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

# =============================================
# Installation Helper Functions
# =============================================

save_app_config() {
    local app_name="$1"
    local domain="$2"
    local app_dir="$3"
    local db_name="$4"
    
    log_info "📝 Saving app configuration for $app_name"
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Create config file
    cat > "$CONFIG_DIR/$app_name.conf" << EOF
# Laravel App Configuration for $app_name
APP_NAME="$app_name"
DOMAIN="$domain"
APP_DIR="$app_dir"
DB_NAME="$db_name"
DB_USER="root"
DB_PASS=""
CREATED_AT="$(date)"
EOF
    
    # Set proper permissions
    chmod 600 "$CONFIG_DIR/$app_name.conf"
    
    log_info "✅ App configuration saved"
}

# =============================================
# Multi-App Resource Management Functions
# =============================================

count_running_apps() {
    local count=0
    for service in $(systemctl list-units --type=service --state=running | grep "octane-" | awk '{print $1}'); do
        count=$((count + 1))
    done
    echo $count
}

calculate_safe_memory_per_app() {
    local total_memory="$1"
    local total_apps="$2"
    
    # Reserve 20% for system
    local usable_memory=$((total_memory * 80 / 100))
    
    # Calculate memory per app with safety margin
    local memory_per_app=$((usable_memory / total_apps))
    
    # Apply minimum and maximum limits
    [ $memory_per_app -lt 256 ] && memory_per_app=256
    [ $memory_per_app -gt 2048 ] && memory_per_app=2048
    
    echo $memory_per_app
}

calculate_safe_workers_per_app() {
    local cpu_cores="$1"
    local total_apps="$2"
    
    # Calculate max workers we can safely allocate
    local max_total_workers=$((cpu_cores * 2))
    local workers_per_app=$((max_total_workers / total_apps))
    
    # Apply minimum and maximum limits
    [ $workers_per_app -lt 1 ] && workers_per_app=1
    [ $workers_per_app -gt 8 ] && workers_per_app=8
    
    echo $workers_per_app
}

calculate_max_requests() {
    local memory_per_app="$1"
    
    # Calculate max_requests based on memory allocation
    local max_requests=$((memory_per_app * 2))
    
    # Apply sensible limits
    [ $max_requests -lt 100 ] && max_requests=100
    [ $max_requests -gt 3000 ] && max_requests=3000
    
    echo $max_requests
}

check_resource_availability() {
    local total_memory="$1"
    local cpu_cores="$2"
    local total_apps_after_install="$3"
    
    # Check if we exceed recommended limits
    local max_apps=$(get_recommended_max_apps "$total_memory" "$cpu_cores")
    
    if [ $total_apps_after_install -gt $max_apps ]; then
        return 1
    fi
    
    # Check if memory per app would be too low
    local memory_per_app=$(calculate_safe_memory_per_app "$total_memory" "$total_apps_after_install")
    if [ $memory_per_app -lt 256 ]; then
        return 1
    fi
    
    return 0
}

get_recommended_max_apps() {
    local total_memory="$1"
    local cpu_cores="$2"
    
    # Calculate based on memory (min 256MB per app)
    local max_apps_by_memory=$((total_memory * 80 / 100 / 256))
    
    # Calculate based on CPU (max 2 workers per CPU core)
    local max_apps_by_cpu=$((cpu_cores * 2))
    
    # Take the minimum of both
    local max_apps=$max_apps_by_memory
    [ $max_apps_by_cpu -lt $max_apps ] && max_apps=$max_apps_by_cpu
    
    # Apply absolute limits
    [ $max_apps -lt 1 ] && max_apps=1
    [ $max_apps -gt 50 ] && max_apps=50
    
    echo $max_apps
}

save_resource_allocation() {
    local app_name="$1"
    local workers="$2"
    local max_requests="$3"
    local memory_allocation="$4"
    local total_apps="$5"
    
    # Save to config file
    local config_file="$CONFIG_DIR/$app_name.conf"
    if [ -f "$config_file" ]; then
        # Add resource allocation info
        cat >> "$config_file" << EOF

# Resource Allocation (Auto-generated)
WORKERS=$workers
MAX_REQUESTS=$max_requests
MEMORY_ALLOCATION=${memory_allocation}MB
TOTAL_APPS_AT_INSTALL=$total_apps
ALLOCATION_TIMESTAMP="$(date)"
EOF
    fi
}

show_multi_app_resource_usage() {
    log_info "📊 Multi-App Resource Usage Summary:"
    echo ""
    
    local total_memory=$(free -m | awk 'NR==2{print $2}')
    local used_memory=$(free -m | awk 'NR==2{print $3}')
    local cpu_cores=$(nproc)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    local running_apps=$(count_running_apps)
    local max_recommended=$(get_recommended_max_apps "$total_memory" "$cpu_cores")
    
    printf "%-20s %-10s %-10s %-10s %-10s\n" "App Name" "Workers" "Memory" "Status" "Port"
    echo "=========================================================================="
    
    local total_workers=0
    local total_allocated_memory=0
    
    for app_dir in "$APPS_BASE_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            local env_file="$app_dir/.env"
            
            if [ -f "$env_file" ]; then
                # Read workers from .env file
                local workers=$(grep "^OCTANE_WORKERS=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
                
                # Read memory allocation from .env file
                local memory=$(grep "^OCTANE_MULTIAPP_MEMORY_ALLOCATION=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
                
                # If no memory allocation found, estimate based on workers
                if [ -z "$memory" ] && [ "$workers" != "N/A" ]; then
                    # Estimate ~80MB per worker as default
                    local estimated_memory=$((workers * 80))
                    memory="${estimated_memory}MB"
                elif [ -z "$memory" ]; then
                    memory="N/A"
                fi
                
                local status="Stopped"
                if systemctl is-active --quiet "octane-$app_name"; then
                    status="Running"
                fi
                
                # Get port from service file or default to 443 for HTTPS
                local port="443"
                if [ -f "/etc/systemd/system/octane-$app_name.service" ]; then
                    local service_port=$(grep "ExecStart=" "/etc/systemd/system/octane-$app_name.service" | grep -o "port=[0-9]*" | cut -d'=' -f2 2>/dev/null)
                    if [ -n "$service_port" ]; then
                        port="$service_port"
                    fi
                fi
                
                printf "%-20s %-10s %-10s %-10s %-10s\n" "$app_name" "$workers" "$memory" "$status" "$port"
                
                # Calculate totals only for running apps
                if [ "$workers" != "N/A" ] && [ "$status" = "Running" ]; then
                    total_workers=$((total_workers + workers))
                fi
                
                if [ "$memory" != "N/A" ] && [ "$status" = "Running" ]; then
                    local mem_num=$(echo "$memory" | sed 's/MB//')
                    if [[ "$mem_num" =~ ^[0-9]+$ ]]; then
                        total_allocated_memory=$((total_allocated_memory + mem_num))
                    fi
                fi
            fi
        fi
    done
    
    echo "=========================================================================="
    echo ""
    log_info "📈 Resource Summary:"
    log_info "   Running apps: $running_apps / $max_recommended (recommended max)"
    log_info "   Total workers: $total_workers / $((cpu_cores * 2)) (max safe)"
    log_info "   Allocated memory: ${total_allocated_memory}MB / ${total_memory}MB (total)"
    log_info "   Memory usage: $(echo "scale=1; $used_memory * 100 / $total_memory" | bc -l)%"
    log_info "   Load average: $load_avg"
    
    # Show warnings if needed
    if [ $running_apps -gt $max_recommended ]; then
        log_warning "⚠️  WARNING: Too many apps running! Performance may be degraded."
    fi
    
    if [ $total_workers -gt $((cpu_cores * 2)) ]; then
        log_warning "⚠️  WARNING: Total workers exceed CPU capacity!"
    fi
    
    local memory_usage_percent=$(echo "scale=0; $used_memory * 100 / $total_memory" | bc -l)
    if [ $memory_usage_percent -gt 80 ]; then
        log_warning "⚠️  WARNING: High memory usage detected!"
    fi
}
