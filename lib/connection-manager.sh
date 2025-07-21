#!/bin/bash

# =============================================
# Connection Manager Library
# Library untuk mengatasi masalah koneksi FrankenPHP
# Mengintegrasikan fix-frankenphp-connection.sh dan fix-octane-frankenphp-native.sh
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${CONNECTION_MANAGER_LOADED:-}" ]; then
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

    # Check ports for Laravel Octane
    _check_port_status "8000" "Laravel Octane"

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

    # Fix 2: Check Laravel Octane installation and ensure FrankenPHP
    log_info "🚀 Checking Laravel Octane + FrankenPHP..."
    cd "$app_dir"
    if ! php artisan list | grep -q "octane:frankenphp"; then
        log_info "Installing Laravel Octane with FrankenPHP..."
        composer require laravel/octane
        php artisan octane:install --server=frankenphp
        issues_fixed=$((issues_fixed + 1))
    fi

    # Fix 3: Check database connection
    log_info "🗄️  Checking database connection..."
    if ! timeout 10 php artisan tinker --execute="DB::connection()->getPdo(); echo 'DB OK';" 2>/dev/null | grep -q "DB OK"; then
        log_info "Fixing database connection..."
        load_module "database"
        fix_app_database "$app_name"
        issues_fixed=$((issues_fixed + 1))
    fi

    # Fix 4: Fix file permissions
    log_info "🔐 Fixing file permissions..."
    chown -R www-data:www-data "$app_dir"
    chmod -R 755 "$app_dir"
    chmod -R 777 "$app_dir/storage"
    chmod -R 777 "$app_dir/bootstrap/cache"
    issues_fixed=$((issues_fixed + 1))

    # Fix 5: Clear caches and optimize
    log_info "🧹 Clearing caches and optimizing..."
    php artisan cache:clear
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear
    # Optimize for production
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
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

    log_info "🧪 Testing Laravel Octane + FrankenPHP connectivity: $app_name"

    # Test Laravel Octane port
    log_info "Testing Laravel Octane (port 8000)..."
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 | grep -q "200"; then
        log_info "✅ Laravel Octane connection works"
    else
        log_warning "⚠️  Laravel Octane connection failed"
    fi

    # Test domain connection (FrankenPHP handles HTTP/HTTPS automatically)
    log_info "Testing domain connection..."
    if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" | grep -q "200"; then
        log_info "✅ HTTP connection works"
    else
        log_warning "⚠️  HTTP connection failed"
    fi

    # Test response time
    log_info "Testing response time..."
    local response_time=$(curl -s -o /dev/null -w "%{time_total}" "http://$DOMAIN" 2>/dev/null || echo "0")
    log_info "⏱️  Response time: ${response_time}s"
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

    # Test Laravel Octane connection
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000 | grep -q "200"; then
        log_info "✅ Laravel Octane connection works"
    else
        log_warning "⚠️  Laravel Octane connection failed"
    fi

    # Test domain connection (FrankenPHP handles routing)
    if curl -s -o /dev/null -w "%{http_code}" "http://$domain" | grep -q "200"; then
        log_info "✅ Domain connection works"
    else
        log_warning "⚠️  Domain connection failed"
    fi
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
