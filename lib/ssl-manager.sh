#!/bin/bash

# =============================================
# SSL Manager Library
# Library untuk manajemen SSL/HTTPS
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${SSL_MANAGER_LOADED:-}" ]; then
    return 0
fi
export SSL_MANAGER_LOADED=1

# =============================================
# SSL Certificate Functions
# =============================================

ssl_enable() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: ssl_enable <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        display_validation_results
        return 1
    fi

    log_info "🔐 Enabling HTTPS for app: $app_name"

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    local app_dir="$APPS_BASE_DIR/$app_name"

    # Check if domain is accessible
    if ! _check_domain_accessible "$DOMAIN"; then
        log_error "Domain $DOMAIN is not accessible. Please ensure DNS is configured properly."
        return 1
    fi

    # Install certbot if not installed
    if ! command -v certbot &> /dev/null; then
        log_info "📦 Installing certbot..."
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    fi

    # Stop services temporarily
    log_info "🛑 Stopping services temporarily..."
    systemctl stop "frankenphp-$app_name" || true
    systemctl stop nginx || true

    # Request SSL certificate
    log_info "📜 Requesting SSL certificate for $DOMAIN..."
    if certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email admin@"$DOMAIN"; then
        log_info "✅ SSL certificate obtained successfully"

        # Update Caddyfile with HTTPS
        _update_caddyfile_https "$app_dir" "$DOMAIN"

        # Restart service
        systemctl start "frankenphp-$app_name"

        log_info "✅ HTTPS enabled for $app_name"
        log_info "🌐 Visit: https://$DOMAIN"
    else
        log_error "❌ Failed to obtain SSL certificate"
        systemctl start "frankenphp-$app_name" || true
        return 1
    fi
}

ssl_disable() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: ssl_disable <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        display_validation_results
        return 1
    fi

    log_info "🔓 Disabling HTTPS for app: $app_name"

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    local app_dir="$APPS_BASE_DIR/$app_name"

    # Stop service
    systemctl stop "frankenphp-$app_name"

    # Update Caddyfile to HTTP only
    _update_caddyfile_http "$app_dir" "$DOMAIN"

    # Restart service
    systemctl start "frankenphp-$app_name"

    log_info "✅ HTTPS disabled for $app_name"
    log_info "🌐 Visit: http://$DOMAIN"
}

ssl_status() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: ssl_status <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        display_validation_results
        return 1
    fi

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    log_info "🔍 SSL Status for app: $app_name"
    log_info "🌐 Domain: $DOMAIN"
    echo ""

    # Check if SSL certificate exists
    local cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    if [ -f "$cert_path" ]; then
        log_info "✅ SSL certificate exists"

        # Check certificate validity
        local cert_info=$(openssl x509 -in "$cert_path" -text -noout)
        local expiry_date=$(echo "$cert_info" | grep "Not After" | cut -d: -f2- | xargs)
        local expiry_timestamp=$(date -d "$expiry_date" +%s)
        local current_timestamp=$(date +%s)
        local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))

        log_info "📅 Certificate expires: $expiry_date"
        log_info "⏰ Days until expiry: $days_until_expiry"

        if [ $days_until_expiry -lt 30 ]; then
            log_warning "⚠️  Certificate expires in less than 30 days!"
        fi

        # Test HTTPS connection
        if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" | grep -q "200"; then
            log_info "✅ HTTPS connection works"
        else
            log_warning "⚠️  HTTPS connection failed"
        fi
    else
        log_warning "⚠️  No SSL certificate found"
    fi

    # Check HTTP connection
    if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" | grep -q "200"; then
        log_info "✅ HTTP connection works"
    else
        log_warning "⚠️  HTTP connection failed"
    fi
}

ssl_renew() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: ssl_renew <app-name>"
        return 1
    fi

    # Validate app exists
    if ! validate_app_exists "$app_name"; then
        display_validation_results
        return 1
    fi

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    log_info "🔄 Renewing SSL certificate for app: $app_name"
    log_info "🌐 Domain: $DOMAIN"

    # Check if certificate exists
    local cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    if [ ! -f "$cert_path" ]; then
        log_error "No SSL certificate found. Use ssl_enable first."
        return 1
    fi

    # Renew certificate
    if certbot renew --cert-name "$DOMAIN" --quiet; then
        log_info "✅ SSL certificate renewed successfully"

        # Restart service to use new certificate
        systemctl restart "frankenphp-$app_name"

        log_info "✅ Service restarted with new certificate"
    else
        log_error "❌ Failed to renew SSL certificate"
        return 1
    fi
}

# =============================================
# SSL Management Functions
# =============================================

