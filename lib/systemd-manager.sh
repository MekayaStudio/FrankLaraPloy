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

# =============================================
# Systemd Service Functions
# =============================================

systemd_check_service() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_check_service <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
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

    # Check if service is enabled
    if systemctl is-enabled --quiet "$service_name"; then
        log_info "✅ Service is enabled (will start on boot)"
    else
        log_warning "⚠️  Service is not enabled"
    fi
}

systemd_fix_service() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_fix_service <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
    fi

    log_info "🔧 Fixing systemd service: $service_name"

    # Stop service if running
    log_info "🛑 Stopping service..."
    systemctl stop "$service_name" || true

    # Fix common issues
    local issues_fixed=0

    # Fix 1: Reload systemd daemon
    log_info "🔄 Reloading systemd daemon..."
    systemctl daemon-reload
    issues_fixed=$((issues_fixed + 1))

    # Fix 2: Reset failed state
    log_info "🧹 Resetting failed state..."
    systemctl reset-failed "$service_name" || true
    issues_fixed=$((issues_fixed + 1))

    # Fix 3: Check service file permissions
    local service_file="/etc/systemd/system/$service_name.service"
    if [ -f "$service_file" ]; then
        log_info "🔐 Fixing service file permissions..."
        chmod 644 "$service_file"
        issues_fixed=$((issues_fixed + 1))
    fi

    # Fix 4: Enable service
    log_info "⚙️  Enabling service..."
    systemctl enable "$service_name"
    issues_fixed=$((issues_fixed + 1))

    # Fix 5: Start service
    log_info "🚀 Starting service..."
    if systemctl start "$service_name"; then
        log_info "✅ Service started successfully"
        issues_fixed=$((issues_fixed + 1))
    else
        log_error "❌ Failed to start service"
        log_info "📋 Checking logs for errors..."
        journalctl -u "$service_name" -n 10 --no-pager
        return 1
    fi

    log_info "✅ Service fix completed! Fixed $issues_fixed issues"

    # Show final status
    systemctl status "$service_name" --no-pager -l
}

systemd_fix_all_services() {
    log_info "🔧 Fixing all FrankenPHP services..."

    local services_fixed=0
    local services_found=0

    # Find all frankenphp services
    for service_file in /etc/systemd/system/frankenphp-*.service; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file" .service)
            services_found=$((services_found + 1))

            log_info "Processing service: $service_name"
            if systemd_fix_service "$service_name"; then
                services_fixed=$((services_fixed + 1))
            fi
            echo ""
        fi
    done

    if [ $services_found -eq 0 ]; then
        log_info "No frankenphp services found to fix"
    else
        log_info "✅ Fixed $services_fixed out of $services_found services"
    fi
}

systemd_list_services() {
    log_info "📋 Listing all FrankenPHP services:"
    echo ""
    printf "%-30s %-15s %-10s %-15s\n" "Service" "Status" "Enabled" "App"
    echo "======================================================================="

    local services_found=0

    # Find all frankenphp services
    for service_file in /etc/systemd/system/frankenphp-*.service; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file" .service)
            local app_name=${service_name#frankenphp-}

            # Get service status
            local status="stopped"
            if systemctl is-active --quiet "$service_name"; then
                status="running"
            elif systemctl is-failed --quiet "$service_name"; then
                status="failed"
            fi

            # Get enabled status
            local enabled="disabled"
            if systemctl is-enabled --quiet "$service_name"; then
                enabled="enabled"
            fi

            printf "%-30s %-15s %-10s %-15s\n" "$service_name" "$status" "$enabled" "$app_name"
            services_found=$((services_found + 1))
        fi
    done

    if [ $services_found -eq 0 ]; then
        log_info "No FrankenPHP services found"
    else
        echo ""
        log_info "Total services: $services_found"
    fi
}

# =============================================
# Service Management Functions
# =============================================

systemd_start_service() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_start_service <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
    fi

    log_info "🚀 Starting service: $service_name"

    if systemctl start "$service_name"; then
        log_info "✅ Service started successfully"
        systemctl status "$service_name" --no-pager -l
    else
        log_error "❌ Failed to start service"
        journalctl -u "$service_name" -n 10 --no-pager
        return 1
    fi
}

