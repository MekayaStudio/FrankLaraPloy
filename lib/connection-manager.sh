#!/bin/bash

# =============================================
# Connection Manager Library
# Library untuk mengatasi masalah koneksi FrankenPHP
# Mengintegrasikan fix-frankenphp-connection.sh dan fix-octane-frankenphp-native.sh
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "$CONNECTION_MANAGER_LOADED" ]; then
    return 0
fi
export CONNECTION_MANAGER_LOADED=1

# =============================================
# Connection Check Functions
# =============================================

connection_check() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: connection_check <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        display_validation_results
        return 1
    fi

    log_info "🔍 Checking connection for app: $app_name"
    echo ""

    # Check app directory
    local app_dir="$APPS_BASE_DIR/$app_name"
    if [ ! -d "$app_dir" ]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi
    log_info "✅ App directory exists: $app_dir"

    # Check app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    if [ ! -f "$app_config" ]; then
        log_error "App config not found: $app_config"
        return 1
    fi
    log_info "✅ App config exists: $app_config"

    # Load app config
    source "$app_config"
    log_info "✅ App domain: $DOMAIN"

    # Check systemd service
    local service_name="frankenphp-$app_name"
    if systemctl is-active --quiet "$service_name"; then
        log_info "✅ Service $service_name is running"
    else
        log_warning "⚠️  Service $service_name is not running"
    fi

    # Check ports
    _check_port_status "8000" "Laravel Octane"
    _check_port_status "80" "HTTP"
    _check_port_status "443" "HTTPS"

    # Check Caddyfile
    if [ -f "$app_dir/Caddyfile" ]; then
        log_info "✅ Caddyfile exists"
        echo ""
        log_info "📋 Caddyfile content:"
        cat "$app_dir/Caddyfile"
    else
        log_warning "⚠️  Caddyfile not found"
    fi

    # Test connectivity
    echo ""
    log_info "🌐 Testing connectivity:"
    _test_connectivity "$app_name" "$DOMAIN"
}

connection_fix() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: connection_fix <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        display_validation_results
        return 1
    fi

    log_info "🔧 Fixing connection issues for app: $app_name"

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    local app_dir="$APPS_BASE_DIR/$app_name"
    local issues_fixed=0

    # Fix 1: Restart systemd service
    log_info "🔄 Restarting systemd service..."
    if systemctl restart "frankenphp-$app_name"; then
        log_info "✅ Service restarted successfully"
        issues_fixed=$((issues_fixed + 1))
    else
        log_error "❌ Failed to restart service"
    fi

    # Fix 2: Check and fix Caddyfile
    log_info "📄 Checking Caddyfile..."
    if [ ! -f "$app_dir/Caddyfile" ]; then
        log_info "Creating Caddyfile..."
        _create_caddyfile "$app_dir" "$DOMAIN"
        issues_fixed=$((issues_fixed + 1))
    fi

    # Fix 3: Check Laravel Octane
    log_info "🚀 Checking Laravel Octane..."
    cd "$app_dir"
    if ! php artisan list | grep -q "octane:start"; then
        log_info "Installing Laravel Octane..."
        octane_install "$app_dir"
        issues_fixed=$((issues_fixed + 1))
    fi

    # Fix 4: Check database connection
    log_info "🗄️  Checking database connection..."
    if ! timeout 10 php artisan tinker --execute="DB::connection()->getPdo(); echo 'DB OK';" 2>/dev/null | grep -q "DB OK"; then
        log_info "Fixing database connection..."
        load_module "database"
        fix_app_database "$app_name"
        issues_fixed=$((issues_fixed + 1))
    fi

    # Fix 5: Fix file permissions
    log_info "🔐 Fixing file permissions..."
    chown -R www-data:www-data "$app_dir"
    chmod -R 755 "$app_dir"
    chmod -R 777 "$app_dir/storage"
    chmod -R 777 "$app_dir/bootstrap/cache"
    issues_fixed=$((issues_fixed + 1))

    # Fix 6: Clear caches
    log_info "🧹 Clearing caches..."
    php artisan cache:clear
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear
    issues_fixed=$((issues_fixed + 1))

    # Final restart
    log_info "🔄 Final service restart..."
    systemctl restart "frankenphp-$app_name"

    log_info "✅ Connection fix completed! Fixed $issues_fixed issues"

    # Test connectivity after fix
    sleep 3
    connection_test "$app_name"
}

