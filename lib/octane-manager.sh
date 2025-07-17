#!/bin/bash

# =============================================
# Octane Manager Library
# Library untuk manajemen Laravel Octane
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${OCTANE_MANAGER_LOADED:-}" ]; then
    return 0
fi
export OCTANE_MANAGER_LOADED=1

# =============================================
# Octane Management Functions
# =============================================

octane_install() {
    local target_dir="${1:-$(pwd)}"

    if [ ! -d "$target_dir" ]; then
        log_error "Directory not found: $target_dir"
        return 1
    fi

    cd "$target_dir"

    # Check if it's a Laravel project
    if [ ! -f "artisan" ]; then
        log_error "Not a Laravel project (artisan not found)"
        return 1
    fi

    log_info "🚀 Installing Laravel Octane with FrankenPHP..."

    # Step 1: Check if Octane is already installed
    if php artisan list | grep -q "octane:start"; then
        log_info "✅ Laravel Octane already installed"

        # Step 2: Configure FrankenPHP (Laravel will handle binary download)
        log_info "🔧 Configuring Octane to use FrankenPHP..."
        if ! php artisan octane:install --server=frankenphp; then
            log_error "Failed to configure Octane with FrankenPHP"
            return 1
        fi
    else
        log_info "📦 Installing Laravel Octane..."

        # Step 1: Install Octane package
        if ! composer require laravel/octane; then
            log_error "Failed to install Laravel Octane"
            return 1
        fi

        # Step 2: Install and configure FrankenPHP (Laravel will handle binary download)
        log_info "🔧 Installing and configuring FrankenPHP..."
        if ! php artisan octane:install --server=frankenphp; then
            log_error "Failed to install FrankenPHP via Laravel Octane"
            return 1
        fi
    fi

    log_info "✅ Laravel Octane with FrankenPHP installed successfully!"
    log_info "🔧 To start server: php artisan octane:start --server=frankenphp"
    log_info "🔧 Or use: octane_start"
}

octane_start() {
    local app_name="${1:-}"
    
    if [ -z "$app_name" ]; then
        log_error "App name is required"
        return 1
    fi
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    if [ ! -d "$app_dir" ]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi
    
    log_info "▶️  Starting Octane server for app: $app_name"
    
    # Start systemd service
    if systemctl start "octane-$app_name"; then
        log_info "✅ Octane server started successfully"
    else
        log_error "Failed to start Octane server"
        return 1
    fi
}

octane_stop() {
    local app_name="${1:-}"
    
    if [ -z "$app_name" ]; then
        log_error "App name is required"
        return 1
    fi
    
    log_info "⏹️  Stopping Octane server for app: $app_name"
    
    # Stop systemd service
    if systemctl stop "octane-$app_name"; then
        log_info "✅ Octane server stopped successfully"
    else
        log_error "Failed to stop Octane server"
        return 1
    fi
}

octane_restart() {
    local app_name="${1:-}"
    
    if [ -z "$app_name" ]; then
        log_error "App name is required"
        return 1
    fi
    
    log_info "🔄 Restarting Octane server for app: $app_name"
    
    # Restart systemd service
    if systemctl restart "octane-$app_name"; then
        log_info "✅ Octane server restarted successfully"
    else
        log_error "Failed to restart Octane server"
        return 1
    fi
}

octane_status() {
    local app_name="${1:-}"
    
    if [ -z "$app_name" ]; then
        log_error "App name is required"
        return 1
    fi
    
    log_info "📊 Octane server status for app: $app_name"
    
    # Show systemd service status
    systemctl status "octane-$app_name" --no-pager
}

octane_create_service() {
    local app_name="$1"
    local port="${2:-8000}"
    
    log_info "🔧 Creating Octane systemd service for app: $app_name"
    
    # Use systemd manager to create service
    create_octane_service "$app_name" "$port"
}

# =============================================
# HTTP/HTTPS Dual Mode Management
# =============================================

