#!/bin/bash

# =============================================
# FrankenPHP Multi-App Deployer - Installer
# =============================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "${BLUE}$1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/frankenphp-deployer"

log_header "🚀 FrankenPHP Multi-App Deployer - Installer"
echo ""

# Cek root
if [ "$EUID" -ne 0 ]; then
    log_error "Jalankan sebagai root: sudo ./install.sh"
    exit 1
fi

# Cek file
required_files=(
    "frankenphp-multiapp-deployer-optimized.sh"
    "lib/config.sh"
    "lib/utils.sh"
    "lib/system_setup.sh"
    "lib/resource_management.sh"
    "lib/app_management.sh"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        log_error "File $file tidak ditemukan!"
        exit 1
    fi
done

# Install files
log_info "📦 Installing files..."
mkdir -p "$INSTALL_DIR/lib"
cp "$SCRIPT_DIR/frankenphp-multiapp-deployer-optimized.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/lib/"* "$INSTALL_DIR/lib/"
cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true
chmod +x "$INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh"
chmod +x "$INSTALL_DIR/lib/"*.sh

# Buat command shortcuts
log_info "🔧 Creating command shortcuts..."

# Main commands
cat > /usr/local/bin/frankenphp <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh "\$@"
EOF

cat > /usr/local/bin/frankenphp-setup <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh setup
EOF

cat > /usr/local/bin/create-laravel-app <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh create "\$@"
EOF

cat > /usr/local/bin/deploy-laravel-app <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh deploy "\$@"
EOF

cat > /usr/local/bin/list-laravel-apps <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh list
EOF

cat > /usr/local/bin/remove-laravel-app <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh remove "\$@"
EOF

cat > /usr/local/bin/status-laravel-app <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh status "\$@"
EOF

cat > /usr/local/bin/monitor-server-resources <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh monitor
EOF

cat > /usr/local/bin/analyze-app-resources <<EOF
#!/bin/bash
exec $INSTALL_DIR/frankenphp-multiapp-deployer-optimized.sh analyze
EOF

cat > /usr/local/bin/backup-all-laravel-apps <<EOF
#!/bin/bash
BACKUP_DIR="/var/backups/laravel-apps"
DATE=\$(date +%Y%m%d_%H%M%S)
mkdir -p \$BACKUP_DIR/\$DATE

echo "📦 Backing up all Laravel apps..."
for config in /etc/laravel-apps/*.conf; do
    if [ -f "\$config" ]; then
        source "\$config"
        echo "Backing up \$APP_NAME..."
        source /root/.mysql_credentials
        mysqldump -u root -p\$MYSQL_ROOT_PASS \\`\$DB_NAME\\` > \$BACKUP_DIR/\$DATE/\${APP_NAME}_database.sql
        tar -czf \$BACKUP_DIR/\$DATE/\${APP_NAME}_app.tar.gz -C \$APP_DIR .
        echo "✅ \$APP_NAME backed up"
    fi
done

find \$BACKUP_DIR -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \\;
echo "✅ All backups completed: \$DATE"
EOF

# Set permissions
chmod +x /usr/local/bin/frankenphp
chmod +x /usr/local/bin/frankenphp-setup
chmod +x /usr/local/bin/create-laravel-app
chmod +x /usr/local/bin/deploy-laravel-app
chmod +x /usr/local/bin/list-laravel-apps
chmod +x /usr/local/bin/remove-laravel-app
chmod +x /usr/local/bin/status-laravel-app
chmod +x /usr/local/bin/monitor-server-resources
chmod +x /usr/local/bin/analyze-app-resources
chmod +x /usr/local/bin/backup-all-laravel-apps

log_info "✅ Installation completed!"
echo ""
log_header "📚 AVAILABLE COMMANDS:"
echo ""
echo "   frankenphp-setup                    - Setup sistem"
echo "   create-laravel-app <name> <domain>  - Buat aplikasi"
echo "   deploy-laravel-app <name>           - Deploy aplikasi"
echo "   list-laravel-apps                   - List aplikasi"
echo "   status-laravel-app <name>           - Status aplikasi"
echo "   monitor-server-resources            - Monitor resource"
echo "   backup-all-laravel-apps             - Backup aplikasi"
echo ""
log_header "🚀 Ready to use! Run 'frankenphp-setup' to start." 