connection_test() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: connection_test <app-name>"
        return 1
    fi

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    log_info "🧪 Testing connectivity for app: $app_name"

    # Test local connection
    log_info "Testing local connection (port 8000)..."
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 | grep -q "200"; then
        log_info "✅ Local connection (port 8000) works"
    else
        log_warning "⚠️  Local connection (port 8000) failed"
    fi

    # Test domain connection
    log_info "Testing HTTP connection..."
    if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" | grep -q "200"; then
        log_info "✅ HTTP connection works"
    else
        log_warning "⚠️  HTTP connection failed"
    fi

    # Test HTTPS connection
    log_info "Testing HTTPS connection..."
    if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" | grep -q "200"; then
        log_info "✅ HTTPS connection works"
    else
        log_warning "⚠️  HTTPS connection failed"
    fi

    # Test response time
    log_info "Testing response time..."
    local response_time=$(curl -s -o /dev/null -w "%{time_total}" "http://$DOMAIN")
    log_info "⏱️  Response time: ${response_time}s"
}

# =============================================
# Native FrankenPHP Functions
# =============================================

connection_native_check() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: connection_native_check <app-name>"
        return 1
    fi

    log_info "🔍 Checking native FrankenPHP configuration: $app_name"

    local app_dir="$APPS_BASE_DIR/$app_name"
    local app_config="$CONFIG_DIR/$app_name.conf"

    # Load app config
    source "$app_config"

    # Check current systemd service
    local service_file="/etc/systemd/system/frankenphp-$app_name.service"
    if [ -f "$service_file" ]; then
        log_info "✅ Current systemd service exists"
        echo ""
        log_info "📋 Current service configuration:"
        cat "$service_file"
        echo ""
    else
        log_warning "⚠️  No systemd service found"
    fi

    # Check if service is running
    if systemctl is-active --quiet "frankenphp-$app_name"; then
        log_info "✅ Service is currently running"

        # Show current process
        log_info "🔄 Current running process:"
        ps aux | grep "$app_name" | grep -v grep || true

        # Show port usage
        log_info "🌐 Port usage:"
        netstat -tlnp | grep -E ":(80|443|8000)" || true

    else
        log_warning "⚠️  Service is not running"
    fi

    # Check Laravel Octane installation
    cd "$app_dir"
    if [ -f "artisan" ]; then
        log_info "✅ Laravel project found"

        # Check if Octane is installed
        if php artisan list | grep -q "octane:frankenphp"; then
            log_info "✅ Laravel Octane with FrankenPHP is installed"
        else
            log_warning "⚠️  Laravel Octane with FrankenPHP not found"
        fi

        # Check FrankenPHP binary
        if [ -f "frankenphp" ]; then
            log_info "✅ FrankenPHP binary found in app directory"
        else
            log_warning "⚠️  FrankenPHP binary not found in app directory"
        fi
    else
        log_error "❌ Not a Laravel project (artisan not found)"
    fi
}