systemd_stop_service() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_stop_service <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
    fi

    log_info "🛑 Stopping service: $service_name"

    if systemctl stop "$service_name"; then
        log_info "✅ Service stopped successfully"
    else
        log_error "❌ Failed to stop service"
        return 1
    fi
}

systemd_restart_service() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_restart_service <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
    fi

    log_info "🔄 Restarting service: $service_name"

    if systemctl restart "$service_name"; then
        log_info "✅ Service restarted successfully"
        systemctl status "$service_name" --no-pager -l
    else
        log_error "❌ Failed to restart service"
        journalctl -u "$service_name" -n 10 --no-pager
        return 1
    fi
}

systemd_enable_service() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_enable_service <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
    fi

    log_info "⚙️  Enabling service: $service_name"

    if systemctl enable "$service_name"; then
        log_info "✅ Service enabled successfully"
    else
        log_error "❌ Failed to enable service"
        return 1
    fi
}

systemd_disable_service() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_disable_service <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
    fi

    log_info "⚙️  Disabling service: $service_name"

    if systemctl disable "$service_name"; then
        log_info "✅ Service disabled successfully"
    else
        log_error "❌ Failed to disable service"
        return 1
    fi
}

# =============================================
# Service Creation Functions
# =============================================

create_frankenphp_service() {
    local app_name="$1"
    local app_dir="$2"
    local domain="$3"
    local port="${4:-8000}"

    if [ -z "$app_name" ] || [ -z "$app_dir" ] || [ -z "$domain" ]; then
        log_error "Usage: create_frankenphp_service <app-name> <app-dir> <domain> [port]"
        return 1
    fi

    local service_name="frankenphp-$app_name"
    local service_file="/etc/systemd/system/$service_name.service"

    log_info "📝 Creating systemd service: $service_name"

    cat > "$service_file" << EOF
[Unit]
Description=FrankenPHP Server for $app_name
After=network.target mysql.service
Requires=network.target
Wants=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$app_dir
ExecStart=/usr/bin/php artisan octane:start --server=frankenphp --host=0.0.0.0 --port=$port
ExecReload=/bin/kill -USR2 \$MAINPID
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
ReadWritePaths=/tmp

# Environment
Environment=APP_ENV=production
Environment=APP_DEBUG=false
Environment=LOG_CHANNEL=stack

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions
    chmod 644 "$service_file"

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$service_name"

    log_info "✅ Service created and enabled: $service_name"
    log_info "🚀 To start: systemctl start $service_name"
}

# =============================================
# Service Monitoring Functions
# =============================================

systemd_monitor_service() {
    local service_name="$1"
    local interval="${2:-5}"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_monitor_service <service-name> [interval]"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
    fi

    log_info "📊 Monitoring service: $service_name (every ${interval}s)"
    log_info "Press Ctrl+C to stop monitoring"

    while true; do
        clear
        echo "$(date) - Service Status for $service_name"
        echo "=================================================="
        systemctl status "$service_name" --no-pager -l
        echo ""
        echo "Recent logs:"
        journalctl -u "$service_name" -n 5 --no-pager
        sleep "$interval"
    done
}

systemd_logs_follow() {
    local service_name="$1"

    if [ -z "$service_name" ]; then
        log_error "Usage: systemd_logs_follow <service-name>"
        return 1
    fi

    # Handle service name variations
    if [[ "$service_name" != frankenphp-* ]]; then
        service_name="frankenphp-$service_name"
    fi

    log_info "📋 Following logs for service: $service_name"
    journalctl -u "$service_name" -f
}