octane_create_dual_mode_service() {
    local app_name="$1"
    local domain="$2"
    local app_dir="$3"
    local mode="${4:-dual}"  # dual, https-only, http-only

    if [ -z "$app_name" ] || [ -z "$domain" ] || [ -z "$app_dir" ]; then
        log_error "Usage: octane_create_dual_mode_service <app_name> <domain> <app_dir> [mode]"
        return 1
    fi

    log_info "🔧 Creating Octane service with mode: $mode for $app_name"

    case "$mode" in
        "dual")
            _create_dual_mode_services "$app_name" "$domain" "$app_dir"
            ;;
        "https-only")
            _create_https_only_service "$app_name" "$domain" "$app_dir"
            ;;
        "http-only")
            _create_http_only_service "$app_name" "$domain" "$app_dir"
            ;;
        *)
            log_error "Invalid mode: $mode. Use: dual, https-only, http-only"
            return 1
            ;;
    esac
}

_create_dual_mode_services() {
    local app_name="$1"
    local domain="$2"
    local app_dir="$3"

    log_info "🌐 Creating dual mode services (HTTP + HTTPS) for $app_name"

    # Create HTTPS service (port 443)
    cat > "/etc/systemd/system/octane-$app_name-https.service" << EOF
[Unit]
Description=Laravel Octane HTTPS Server for $app_name
Documentation=https://laravel.com/docs/octane
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php artisan octane:frankenphp --host=$domain --port=443 --https --workers=4 --max-requests=1000 --log-level=info
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

    # Create HTTP service (port 80) - NO redirect
    cat > "/etc/systemd/system/octane-$app_name-http.service" << EOF
[Unit]
Description=Laravel Octane HTTP Server for $app_name
Documentation=https://laravel.com/docs/octane
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php artisan octane:frankenphp --host=$domain --port=80 --workers=4 --max-requests=1000 --log-level=info
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
    chmod 644 "/etc/systemd/system/octane-$app_name-https.service"
    chmod 644 "/etc/systemd/system/octane-$app_name-http.service"

    # Allow www-data to bind to privileged ports
    if command -v setcap >/dev/null 2>&1; then
        local php_binary=$(readlink -f /usr/bin/php)
        if [ -f "$php_binary" ]; then
            setcap 'cap_net_bind_service=+ep' "$php_binary"
        fi
    fi

    log_info "✅ Dual mode services created:"
    log_info "   - HTTPS: octane-$app_name-https (port 443)"
    log_info "   - HTTP: octane-$app_name-http (port 80, no redirect)"
}

_create_https_only_service() {
    local app_name="$1"
    local domain="$2"
    local app_dir="$3"

    log_info "🔒 Creating HTTPS-only service for $app_name"

    # Create HTTPS service with HTTP redirect
    cat > "/etc/systemd/system/octane-$app_name.service" << EOF
[Unit]
Description=Laravel Octane HTTPS Server for $app_name
Documentation=https://laravel.com/docs/octane
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php artisan octane:frankenphp --host=$domain --port=443 --https --http-redirect --workers=4 --max-requests=1000 --log-level=info
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

    chmod 644 "/etc/systemd/system/octane-$app_name.service"

    # Allow www-data to bind to privileged ports
    if command -v setcap >/dev/null 2>&1; then
        local php_binary=$(readlink -f /usr/bin/php)
        if [ -f "$php_binary" ]; then
            setcap 'cap_net_bind_service=+ep' "$php_binary"
        fi
    fi

    log_info "✅ HTTPS-only service created: octane-$app_name (port 443 with HTTP redirect)"
}

_create_http_only_service() {
    local app_name="$1"
    local domain="$2"
    local app_dir="$3"

    log_info "🌐 Creating HTTP-only service for $app_name"

    # Create HTTP service only
    cat > "/etc/systemd/system/octane-$app_name.service" << EOF
[Unit]
Description=Laravel Octane HTTP Server for $app_name
Documentation=https://laravel.com/docs/octane
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php artisan octane:frankenphp --host=$domain --port=80 --workers=4 --max-requests=1000 --log-level=info
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

    chmod 644 "/etc/systemd/system/octane-$app_name.service"

    # Allow www-data to bind to privileged ports
    if command -v setcap >/dev/null 2>&1; then
        local php_binary=$(readlink -f /usr/bin/php)
        if [ -f "$php_binary" ]; then
            setcap 'cap_net_bind_service=+ep' "$php_binary"
        fi
    fi

    log_info "✅ HTTP-only service created: octane-$app_name (port 80)"
}

