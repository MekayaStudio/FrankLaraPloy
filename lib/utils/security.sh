#!/bin/bash

# =============================================
# Security Library
# Library untuk konfigurasi security
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${SECURITY_LOADED:-}" ]; then
    return 0
fi
export SECURITY_LOADED=1

# Load dependencies
if [ -z "${SHARED_FUNCTIONS_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/utils/shared-functions.sh"
fi
if [ -z "${ERROR_HANDLER_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/utils/error-handler.sh"
fi

# =============================================
# Security Configuration Functions
# =============================================

setup_security() {
    log_info "🛡️  Setting up security configurations..."
    
    # Setup firewall
    setup_firewall_rules
    
    # Setup fail2ban
    setup_fail2ban_rules
    
    # Secure SSH
    secure_ssh_config
    
    # Setup system security
    setup_system_security
    
    log_info "✅ Security setup completed"
}

setup_firewall_rules() {
    log_info "🔥 Configuring firewall rules..."
    
    # Reset UFW
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow MySQL only from localhost
    ufw allow from 127.0.0.1 to any port 3306
    
    # Allow Redis only from localhost
    ufw allow from 127.0.0.1 to any port 6379
    
    # Enable UFW
    ufw --force enable
    
    log_info "✅ Firewall rules configured"
}

setup_fail2ban_rules() {
    log_info "🔒 Setting up fail2ban protection..."
    
    # Configure fail2ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF
    
    # Enable and start fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_info "✅ Fail2ban configured"
}

secure_ssh_config() {
    log_info "🔐 Securing SSH configuration..."
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Apply security settings
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config
    
    # Add security settings
    cat >> /etc/ssh/sshd_config << 'EOF'

# Security settings
Protocol 2
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
EOF
    
    # Restart SSH service
    systemctl restart ssh
    
    log_info "✅ SSH security configured"
}

setup_system_security() {
    log_info "🛡️  Applying system security settings..."
    
    # Disable unnecessary services
    systemctl disable php*-fpm 2>/dev/null || true
    
    # Set file permissions
    chmod 640 /etc/passwd
    chmod 600 /etc/shadow
    chmod 644 /etc/group
    
    # Configure kernel parameters
    cat > /etc/sysctl.d/99-security.conf << 'EOF'
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 1

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
    
    # Apply kernel parameters
    sysctl -p /etc/sysctl.d/99-security.conf
    
    log_info "✅ System security configured"
}

check_security_status() {
    log_info "🔍 Checking security status..."
    
    echo "=== Firewall Status ==="
    ufw status
    echo ""
    
    echo "=== Fail2ban Status ==="
    fail2ban-client status
    echo ""
    
    echo "=== SSH Security ==="
    if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
        echo "✅ Root login disabled"
    else
        echo "❌ Root login enabled"
    fi
    
    if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
        echo "✅ Password authentication disabled"
    else
        echo "❌ Password authentication enabled"
    fi
    
    echo ""
    
    echo "=== Service Status ==="
    echo "SSH: $(systemctl is-active ssh)"
    echo "Fail2ban: $(systemctl is-active fail2ban)"
    echo "UFW: $(systemctl is-active ufw)"
    
    log_info "✅ Security status check completed"
}
