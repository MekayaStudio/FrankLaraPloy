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
    if systemctl start "laravel-octane-$app_name"; then
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
    if systemctl stop "laravel-octane-$app_name"; then
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
    if systemctl restart "laravel-octane-$app_name"; then
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
    systemctl status "laravel-octane-$app_name" --no-pager
}

octane_create_service() {
    local app_name="$1"
    local port="${2:-8000}"
    
    log_info "🔧 Creating Octane systemd service for app: $app_name"
    
    # Use systemd manager to create service
    create_octane_service "$app_name" "$port"
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