octane_start_dual_mode() {
    local app_name="$1"
    local mode="${2:-dual}"

    if [ -z "$app_name" ]; then
        log_error "Usage: octane_start_dual_mode <app_name> [mode]"
        return 1
    fi

    log_info "🚀 Starting Octane services for $app_name in $mode mode"

    case "$mode" in
        "dual")
            systemctl daemon-reload
            systemctl enable "octane-$app_name-https"
            systemctl enable "octane-$app_name-http"
            systemctl start "octane-$app_name-https"
            systemctl start "octane-$app_name-http"
            log_info "✅ Dual mode services started"
            ;;
        "https-only")
            systemctl daemon-reload
            systemctl enable "octane-$app_name"
            systemctl start "octane-$app_name"
            log_info "✅ HTTPS-only service started"
            ;;
        "http-only")
            systemctl daemon-reload
            systemctl enable "octane-$app_name"
            systemctl start "octane-$app_name"
            log_info "✅ HTTP-only service started"
            ;;
        *)
            log_error "Invalid mode: $mode"
            return 1
            ;;
    esac
}

octane_stop_dual_mode() {
    local app_name="$1"
    local mode="${2:-dual}"

    if [ -z "$app_name" ]; then
        log_error "Usage: octane_stop_dual_mode <app_name> [mode]"
        return 1
    fi

    log_info "🛑 Stopping Octane services for $app_name in $mode mode"

    case "$mode" in
        "dual")
            systemctl stop "octane-$app_name-https" 2>/dev/null || true
            systemctl stop "octane-$app_name-http" 2>/dev/null || true
            systemctl disable "octane-$app_name-https" 2>/dev/null || true
            systemctl disable "octane-$app_name-http" 2>/dev/null || true
            log_info "✅ Dual mode services stopped"
            ;;
        "https-only"|"http-only")
            systemctl stop "octane-$app_name" 2>/dev/null || true
            systemctl disable "octane-$app_name" 2>/dev/null || true
            log_info "✅ Service stopped"
            ;;
        *)
            log_error "Invalid mode: $mode"
            return 1
            ;;
    esac
}

octane_status_dual_mode() {
    local app_name="$1"
    local mode="${2:-dual}"

    if [ -z "$app_name" ]; then
        log_error "Usage: octane_status_dual_mode <app_name> [mode]"
        return 1
    fi

    log_info "📊 Octane service status for $app_name ($mode mode)"

    case "$mode" in
        "dual")
            echo ""
            echo "HTTPS Service (octane-$app_name-https):"
            systemctl status "octane-$app_name-https" --no-pager -l || true
            echo ""
            echo "HTTP Service (octane-$app_name-http):"
            systemctl status "octane-$app_name-http" --no-pager -l || true
            ;;
        "https-only"|"http-only")
            echo ""
            systemctl status "octane-$app_name" --no-pager -l || true
            ;;
        *)
            log_error "Invalid mode: $mode"
            return 1
            ;;
    esac
}

octane_restart_dual_mode() {
    local app_name="$1"
    local mode="${2:-dual}"

    if [ -z "$app_name" ]; then
        log_error "Usage: octane_restart_dual_mode <app_name> [mode]"
        return 1
    fi

    log_info "🔄 Restarting Octane services for $app_name in $mode mode"

    case "$mode" in
        "dual")
            systemctl restart "octane-$app_name-https"
            systemctl restart "octane-$app_name-http"
            log_info "✅ Dual mode services restarted"
            ;;
        "https-only"|"http-only")
            systemctl restart "octane-$app_name"
            log_info "✅ Service restarted"
            ;;
        *)
            log_error "Invalid mode: $mode"
            return 1
            ;;
    esac
}

# =============================================
# Configuration Management
# =============================================

