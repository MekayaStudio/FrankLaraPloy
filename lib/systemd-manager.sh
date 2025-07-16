#!/bin/bash

# =============================================
# Systemd Manager Library
# Library untuk manajemen systemd services
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "$SYSTEMD_MANAGER_LOADED" ]; then
    return 0
fi
export SYSTEMD_MANAGER_LOADED=1

# Load dependencies
if [ -z "$SHARED_FUNCTIONS_LOADED" ]; then
    source "$SCRIPT_DIR/lib/shared-functions.sh"
fi
if [ -z "$ERROR_HANDLER_LOADED" ]; then
    source "$SCRIPT_DIR/lib/error-handler.sh"
fi

# =============================================
# Systemd Service Functions
# =============================================

create_octane_service() {
    local app_name="$1"
    local port="${2:-8000}"
    
    log_info "🔧 Creating Octane systemd service for app: $app_name"
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    local service_file="/etc/systemd/system/laravel-octane-${app_name}.service"
    
    # Create service file
    cat > "$service_file" << EOF
[Unit]
Description=Laravel Octane Server for $app_name
After=network.target
Requires=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php $app_dir/artisan octane:start --server=frankenphp --host=127.0.0.1 --port=$port
ExecReload=/bin/kill -USR2 \$MAINPID
KillMode=mixed
Restart=on-failure
RestartSec=10
TimeoutStopSec=30

# Environment variables
Environment=APP_ENV=production
Environment=APP_DEBUG=false

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$app_dir/storage $app_dir/bootstrap/cache
ProtectHome=true

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=laravel-octane-$app_name

[Install]
WantedBy=multi-user.target
EOF
    
    # Set permissions
    chmod 644 "$service_file"
    
    # Reload systemd
    systemctl daemon-reload
    
    log_info "✅ Octane service created: laravel-octane-$app_name"
}

create_queue_worker_service() {
    local app_name="$1"
    
    log_info "🔧 Creating queue worker systemd service for app: $app_name"
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    local service_file="/etc/systemd/system/laravel-queue-${app_name}.service"
    
    # Create service file
    cat > "$service_file" << EOF
[Unit]
Description=Laravel Queue Worker for $app_name
After=network.target
Requires=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php $app_dir/artisan queue:work --sleep=3 --tries=3 --timeout=90
ExecReload=/bin/kill -USR2 \$MAINPID
KillMode=mixed
Restart=on-failure
RestartSec=10
TimeoutStopSec=30

# Environment variables
Environment=APP_ENV=production
Environment=APP_DEBUG=false

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$app_dir/storage $app_dir/bootstrap/cache
ProtectHome=true

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=laravel-queue-$app_name

[Install]
WantedBy=multi-user.target
EOF
    
    # Set permissions
    chmod 644 "$service_file"
    
    # Reload systemd
    systemctl daemon-reload
    
    log_info "✅ Queue worker service created: laravel-queue-$app_name"
}

systemd_check_service() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_check_service <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != laravel-* ]]; then
        service_name="laravel-octane-$service_name"
    fi

    log_info "🔍 Checking service: $service_name"
    echo ""

    # Check if service file exists
    local service_file="/etc/systemd/system/$service_name.service"
    if [ ! -f "$service_file" ]; then
        log_error "Service file not found: $service_file"
        return 1
    fi
    log_info "✅ Service file exists"

    # Show service status
    log_info "📊 Service Status:"
    systemctl status "$service_name" --no-pager -l

    # Show recent logs
    echo ""
    log_info "📋 Recent logs (last 20 lines):"
    journalctl -u "$service_name" -n 20 --no-pager

    return 0
}

systemd_fix_service() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "Usage: systemd_fix_service <app-name>"
        return 1
    fi
    
    log_info "🔧 Fixing systemd service for app: $app_name"
    
    local app_dir="$APPS_BASE_DIR/$app_name"
    if [ ! -d "$app_dir" ]; then
        handle_error "App directory not found: $app_dir" $ERROR_FILESYSTEM
        return 1
    fi
    
    # Stop services
    systemctl stop "laravel-octane-$app_name" 2>/dev/null || true
    systemctl stop "laravel-queue-$app_name" 2>/dev/null || true
    
    # Remove old service files
    rm -f "/etc/systemd/system/laravel-octane-$app_name.service"
    rm -f "/etc/systemd/system/laravel-queue-$app_name.service"
    
    # Reload systemd
    systemctl daemon-reload
    
    # Recreate services
    create_octane_service "$app_name"
    create_queue_worker_service "$app_name"
    
    # Enable and start services
    systemctl enable "laravel-octane-$app_name"
    systemctl start "laravel-octane-$app_name"
    
    # Enable queue worker if it has queue configuration
    if cd "$app_dir" && php artisan list | grep -q "queue:work"; then
        systemctl enable "laravel-queue-$app_name"
        systemctl start "laravel-queue-$app_name"
    fi
    
    log_info "✅ Service fixed for app: $app_name"
}

systemd_fix_all_services() {
    log_info "🔧 Fixing all systemd services..."
    
    if [ ! -d "$APPS_BASE_DIR" ]; then
        log_error "Apps directory not found: $APPS_BASE_DIR"
        return 1
    fi
    
    local fixed_count=0
    
    for app_dir in "$APPS_BASE_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            log_info "🔧 Fixing service for app: $app_name"
            
            if systemd_fix_service "$app_name"; then
                ((fixed_count++))
            fi
        fi
    done
    
    log_info "✅ Fixed $fixed_count services"
}

