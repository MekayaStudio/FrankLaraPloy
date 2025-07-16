#!/bin/bash

# =============================================
# Octane Manager Library
# Library untuk manajemen Laravel Octane
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "$OCTANE_MANAGER_LOADED" ]; then
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

    # Install Octane
    if ! composer require laravel/octane; then
        log_error "Failed to install Laravel Octane"
        return 1
    fi

    # Install Octane with FrankenPHP
    if ! php artisan octane:install --server=frankenphp; then
        log_error "Failed to install Octane with FrankenPHP"
        return 1
    fi

    # Download FrankenPHP binary if not exists
    if [ ! -f "frankenphp" ]; then
        log_info "📥 Downloading FrankenPHP binary..."
        if ! curl -LO https://github.com/dunglas/frankenphp/releases/latest/download/frankenphp-linux-x86_64; then
            log_error "Failed to download FrankenPHP binary"
            return 1
        fi

        mv frankenphp-linux-x86_64 frankenphp
        chmod +x frankenphp
    fi

    log_info "✅ Laravel Octane with FrankenPHP installed successfully!"
    log_info "🔧 To start server: php artisan octane:start --server=frankenphp"
    log_info "🔧 Or use: octane_start"
}

octane_start() {
    local target_dir="${1:-$(pwd)}"
    local host="${2:-0.0.0.0}"
    local port="${3:-8000}"

    if [ ! -d "$target_dir" ]; then
        log_error "Directory not found: $target_dir"
        return 1
    fi

    cd "$target_dir"

    # Check if it's a Laravel project with Octane
    if [ ! -f "artisan" ]; then
        log_error "Not a Laravel project (artisan not found)"
        return 1
    fi

    if ! php artisan list | grep -q "octane:start"; then
        log_error "Laravel Octane not installed. Run: octane_install"
        return 1
    fi

    log_info "🚀 Starting Octane server..."
    log_info "🌐 Server will be available at: http://$host:$port"

    # Start Octane server
    php artisan octane:start --server=frankenphp --host="$host" --port="$port"
}

octane_stop() {
    local target_dir="${1:-$(pwd)}"

    if [ ! -d "$target_dir" ]; then
        log_error "Directory not found: $target_dir"
        return 1
    fi

    cd "$target_dir"

    log_info "🛑 Stopping Octane server..."
    php artisan octane:stop || log_info "Server might already be stopped"

    log_info "✅ Octane server stopped"
}

octane_restart() {
    local target_dir="${1:-$(pwd)}"

    log_info "🔄 Restarting Octane server..."
    octane_stop "$target_dir"
    sleep 2
    octane_start "$target_dir"
}

octane_status() {
    local target_dir="${1:-$(pwd)}"

    if [ ! -d "$target_dir" ]; then
        log_error "Directory not found: $target_dir"
        return 1
    fi

    cd "$target_dir"

    log_info "📊 Checking Octane status..."

    # Check if Octane is installed
    if ! php artisan list | grep -q "octane:start"; then
        log_error "Laravel Octane not installed"
        return 1
    fi

    # Check if server is running
    if php artisan octane:status 2>/dev/null; then
        log_info "✅ Octane server is running"
    else
        log_info "⚠️  Octane server is not running"
    fi

    # Check process
    if pgrep -f "octane:start" > /dev/null; then
        log_info "✅ Octane process found"
        log_info "🔍 Process details:"
        ps aux | grep "octane:start" | grep -v grep
    else
        log_info "⚠️  No Octane process found"
    fi

    # Check port
    if netstat -tlnp 2>/dev/null | grep -q ":8000"; then
        log_info "✅ Port 8000 is listening"
    else
        log_info "⚠️  Port 8000 is not listening"
    fi
}

octane_optimize() {
    local target_dir="${1:-$(pwd)}"

    if [ ! -d "$target_dir" ]; then
        log_error "Directory not found: $target_dir"
        return 1
    fi

    cd "$target_dir"

    log_info "⚡ Optimizing Laravel for production..."

    # Clear caches
    php artisan cache:clear
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear

    # Optimize for production
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache

    # Optimize Composer autoload
    composer dump-autoload --optimize

    log_info "✅ Laravel optimization completed"
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

    # Check FrankenPHP binary
    if [ ! -f "frankenphp" ]; then
        log_warning "⚠️  FrankenPHP binary not found in current directory"
        issues=$((issues + 1))
    else
        log_info "✅ FrankenPHP binary found"
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