octane_configure_mode() {
    local app_name="$1"
    local mode="$2"
    local domain="$3"

    if [ -z "$app_name" ] || [ -z "$mode" ]; then
        log_error "Usage: octane_configure_mode <app_name> <mode> [domain]"
        log_info "Available modes: dual, https-only, http-only"
        return 1
    fi

    local app_dir="$APPS_BASE_DIR/$app_name"
    if [ ! -d "$app_dir" ]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi

    # Get domain from config if not provided
    if [ -z "$domain" ]; then
        if [ -f "/etc/laravel-apps/$app_name.conf" ]; then
            domain=$(grep "DOMAIN=" "/etc/laravel-apps/$app_name.conf" | cut -d'=' -f2 | tr -d '"')
        fi
    fi

    if [ -z "$domain" ]; then
        log_error "Domain not specified and not found in config"
        return 1
    fi

    log_info "⚙️  Configuring Octane mode: $mode for $app_name"

    # Stop existing services
    octane_stop_dual_mode "$app_name" "dual" 2>/dev/null || true
    octane_stop_dual_mode "$app_name" "https-only" 2>/dev/null || true
    octane_stop_dual_mode "$app_name" "http-only" 2>/dev/null || true

    # Remove old service files
    rm -f "/etc/systemd/system/octane-$app_name.service"
    rm -f "/etc/systemd/system/octane-$app_name-https.service"
    rm -f "/etc/systemd/system/octane-$app_name-http.service"

    # Create new service(s) based on mode
    octane_create_dual_mode_service "$app_name" "$domain" "$app_dir" "$mode"

    # Start services
    octane_start_dual_mode "$app_name" "$mode"

    log_info "✅ Octane mode configured successfully: $mode"
    log_info "🔍 Check status: octane_status_dual_mode $app_name $mode"
}

# =============================================
# Octane Health Check Functions
# =============================================

octane_health_check() {
    local target_dir="${1:-$(pwd)}"

    cd "$target_dir"

    log_info "🏥 Running Octane health check..."

    local issues=0

    # Check Laravel installation
    if [ ! -f "artisan" ]; then
        log_error "❌ Laravel not found"
        issues=$((issues + 1))
    else
        log_info "✅ Laravel project found"
    fi

    # Check Octane installation
    if ! php artisan list | grep -q "octane:start"; then
        log_error "❌ Octane not installed"
        issues=$((issues + 1))
    else
        log_info "✅ Octane installed"
    fi

    # Check FrankenPHP configuration
    if [ -f "config/octane.php" ]; then
        if grep -q "frankenphp" config/octane.php; then
            log_info "✅ FrankenPHP configured in Octane"
        else
            log_warning "⚠️  FrankenPHP not configured in Octane"
            issues=$((issues + 1))
        fi
    else
        log_warning "⚠️  Octane config file not found"
        issues=$((issues + 1))
    fi

    # Check environment file
    if [ ! -f ".env" ]; then
        log_error "❌ .env file not found"
        issues=$((issues + 1))
    else
        log_info "✅ .env file found"
    fi

    # Check database connection
    if timeout 10 php artisan tinker --execute="DB::connection()->getPdo(); echo 'DB OK';" 2>/dev/null | grep -q "DB OK"; then
        log_info "✅ Database connection works"
    else
        log_warning "⚠️  Database connection failed"
        issues=$((issues + 1))
    fi

    # Check memory limit
    local memory_limit=$(php -r "echo ini_get('memory_limit');")
    log_info "💾 PHP Memory Limit: $memory_limit"

    # Check max execution time
    local max_execution_time=$(php -r "echo ini_get('max_execution_time');")
    log_info "⏱️  Max Execution Time: $max_execution_time seconds"

    # Summary
    if [ $issues -eq 0 ]; then
        log_info "✅ Health check passed - No issues found"
    else
        log_warning "⚠️  Health check found $issues issue(s)"
    fi

    return $issues
}

# =============================================
# Octane Performance Functions
# =============================================

octane_performance_tune() {
    local target_dir="${1:-$(pwd)}"

    cd "$target_dir"

    log_info "⚡ Tuning Octane performance..."

    # Create or update octane config
    if [ ! -f "config/octane.php" ]; then
        php artisan vendor:publish --provider="Laravel\Octane\OctaneServiceProvider" --tag="config"
    fi

    # Optimize PHP settings for Octane
    log_info "🔧 Optimizing PHP settings for Octane..."

    # Add recommended settings to .env if not present
    if ! grep -q "OCTANE_SERVER" .env; then
        echo "" >> .env
        echo "# Octane Settings" >> .env
        echo "OCTANE_SERVER=frankenphp" >> .env
        echo "OCTANE_HTTPS=true" >> .env
        echo "OCTANE_MAX_REQUESTS=1000" >> .env
    fi

    log_info "✅ Performance tuning completed"
}

# =============================================
# Octane Log Management
# =============================================

