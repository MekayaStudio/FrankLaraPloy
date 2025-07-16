# FrankenPHP Multi-App Deployment System

Sistem deployment multi-aplikasi Laravel yang menggunakan FrankenPHP dengan dukungan Laravel Octane, load balancing, dan resource monitoring yang cerdas.

## 🚀 Fitur Utama

### 🔥 Laravel Octane + FrankenPHP
- **Embedded PHP Server**: Tidak memerlukan PHP-FPM
- **Built-in Caddy Web Server**: Reverse proxy otomatis
- **Auto HTTPS**: Let's Encrypt terintegrasi
- **Worker Optimization**: Kalkulasi thread optimal berdasarkan CPU/Memory
- **Apache/Nginx Removal**: Otomatis menghapus Apache/Nginx untuk mencegah konflik
- **Indonesia Mirror**: Menggunakan mirror server Indonesia untuk download lebih cepat

### 📈 Horizontal Scaling
- **Load Balancer**: Round-robin load balancing
- **Multi-Instance**: Scaling horizontal per aplikasi
- **Health Checks**: Monitoring kesehatan instance
- **Zero-Downtime**: Deployment tanpa downtime

### 🧠 Resource Awareness
- **Pre-flight Checks**: Validasi resource sebelum deployment
- **Smart Thread Allocation**: Optimasi berdasarkan kapasitas server
- **Resource Monitoring**: Real-time monitoring CPU/Memory
- **Capacity Planning**: Prediksi dampak perubahan

### 🔧 Multi-App Support
- **Isolated Apps**: Setiap app memiliki database dan konfigurasi terpisah
- **GitHub Integration**: Auto-deployment dari repository
- **Database Management**: MySQL database per app
- **Backup System**: Backup otomatis harian

## 📁 Struktur Project

```
scripts/
├── lib/                              # Modular libraries
│   ├── shared-functions.sh           # Common utilities
│   ├── error-handler.sh              # Error handling & rollback
│   ├── validation.sh                 # Comprehensive validation
│   ├── app-management.sh             # App lifecycle management
│   ├── octane-manager.sh             # Laravel Octane operations
│   ├── database-manager.sh           # Database operations
│   ├── systemd-manager.sh            # Service management
│   ├── ssl-manager.sh                # SSL/HTTPS management
│   ├── connection-manager.sh         # Connection troubleshooting
│   └── debug-manager.sh              # Testing and debugging
├── config/
│   └── frankenphp-config.conf        # System configuration
├── install.sh                       # 🆕 Main installer (refactored)
└── README.md                         # This documentation
```

## 🛠️ Instalasi

### Persyaratan Sistem

- **OS**: Ubuntu 24.04 LTS
- **RAM**: Minimum 1GB (recommended 2GB+)
- **Storage**: Minimum 5GB free space
- **Network**: Koneksi internet untuk download dependencies
- **User**: Root access required

### Quick Start

```bash
# Clone repository
git clone <repository-url>
cd scripts

# Setup sistem (one-time setup)
sudo ./install.sh setup

# Install aplikasi Laravel baru
./install.sh install web_sam example.com https://github.com/user/repo.git

# Atau quick install (setup + install sekaligus)
sudo ./install.sh quick web_sam example.com https://github.com/user/repo.git
```

## 📚 Penggunaan

### 1. Deployment Aplikasi Baru

```bash
# Dengan GitHub repository
./install.sh install web_sam testingsetup.rizqis.com https://github.com/CompleteLabs/web-app-sam.git

# Tanpa GitHub (manual deployment)
./install.sh install web_api api.completelabs.com

# Quick install (setup + install sekaligus)
sudo ./install.sh quick web_sam example.com https://github.com/user/repo.git
```

### 2. Laravel Octane Helper

```bash
# Install Laravel Octane + FrankenPHP
./install.sh octane:install /opt/laravel-apps/web_sam

# Start/Stop/Status server
./install.sh octane:start
./install.sh octane:stop
./install.sh octane:status

# Restart server
./install.sh octane:restart

# Optimize for production
./install.sh octane:optimize
```

### 3. Manajemen Aplikasi