ssl_renew_all() {
    log_info "🔄 Renewing all SSL certificates..."

    if certbot renew --quiet; then
        log_info "✅ All SSL certificates renewed successfully"

        # Restart all FrankenPHP services
        log_info "🔄 Restarting all FrankenPHP services..."
        systemctl restart frankenphp-*.service

        log_info "✅ All services restarted"
    else
        log_error "❌ Failed to renew some SSL certificates"
        return 1
    fi
}

ssl_list_certificates() {
    log_info "📜 Listing all SSL certificates:"
    echo ""

    if command -v certbot &> /dev/null; then
        certbot certificates
    else
        log_info "Certbot not installed"
    fi
}

ssl_auto_renew_setup() {
    log_info "⚙️  Setting up automatic SSL certificate renewal..."

    # Create renewal script
    cat > /usr/local/bin/ssl-auto-renew.sh << 'EOF'
#!/bin/bash
# Auto-renewal script for SSL certificates

# Renew certificates
/usr/bin/certbot renew --quiet

# Restart FrankenPHP services if certificates were renewed
if [ $? -eq 0 ]; then
    systemctl restart frankenphp-*.service
fi
EOF

    chmod +x /usr/local/bin/ssl-auto-renew.sh

    # Create cron job
    cat > /etc/cron.d/ssl-auto-renew << EOF
# Auto-renewal for SSL certificates
0 3 * * * root /usr/local/bin/ssl-auto-renew.sh
EOF

    log_info "✅ Auto-renewal setup completed"
    log_info "🕐 Certificates will be checked daily at 3 AM"
}

# =============================================
# Helper Functions
# =============================================

_check_domain_accessible() {
    local domain="$1"

    # Check if domain resolves
    if ! nslookup "$domain" &> /dev/null; then
        return 1
    fi

    # Check if domain is accessible via HTTP
    if curl -s --max-time 10 "http://$domain" &> /dev/null; then
        return 0
    fi

    return 1
}

_update_caddyfile_https() {
    local app_dir="$1"
    local domain="$2"

    cat > "$app_dir/Caddyfile" << EOF
{
    admin off
    log {
        output file /var/log/frankenphp/\$APP_NAME.log
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

    # SSL configuration
    tls /etc/letsencrypt/live/$domain/fullchain.pem /etc/letsencrypt/live/$domain/privkey.pem

    # FrankenPHP
    php_server
}

# HTTP redirect to HTTPS
http://$domain {
    redir https://$domain{uri} permanent
}
EOF
}

_update_caddyfile_http() {
    local app_dir="$1"
    local domain="$2"

    cat > "$app_dir/Caddyfile" << EOF
{
    admin off
    log {
        output file /var/log/frankenphp/\$APP_NAME.log
        level INFO
    }
}

$domain {
    root * public

    # Enable compression
    encode gzip

    # Security headers
    header {
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
}

# =============================================
# SSL Testing Functions
# =============================================

ssl_test_connection() {
    local domain="$1"

    if [ -z "$domain" ]; then
        log_error "Usage: ssl_test_connection <domain>"
        return 1
    fi

    log_info "🧪 Testing SSL connection for: $domain"

    # Test SSL connection
    if openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        log_info "✅ SSL connection test passed"

        # Get certificate details
        local cert_details=$(openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | openssl x509 -text -noout)
        local issuer=$(echo "$cert_details" | grep "Issuer:" | cut -d: -f2- | xargs)
        local expiry=$(echo "$cert_details" | grep "Not After" | cut -d: -f2- | xargs)

        log_info "📜 Certificate Issuer: $issuer"
        log_info "📅 Certificate Expires: $expiry"
    else
        log_error "❌ SSL connection test failed"
        return 1
    fi
}

ssl_check_security() {
    local domain="$1"

    if [ -z "$domain" ]; then
        log_error "Usage: ssl_check_security <domain>"
        return 1
    fi

    log_info "🔒 Checking SSL security for: $domain"

    # Check SSL Labs rating (requires internet)
    if command -v curl &> /dev/null; then
        log_info "For detailed SSL analysis, visit:"
        log_info "https://www.ssllabs.com/ssltest/analyze.html?d=$domain"
    fi

    # Basic security checks
    local ssl_output=$(openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null)

    # Check protocol version
    if echo "$ssl_output" | grep -q "Protocol.*TLSv1.3"; then
        log_info "✅ Uses TLS 1.3 (excellent)"
    elif echo "$ssl_output" | grep -q "Protocol.*TLSv1.2"; then
        log_info "✅ Uses TLS 1.2 (good)"
    else
        log_warning "⚠️  Uses older TLS version (consider upgrading)"
    fi

    # Check cipher suite
    local cipher=$(echo "$ssl_output" | grep "Cipher.*:" | cut -d: -f2 | xargs)
    if [ -n "$cipher" ]; then
        log_info "🔐 Cipher Suite: $cipher"
    fi
}
