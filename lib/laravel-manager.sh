#!/bin/bash

# =============================================
# Laravel Manager Library - Core Functions Only
# Library untuk fungsi-fungsi core Laravel yang tidak tersedia di app-management.sh
# Fungsi yang tersedia: create_laravel_app, configure_laravel_env, run_laravel_migrations,
# optimize_laravel_app, setup_laravel_scheduler, setup_laravel_queue_worker, dll.
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${LARAVEL_MANAGER_LOADED:-}" ]; then
    return 0
fi
export LARAVEL_MANAGER_LOADED=1

# Load dependencies
if [ -z "${SHARED_FUNCTIONS_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/shared-functions.sh"
fi
if [ -z "${ERROR_HANDLER_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/error-handler.sh"
fi
if [ -z "${OCTANE_MANAGER_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/octane-manager.sh"
fi
if [ -z "${DATABASE_MANAGER_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/database-manager.sh"
fi
if [ -z "${SYSTEMD_MANAGER_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/systemd-manager.sh"
fi

# =============================================
# Laravel Installation Functions
# =============================================

create_laravel_app() {
    local app_name="$1"
    local domain="$2"
    local github_repo="${3:-}"
    
    log_info "🚀 Creating Laravel app: $app_name"
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    # Create app directory
    ensure_directory "$app_dir"
    
    if [ -n "$github_repo" ]; then
        # Clone from GitHub
        log_info "📥 Cloning from GitHub: $github_repo"
        cd "$app_dir"
        if ! git clone "$github_repo" .; then
            handle_error "Failed to clone repository: $github_repo" $ERROR_NETWORK
            return 1
        fi
        
        # Install dependencies
        log_info "📦 Installing Composer dependencies..."
        if ! composer install --no-dev --optimize-autoloader; then
            handle_error "Failed to install Composer dependencies" $ERROR_DEPENDENCY
            return 1
        fi
        
        # Install Node dependencies if package.json exists
        if [ -f "package.json" ]; then
            log_info "📦 Installing Node.js dependencies..."
            if ! npm install; then
                handle_error "Failed to install Node.js dependencies" $ERROR_DEPENDENCY
                return 1
            fi
            
            # Build assets
            log_info "🔨 Building assets..."
            if ! npm run build; then
                log_warning "Failed to build assets, continuing..."
            fi
        fi
    else
        # Create new Laravel project
        log_info "🆕 Creating new Laravel project..."
        cd / # Change to root directory first
        if ! composer create-project laravel/laravel "$app_dir"; then
            handle_error "Failed to create Laravel project" $ERROR_DEPENDENCY
            return 1
        fi
        cd "$app_dir"
    fi
    
    # Set proper permissions
    chown -R www-data:www-data "$app_dir"
    chmod -R 755 "$app_dir"
    chmod -R 775 "$app_dir/storage"
    chmod -R 775 "$app_dir/bootstrap/cache"
    
    log_info "✅ Laravel app created successfully"
}

configure_laravel_env() {
    local app_name="$1"
    local domain="$2"
    
    log_info "🔧 Configuring Laravel environment..."
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    local env_file="$app_dir/.env"
    
    # Copy .env.example if .env doesn't exist
    if [ ! -f "$env_file" ] && [ -f "$app_dir/.env.example" ]; then
        cp "$app_dir/.env.example" "$env_file"
    fi
    
    # Generate app key if not exists
    cd "$app_dir"
    if ! grep -q "APP_KEY=" "$env_file" || [ "$(grep APP_KEY= "$env_file" | cut -d'=' -f2)" = "" ]; then
        log_info "🔑 Generating application key..."
        php artisan key:generate --force
    fi
    
    # Configure environment variables
    sed -i "s/APP_NAME=.*/APP_NAME=\"$app_name\"/" "$env_file"
    sed -i "s/APP_URL=.*/APP_URL=https:\/\/$domain/" "$env_file"
    sed -i "s/APP_ENV=.*/APP_ENV=production/" "$env_file"
    sed -i "s/APP_DEBUG=.*/APP_DEBUG=false/" "$env_file"
    
    # Configure database
    local db_password=$(setup_app_database "$app_name")
    sed -i "s/DB_CONNECTION=.*/DB_CONNECTION=mysql/" "$env_file"
    sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/" "$env_file"
    sed -i "s/DB_PORT=.*/DB_PORT=3306/" "$env_file"
    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$app_name/" "$env_file"
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$app_name/" "$env_file"
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_password/" "$env_file"
    
    # Configure Redis
    sed -i "s/REDIS_HOST=.*/REDIS_HOST=127.0.0.1/" "$env_file"
    sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD=null/" "$env_file"
    sed -i "s/REDIS_PORT=.*/REDIS_PORT=6379/" "$env_file"
    
    # Configure cache and session
    sed -i "s/CACHE_DRIVER=.*/CACHE_DRIVER=redis/" "$env_file"
    sed -i "s/SESSION_DRIVER=.*/SESSION_DRIVER=redis/" "$env_file"
    sed -i "s/QUEUE_CONNECTION=.*/QUEUE_CONNECTION=redis/" "$env_file"
    
    # Configure mail (basic setup)
    sed -i "s/MAIL_MAILER=.*/MAIL_MAILER=smtp/" "$env_file"
    sed -i "s/MAIL_HOST=.*/MAIL_HOST=localhost/" "$env_file"
    sed -i "s/MAIL_PORT=.*/MAIL_PORT=587/" "$env_file"
    sed -i "s/MAIL_ENCRYPTION=.*/MAIL_ENCRYPTION=tls/" "$env_file"
    sed -i "s/MAIL_FROM_ADDRESS=.*/MAIL_FROM_ADDRESS=noreply@$domain/" "$env_file"
    sed -i "s/MAIL_FROM_NAME=.*/MAIL_FROM_NAME=\"$app_name\"/" "$env_file"
    
    log_info "✅ Laravel environment configured"
}

run_laravel_migrations() {
    local app_name="$1"
    
    log_info "🗃️  Running Laravel migrations..."
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    cd "$app_dir"
    
    # Run migrations
    if ! php artisan migrate --force; then
        handle_error "Failed to run migrations" $ERROR_DATABASE
        return 1
    fi
    
    # Run seeders if available
    if [ -d "database/seeders" ] && [ "$(ls -A database/seeders)" ]; then
        log_info "🌱 Running database seeders..."
        if ! php artisan db:seed --force; then
            log_warning "Failed to run seeders, continuing..."
        fi
    fi
    
    log_info "✅ Laravel migrations completed"
}

optimize_laravel_app() {
    local app_name="$1"
    
    log_info "⚡ Optimizing Laravel application..."
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    cd "$app_dir"
    
    # Clear all caches first
    php artisan cache:clear
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear
    
    # Optimize for production
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    
    # Generate optimized autoloader
    composer dump-autoload --optimize
    
    log_info "✅ Laravel application optimized"
}

setup_laravel_scheduler() {
    local app_name="$1"
    
    log_info "⏰ Setting up Laravel scheduler..."
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    # Check if schedule:run is available
    if ! cd "$app_dir" && php artisan list | grep -q "schedule:run"; then
        log_info "📅 No scheduled tasks found, skipping scheduler setup"
        return 0
    fi
    
    # Add cron job for Laravel scheduler
    local cron_job="* * * * * cd $app_dir && php artisan schedule:run >> /dev/null 2>&1"
    
    # Check if cron job already exists
    if ! crontab -l 2>/dev/null | grep -q "$app_dir.*schedule:run"; then
        # Add cron job
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log_info "✅ Laravel scheduler cron job added"
    else
        log_info "✅ Laravel scheduler cron job already exists"
    fi
}

setup_laravel_queue_worker() {
    local app_name="$1"
    
    log_info "⚙️  Setting up Laravel queue worker..."
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    # Check if queue:work is available
    if ! cd "$app_dir" && php artisan list | grep -q "queue:work"; then
        log_info "📋 No queue configuration found, skipping queue worker setup"
        return 0
    fi
    
    # Create systemd service for queue worker
    create_queue_worker_service "$app_name"
    
    log_info "✅ Laravel queue worker configured"
}

remove_app() {
    local app_name="${1:-}"
    
    if [ -z "$app_name" ]; then
        handle_error "App name is required" $ERROR_VALIDATION
        return 1
    fi
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    if [ ! -d "$app_dir" ]; then
        handle_error "App '$app_name' not found" $ERROR_VALIDATION
        return 1
    fi
    
    log_info "🗑️  Removing Laravel app: $app_name"
    
    # Stop and disable services
    if systemctl is-active --quiet "laravel-octane-${app_name}"; then
        systemctl stop "laravel-octane-${app_name}"
    fi
    
    if systemctl is-enabled --quiet "laravel-octane-${app_name}"; then
        systemctl disable "laravel-octane-${app_name}"
    fi
    
    # Remove service files
    rm -f "/etc/systemd/system/laravel-octane-${app_name}.service"
    rm -f "/etc/systemd/system/laravel-queue-${app_name}.service"
    
    # Reload systemd
    systemctl daemon-reload
    
    # Remove cron job
    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v "$app_dir" > "$temp_cron"
    crontab "$temp_cron"
    rm -f "$temp_cron"
    
    # Remove database and user
    remove_app_database "$app_name"
    
    # Remove application directory
    rm -rf "$app_dir"
    
    # Remove logs
    rm -rf "$LOG_DIR/$app_name"
    
    log_info "✅ Laravel app '$app_name' removed successfully"
}

logs_app() {
    local app_name="${1:-}"
    local lines="${2:-50}"
    
    if [ -z "$app_name" ]; then
        handle_error "App name is required" $ERROR_VALIDATION
        return 1
    fi
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    
    if [ ! -d "$app_dir" ]; then
        handle_error "App '$app_name' not found" $ERROR_VALIDATION
        return 1
    fi
    
    log_info "📋 Logs for Laravel app: $app_name (last $lines lines)"
    echo ""
    
    # Laravel logs
    local laravel_log="$app_dir/storage/logs/laravel.log"
    if [ -f "$laravel_log" ]; then
        echo "=== Laravel Application Logs ==="
        tail -n "$lines" "$laravel_log"
        echo ""
    fi
    
    # Octane service logs
    echo "=== Octane Service Logs ==="
    journalctl -u "laravel-octane-${app_name}" -n "$lines" --no-pager
    echo ""
    
    # Queue worker logs (if exists)
    if systemctl list-unit-files | grep -q "laravel-queue-${app_name}"; then
        echo "=== Queue Worker Logs ==="
        journalctl -u "laravel-queue-${app_name}" -n "$lines" --no-pager
        echo ""
    fi
}