```bash
# List semua aplikasi
./install.sh list

# Deploy ulang aplikasi
./install.sh deploy web_sam

# Status aplikasi
./install.sh status web_sam

# Remove aplikasi
./install.sh remove web_sam
```

### 4. Horizontal Scaling

```bash
# Scale up (tambah instance)
./install.sh scale web_sam up 8001
./install.sh scale web_sam up 8002

# Scale down (hapus instance)
./install.sh scale web_sam down 8002

# Check status scaling
./install.sh status web_sam
```

### 5. Resource Monitoring

```bash
# Monitor resource server
./install.sh monitor

# Debug system atau app
./install.sh debug
./install.sh debug web_sam

# Test components
./install.sh test

# Backup semua apps
./install.sh backup
```

## ⚙️ Konfigurasi

### File Konfigurasi Utama

**`config/frankenphp-config.conf`**
```bash
# Resource Management
MEMORY_SAFETY_MARGIN=20
CPU_SAFETY_MARGIN=25
MIN_MEMORY_PER_APP=512
MAX_MEMORY_PER_APP=2048
THREAD_MEMORY_USAGE=80
MAX_APPS_PER_SERVER=10

# FrankenPHP Configuration
DEFAULT_HTTP_PORT=80
DEFAULT_HTTPS_PORT=443
DEFAULT_OCTANE_PORT=8000

# Performance Settings
PHP_MEMORY_LIMIT="512M"
PHP_MAX_EXECUTION_TIME=300
OPCACHE_MEMORY_CONSUMPTION=256
```

### Konfigurasi Per-App

Setiap aplikasi memiliki file konfigurasi di `/etc/laravel-apps/`:

```bash
# /etc/laravel-apps/web_sam.conf
APP_NAME=web_sam
APP_DIR=/opt/laravel-apps/web_sam
DOMAIN=testingsetup.rizqis.com
DB_NAME=web_sam_db
DB_USER=web_sam_user
DB_PASS=generated_password
GITHUB_REPO=https://github.com/CompleteLabs/web-app-sam.git
CREATED_AT=2024-01-01 10:00:00
```

## 🔧 Advanced Usage

### Custom Environment Variables

```bash
# Enable debug mode
export DEBUG=true
./install.sh debug

# Skip pre-flight checks (development)
export SKIP_PREFLIGHT_CHECKS=true
./install.sh install test_app localhost
```

### Manual FrankenPHP Configuration

```bash
# Custom Caddyfile untuk load balancing
cat > /opt/laravel-apps/web_sam/Caddyfile <<EOF
{
    frankenphp {
        num_threads 8
    }
}

example.com {
    reverse_proxy {
        to localhost:8000
        to localhost:8001
        to localhost:8002
        lb_policy round_robin
        health_uri /health
        health_interval 30s
    }
}
EOF
```

### Database Management

```bash
# Manual database operations
source /root/.mysql_credentials
mysql -u root -p$MYSQL_ROOT_PASS

# Create database manually
CREATE DATABASE `new_app_db`;
CREATE USER 'new_app_user'@'localhost' IDENTIFIED BY 'secure_password';
GRANT ALL PRIVILEGES ON `new_app_db`.* TO 'new_app_user'@'localhost';
FLUSH PRIVILEGES;
```

## 🛡️ Security Best Practices

### 1. Systemd Security Settings

Secara default, systemd service menggunakan pengaturan keamanan yang fleksibel untuk kompatibilitas. Anda dapat mengubah ke mode strict di `config/frankenphp-config.conf`:

```bash
# Untuk keamanan strict (mungkin menyebabkan konflik pada beberapa sistem)
SYSTEMD_STRICT_SECURITY=true
SYSTEMD_PRIVATE_TMP=true
SYSTEMD_PRIVATE_DEVICES=true
SYSTEMD_PROTECT_SYSTEM=strict
SYSTEMD_PROTECT_HOME=true
SYSTEMD_NO_NEW_PRIVILEGES=true

# Untuk kompatibilitas maksimal (default)
SYSTEMD_STRICT_SECURITY=false
SYSTEMD_PRIVATE_TMP=false
SYSTEMD_PRIVATE_DEVICES=false
SYSTEMD_PROTECT_SYSTEM=false
SYSTEMD_PROTECT_HOME=false
SYSTEMD_NO_NEW_PRIVILEGES=false
```

