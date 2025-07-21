#!/bin/bash

# =============================================
# SSL Manager Library - FrankenPHP Automatic SSL
# FrankenPHP sudah built-in dengan automatic SSL/HTTPS
# File ini hanya untuk kompatibilitas API
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${SSL_MANAGER_LOADED:-}" ]; then
    return 0
fi
export SSL_MANAGER_LOADED=1

# =============================================
# SSL Information Functions (FrankenPHP automatic)
# =============================================

ssl_status() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: ssl_status <app-name>"
        return 1
    fi

    log_info "🔐 SSL Status for app: $app_name"
    log_info "✅ FrankenPHP handles SSL automatically"
    log_info "📋 Features:"
    log_info "   • Automatic certificate generation via Let's Encrypt"
    log_info "   • Auto-renewal (no cron jobs needed)"
    log_info "   • HTTP to HTTPS redirect"
    log_info "   • Modern TLS 1.2/1.3 protocols"
    log_info "   • HTTP/2 and HTTP/3 support"
    echo ""
    log_info "💡 No manual SSL configuration needed!"
}

ssl_info() {
    log_info "🔐 SSL Information - FrankenPHP Built-in"
    echo ""
    log_info "✅ Automatic Features:"
    log_info "   • Let's Encrypt certificate generation"
    log_info "   • Automatic certificate renewal"
    log_info "   • Modern TLS 1.2/1.3 support"
    log_info "   • HTTP/2 and HTTP/3 support"
    log_info "   • HSTS headers"
    log_info "   • Perfect Forward Secrecy"
    log_info "   • OCSP stapling"
    echo ""
    log_info "🔧 Requirements:"
    log_info "   • Domain must point to this server"
    log_info "   • Port 80 and 443 must be accessible"
    log_info "   • Valid domain (no localhost)"
    echo ""
    log_info "📝 Configuration:"
    log_info "   • Add domain to FrankenPHP configuration"
    log_info "   • SSL certificates are managed automatically"
}

# Legacy compatibility functions (no-op with info)
ssl_enable() {
    local app_name="$1"
    log_info "ℹ️  SSL is automatically enabled by FrankenPHP for app: $app_name"
    ssl_status "$app_name"
}

ssl_disable() {
    local app_name="$1"
    log_warning "⚠️  SSL cannot be disabled in FrankenPHP"
    log_info "🔒 FrankenPHP enforces HTTPS for security best practices"
}

ssl_renew() {
    local app_name="${1:-all}"
    log_info "ℹ️  SSL certificates are automatically renewed by FrankenPHP"
    log_info "✅ No manual renewal needed for: $app_name"
}