systemd_list_services() {
    log_info "📋 Laravel Octane systemd services:"
    
    echo ""
    printf "%-30s %-10s %-10s %-s\n" "SERVICE NAME" "STATUS" "ENABLED" "DESCRIPTION"
    printf "%-30s %-10s %-10s %-s\n" "------------" "------" "-------" "-----------"
    
    # List all Laravel Octane services
    for service_file in /etc/systemd/system/laravel-octane-*.service; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file" .service)
            local app_name=${service_name#laravel-octane-}
            
            # Get service status
            local status="inactive"
            if systemctl is-active --quiet "$service_name"; then
                status="active"
            fi
            
            # Get enabled status
            local enabled="disabled"
            if systemctl is-enabled --quiet "$service_name"; then
                enabled="enabled"
            fi
            
            printf "%-30s %-10s %-10s %-s\n" "$service_name" "$status" "$enabled" "Laravel Octane for $app_name"
        fi
    done
    
    # List all Laravel Queue services
    for service_file in /etc/systemd/system/laravel-queue-*.service; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file" .service)
            local app_name=${service_name#laravel-queue-}
            
            # Get service status
            local status="inactive"
            if systemctl is-active --quiet "$service_name"; then
                status="active"
            fi
            
            # Get enabled status
            local enabled="disabled"
            if systemctl is-enabled --quiet "$service_name"; then
                enabled="enabled"
            fi
            
            printf "%-30s %-10s %-10s %-s\n" "$service_name" "$status" "$enabled" "Laravel Queue for $app_name"
        fi
    done
    
    echo ""
}

restart_app_services() {
    local app_name="$1"
    
    log_info "🔄 Restarting services for app: $app_name"
    
    # Restart Octane service
    if systemctl is-active --quiet "laravel-octane-$app_name"; then
        systemctl restart "laravel-octane-$app_name"
        log_info "✅ Restarted Octane service"
    fi
    
    # Restart Queue service
    if systemctl is-active --quiet "laravel-queue-$app_name"; then
        systemctl restart "laravel-queue-$app_name"
        log_info "✅ Restarted Queue service"
    fi
}

stop_app_services() {
    local app_name="$1"
    
    log_info "🛑 Stopping services for app: $app_name"
    
    # Stop Octane service
    if systemctl is-active --quiet "laravel-octane-$app_name"; then
        systemctl stop "laravel-octane-$app_name"
        log_info "✅ Stopped Octane service"
    fi
    
    # Stop Queue service
    if systemctl is-active --quiet "laravel-queue-$app_name"; then
        systemctl stop "laravel-queue-$app_name"
        log_info "✅ Stopped Queue service"
    fi
}

start_app_services() {
    local app_name="$1"
    
    log_info "▶️  Starting services for app: $app_name"
    
    # Start Octane service
    if systemctl is-enabled --quiet "laravel-octane-$app_name"; then
        systemctl start "laravel-octane-$app_name"
        log_info "✅ Started Octane service"
    fi
    
    # Start Queue service
    if systemctl is-enabled --quiet "laravel-queue-$app_name"; then
        systemctl start "laravel-queue-$app_name"
        log_info "✅ Started Queue service"
    fi
}

# =============================================
# Service Monitoring Functions
# =============================================

monitor_service_health() {
    local service_name="$1"
    local max_failures="${2:-3}"
    
    log_info "👁️  Monitoring service health: $service_name"
    
    local failure_count=0
    local check_interval=30
    
    while true; do
        if systemctl is-active --quiet "$service_name"; then
            if [ $failure_count -gt 0 ]; then
                log_info "✅ Service $service_name is healthy again"
                failure_count=0
            fi
        else
            ((failure_count++))
            log_warning "⚠️  Service $service_name is not running (failure $failure_count/$max_failures)"
            
            if [ $failure_count -ge $max_failures ]; then
                log_error "❌ Service $service_name has failed $max_failures times"
                # Attempt to restart
                systemctl restart "$service_name"
                failure_count=0
            fi
        fi
        
        sleep $check_interval
    done
}

get_service_port() {
    local app_name="$1"
    
    local service_file="/etc/systemd/system/laravel-octane-$app_name.service"
    if [ -f "$service_file" ]; then
        # Extract port from service file
        local port=$(grep -o '\--port=[0-9]\+' "$service_file" | cut -d'=' -f2)
        echo "${port:-8000}"
    else
        echo "8000"
    fi
}

# =============================================
# Service Cleanup Functions
# =============================================

cleanup_orphaned_services() {
    log_info "🧹 Cleaning up orphaned services..."
    
    local cleaned_count=0
    
    # Check Laravel Octane services
    for service_file in /etc/systemd/system/laravel-octane-*.service; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file" .service)
            local app_name=${service_name#laravel-octane-}
            
            # Check if app directory exists
            if [ ! -d "$APPS_BASE_DIR/$app_name" ]; then
                log_info "🗑️  Removing orphaned service: $service_name"
                systemctl stop "$service_name" 2>/dev/null || true
                systemctl disable "$service_name" 2>/dev/null || true
                rm -f "$service_file"
                ((cleaned_count++))
            fi
        fi
    done
    
    # Check Laravel Queue services
    for service_file in /etc/systemd/system/laravel-queue-*.service; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file" .service)
            local app_name=${service_name#laravel-queue-}
            
            # Check if app directory exists
            if [ ! -d "$APPS_BASE_DIR/$app_name" ]; then
                log_info "🗑️  Removing orphaned service: $service_name"
                systemctl stop "$service_name" 2>/dev/null || true
                systemctl disable "$service_name" 2>/dev/null || true
                rm -f "$service_file"
                ((cleaned_count++))
            fi
        fi
    done
    
    if [ $cleaned_count -gt 0 ]; then
        systemctl daemon-reload
        log_info "✅ Cleaned up $cleaned_count orphaned services"
    else
        log_info "✅ No orphaned services found"
    fi
}