### 2. Apache/Nginx Removal

Script otomatis menghapus Apache dan Nginx untuk mencegah konflik dengan FrankenPHP:

```bash
# Apache dan Nginx dihapus otomatis saat setup
# Termasuk:
# - apache2, apache2-bin, apache2-common, apache2-data, apache2-utils
# - nginx, nginx-common, nginx-core
# - libapache2-mod-php*
# - /etc/apache2, /etc/nginx, /var/www/html

# Cek apakah Apache/Nginx sudah dihapus
systemctl status apache2  # Should show "not found"
systemctl status nginx    # Should show "not found"
```

### 3. Indonesia Mirror Configuration

Script menggunakan mirror server Indonesia untuk download lebih cepat:

```bash
# Mirror yang digunakan (berurutan):
# 1. mirror.unej.ac.id (Universitas Jember)
# 2. buaya.klas.or.id (KLAS)
# 3. archive.ubuntu.com (fallback)

# Backup original sources.list disimpan di:
# /etc/apt/sources.list.backup
```

### 4. Firewall Configuration

```bash
# Firewall sudah dikonfigurasi otomatis
ufw status
# Status: active
# To                         Action      From
# --                         ------      ----
# 22/tcp                     ALLOW       Anywhere
# 80/tcp                     ALLOW       Anywhere
# 443/tcp                    ALLOW       Anywhere
```

### 2. File Permissions

```bash
# Permissions otomatis diatur
ls -la /opt/laravel-apps/web_sam/
# drwxr-xr-x www-data www-data
# -rw-r--r-- www-data www-data
```

### 3. SSL/TLS Configuration

```bash
# Enable HTTPS otomatis
enable-https-app web_sam

# Manual SSL configuration
# Edit Caddyfile dan ubah auto_https off menjadi auto_https on
```

## 📊 Monitoring & Logging

### Log Files

```bash
# Application logs
tail -f /var/log/frankenphp/web_sam.log

# Error logs
tail -f /var/log/frankenphp/error.log

# System logs
journalctl -u frankenphp-web_sam -f
```

### Resource Monitoring

```bash
# Real-time monitoring
watch -n 5 'monitor-server-resources'

# Detailed analysis
analyze-app-resources | grep -A 10 "web_sam"

# Performance metrics
htop
```

### Health Checks

```bash
# Check app health
curl http://localhost:8000/health

# Check all services
systemctl status frankenphp-web_sam
systemctl status mysql
systemctl status redis
```

## 🔄 Backup & Recovery

### Automated Backup

```bash
# Backup otomatis setiap hari jam 2 pagi
crontab -l | grep backup
# 0 2 * * * /usr/local/bin/backup-all-laravel-apps

# Manual backup
backup-all-laravel-apps
```

### Recovery Process

```bash
# Restore dari backup
cd /var/backups/laravel-apps/20240101_020000/

# Restore database
mysql -u root -p$MYSQL_ROOT_PASS web_sam_db < web_sam_database.sql

# Restore application files
tar -xzf web_sam_app.tar.gz -C /opt/laravel-apps/web_sam/
```

## 🐛 Troubleshooting

### Common Issues

**1. Systemd Namespace Issues (Exit Code 226/NAMESPACE)**

Jika service gagal dengan error `status=226/NAMESPACE`, gunakan fix script:

```bash
# Fix service tertentu
sudo ./fix-systemd-namespace.sh fix frankenphp-testing

# Fix semua frankenphp services
sudo ./fix-systemd-namespace.sh fix-all

# Check status service
sudo ./fix-systemd-namespace.sh check frankenphp-testing
```

**📋 Dokumentasi lengkap**: Lihat `SYSTEMD_NAMESPACE_FIX.md`