connection_native_fix() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: connection_native_fix <app-name>"
        return 1
    fi

    log_info "🔧 Converting to native Laravel Octane FrankenPHP deployment: $app_name"

    local app_dir="$APPS_BASE_DIR/$app_name"
    local app_config="$CONFIG_DIR/$app_name.conf"

    # Load app config
    source "$app_config"

    # Stop current service
    log_info "🛑 Stopping current service..."
    systemctl stop "frankenphp-$app_name" || true

    # Install/update Laravel Octane
    cd "$app_dir"
    log_info "📦 Installing/updating Laravel Octane..."
    composer require laravel/octane
    php artisan octane:install --server=frankenphp

    # Download FrankenPHP binary if not exists
    if [ ! -f "frankenphp" ]; then
        log_info "📥 Downloading FrankenPHP binary..."
        curl -LO https://github.com/dunglas/frankenphp/releases/latest/download/frankenphp-linux-x86_64
        mv frankenphp-linux-x86_64 frankenphp
        chmod +x frankenphp
    fi

    # Create optimized systemd service
    log_info "⚙️  Creating optimized systemd service..."
    _create_native_systemd_service "$app_name" "$app_dir" "$DOMAIN"

    # Reload systemd and start service
    systemctl daemon-reload
    systemctl enable "frankenphp-$app_name"
    systemctl start "frankenphp-$app_name"

    log_info "✅ Native FrankenPHP deployment completed!"

    # Test the new deployment
    sleep 3
    connection_test "$app_name"
}

# =============================================
# Helper Functions
# =============================================

_check_port_status() {
    local port="$1"
    local service_name="$2"

    if netstat -tlnp | grep -q ":$port "; then
        log_info "✅ Port $port is listening ($service_name)"
    else
        log_warning "⚠️  Port $port is not listening ($service_name)"
    fi
}

_test_connectivity() {
    local app_name="$1"
    local domain="$2"

    # Test local connection
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 | grep -q "200"; then
        log_info "✅ Local connection (port 8000) works"
    else
        log_warning "⚠️  Local connection (port 8000) failed"
    fi

    # Test domain connection
    if curl -s -o /dev/null -w "%{http_code}" "http://$domain" | grep -q "200"; then
        log_info "✅ HTTP connection works"
    else
        log_warning "⚠️  HTTP connection failed"
    fi

    if curl -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q "200"; then
        log_info "✅ HTTPS connection works"
    else
        log_warning "⚠️  HTTPS connection failed"
    fi
}

_create_caddyfile() {
    local app_dir="$1"
    local domain="$2"

    cat > "$app_dir/Caddyfile" << EOF
{
    admin off
    log {
        output file /var/log/frankenphp/$app_name.log
        level INFO
    }
}

$domain {
    root * public

    # Enable compression
    encode gzip

    # Security headers
    header {
        # Enable HSTS
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        # XSS Protection
        X-XSS-Protection "1; mode=block"
        # Prevent content type sniffing
        X-Content-Type-Options "nosniff"
        # Referrer policy
        Referrer-Policy "strict-origin-when-cross-origin"
        # Frame options
        X-Frame-Options "SAMEORIGIN"
    }

    # FrankenPHP
    php_server
}
EOF

    log_info "✅ Caddyfile created successfully"
}

_create_native_systemd_service() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"

    cat > "/etc/systemd/system/frankenphp-$app_name.service" << EOF
[Unit]
Description=FrankenPHP Server for $app_name
After=network.target
Requires=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php artisan octane:frankenphp --host=0.0.0.0 --port=8000 --workers=4 --max-requests=1000
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$app_dir
ReadWritePaths=/var/log/frankenphp

# Environment
Environment=APP_ENV=production
Environment=APP_DEBUG=false
Environment=LOG_CHANNEL=stack

[Install]
WantedBy=multi-user.target
EOF

    log_info "✅ Native systemd service created"
}

# =============================================
# Connection Monitoring
# =============================================

connection_monitor() {
    local app_name="$1"
    local interval="${2:-30}"

    if [ -z "$app_name" ]; then
        log_error "Usage: connection_monitor <app-name> [interval]"
        return 1
    fi

    log_info "📊 Monitoring connection for app: $app_name (every ${interval}s)"
    log_info "Press Ctrl+C to stop monitoring"

    while true; do
        echo ""
        echo "$(date) - Connection Status:"
        connection_test "$app_name"
        sleep "$interval"
    done
}