octane_logs() {
    local target_dir="${1:-$(pwd)}"
    local lines="${2:-50}"

    cd "$target_dir"

    log_info "📋 Showing last $lines lines of Octane logs..."

    # Show Laravel logs
    if [ -f "storage/logs/laravel.log" ]; then
        tail -n "$lines" storage/logs/laravel.log
    else
        log_info "No Laravel logs found"
    fi
}

octane_clear_logs() {
    local target_dir="${1:-$(pwd)}"

    cd "$target_dir"

    log_info "🧹 Clearing Octane logs..."

    # Clear Laravel logs
    if [ -f "storage/logs/laravel.log" ]; then
        > storage/logs/laravel.log
        log_info "✅ Laravel logs cleared"
    fi

    # Clear other log files
    find storage/logs -name "*.log" -type f -exec truncate -s 0 {} \;

    log_info "✅ All logs cleared"
}

# =============================================
# Helper Functions
# =============================================

is_octane_installed() {
    local target_dir="${1:-$(pwd)}"
    cd "$target_dir"
    php artisan list | grep -q "octane:start"
}

is_frankenphp_configured() {
    local target_dir="${1:-$(pwd)}"
    cd "$target_dir"

    # Check if octane config exists and has frankenphp configured
    if [ -f "config/octane.php" ]; then
        grep -q "frankenphp" config/octane.php
    else
        return 1
    fi
}

check_octane_server_config() {
    local target_dir="${1:-$(pwd)}"
    cd "$target_dir"

    # Check .env file for OCTANE_SERVER
    if [ -f ".env" ]; then
        grep -q "OCTANE_SERVER=frankenphp" .env
    else
        return 1
    fi
}

install_octane_if_needed() {
    local target_dir="${1:-$(pwd)}"
    cd "$target_dir"

    if ! is_octane_installed; then
        log_info "📦 Installing Laravel Octane..."
        if ! composer require laravel/octane; then
            log_error "Failed to install Laravel Octane"
            return 1
        fi
        log_info "✅ Laravel Octane installed successfully"
    else
        log_info "✅ Laravel Octane already installed"
    fi

    return 0
}

configure_frankenphp_if_needed() {
    local target_dir="${1:-$(pwd)}"
    cd "$target_dir"

    if ! is_frankenphp_configured; then
        log_info "🔧 Configuring FrankenPHP for Octane..."
        if ! php artisan octane:install --server=frankenphp; then
            log_error "Failed to configure FrankenPHP"
            return 1
        fi
        log_info "✅ FrankenPHP configured successfully"
    else
        log_info "✅ FrankenPHP already configured"
    fi

    return 0
}

# Enhanced installation function using best practices
octane_install_best_practice() {
    local target_dir="${1:-$(pwd)}"

    if [ ! -d "$target_dir" ]; then
        log_error "Directory not found: $target_dir"
        return 1
    fi

    cd "$target_dir"

    # Check if it's a Laravel project
    if [ ! -f "artisan" ]; then
        log_error "Not a Laravel project (artisan not found)"
        return 1
    fi

    log_info "🚀 Setting up Laravel Octane with FrankenPHP (Best Practice)..."

    # Step 1: Install Octane if needed
    if ! install_octane_if_needed "$target_dir"; then
        return 1
    fi

    # Step 2: Configure FrankenPHP if needed
    if ! configure_frankenphp_if_needed "$target_dir"; then
        return 1
    fi

    # Step 3: Update .env file if needed
    if ! check_octane_server_config; then
        log_info "🔧 Updating .env file for FrankenPHP..."
        if ! grep -q "OCTANE_SERVER=" .env; then
            echo "OCTANE_SERVER=frankenphp" >> .env
        else
            sed -i.bak 's/OCTANE_SERVER=.*/OCTANE_SERVER=frankenphp/' .env
        fi
        log_info "✅ .env file updated"
    fi

    log_info "✅ Laravel Octane with FrankenPHP setup completed!"
    log_info "🔧 To start server: php artisan octane:start"
    log_info "🔧 Or use: octane_start"
}

is_octane_running() {
    pgrep -f "octane:start" > /dev/null
}

get_octane_pid() {
    pgrep -f "octane:start"
}

octane_memory_usage() {
    local pid=$(get_octane_pid)
    if [ -n "$pid" ]; then
        ps -p "$pid" -o pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -2
    else
        log_info "Octane not running"
    fi
}