**2. FrankenPHP Binary Not Found**
```bash
# Debug installation
./install.sh debug

# Manual download
cd /opt/laravel-apps/web_sam
wget https://github.com/php/frankenphp/releases/download/v1.8.0/frankenphp-linux-x86_64
mv frankenphp-linux-x86_64 frankenphp
chmod +x frankenphp
```

**2. High Memory Usage**
```bash
# Check resource usage
monitor-server-resources

# Optimize thread allocation
optimize-server-resources

# Reduce workers per app
sed -i 's/OCTANE_WORKERS=8/OCTANE_WORKERS=4/' /opt/laravel-apps/web_sam/.env
systemctl restart frankenphp-web_sam
```

**3. Database Connection Issues**
```bash
# Test connection
mysql -u root -p$(cat /root/.mysql_credentials | cut -d'=' -f2)

# Reset MySQL password
mysql_secure_installation
```

**4. Port Already in Use**
```bash
# Check port usage
netstat -tulpn | grep :8000

# Kill process
sudo kill -9 $(lsof -t -i:8000)
```

### Error Recovery

```bash
# Rollback failed deployment
# System otomatis melakukan rollback jika terjadi error

# Manual rollback
remove-laravel-app failed_app
# Kemudian deploy ulang

# Check error logs
tail -f /var/log/frankenphp/error.log
```

## 📈 Performance Optimization

### 1. Thread Optimization

```bash
# System otomatis menghitung optimal threads
# Berdasarkan CPU cores dan memory available

# Manual optimization
CPU_CORES=$(nproc)
OPTIMAL_THREADS=$((CPU_CORES + 2))
echo "OCTANE_WORKERS=$OPTIMAL_THREADS" >> /opt/laravel-apps/web_sam/.env
```

### 2. Memory Management

```bash
# PHP memory optimization
echo "memory_limit = 512M" >> /etc/php/8.3/cli/conf.d/99-custom.ini

# OPcache optimization
echo "opcache.memory_consumption = 256" >> /etc/php/8.3/cli/conf.d/99-custom.ini
echo "opcache.max_accelerated_files = 20000" >> /etc/php/8.3/cli/conf.d/99-custom.ini
```

### 3. Database Optimization

```bash
# MySQL optimization
echo "innodb_buffer_pool_size = 1G" >> /etc/mysql/mysql.conf.d/mysqld.cnf
echo "query_cache_size = 128M" >> /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql
```

## 🤝 Contributing

### Development Setup

```bash
# Enable debug mode
export DEBUG=true
export VERBOSE_LOGGING=true

# Test validation
./lib/validation.sh

# Test error handling
./lib/error-handler.sh
```

### Code Structure

- **lib/shared-functions.sh**: Fungsi-fungsi umum yang digunakan bersama
- **lib/error-handler.sh**: Error handling dengan rollback mechanism
- **lib/validation.sh**: Validasi komprehensif untuk berbagai input
- **config/frankenphp-config.conf**: Konfigurasi sistem yang dapat disesuaikan

### Testing

```bash
# Test script dengan dry-run
SKIP_PREFLIGHT_CHECKS=true ./install.sh debug

# Test resource calculation
./install.sh monitor

# Test validation
echo "test_app" | ./lib/validation.sh validate_app_name
```

## 📄 License

MIT License - Lihat file LICENSE untuk detail lengkap.

## 🆘 Support

Untuk bantuan dan dukungan:

1. **Documentation**: Baca README ini dengan lengkap
2. **Debug**: Gunakan `./install.sh debug` untuk troubleshooting
3. **Monitoring**: Jalankan `./install.sh monitor` untuk analisis
4. **Logs**: Periksa `/var/log/frankenphp/` untuk error logs

## 🔮 Roadmap

### Version 2.1 (Planned)
- [ ] Docker support
- [ ] Kubernetes deployment
- [ ] Advanced monitoring dashboard
- [ ] Multi-server deployment
- [ ] Database clustering

### Version 2.2 (Future)
- [ ] Web UI management
- [ ] API endpoints
- [ ] Webhook integration
- [ ] Advanced security features
- [ ] Performance analytics

---

**Dibuat dengan ❤️ untuk deployment Laravel yang lebih mudah dan efisien**
