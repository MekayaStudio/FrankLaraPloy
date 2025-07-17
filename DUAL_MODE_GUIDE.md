# 🌐 HTTP/HTTPS Dual Mode Guide
## Panduan Lengkap untuk Laravel Octane dengan FrankenPHP

### 📋 Overview

Fitur **Dual Mode** memungkinkan aplikasi Laravel Octane berjalan secara bersamaan di port HTTP (80) dan HTTPS (443) **tanpa redirect otomatis**. Ini memberikan fleksibilitas maksimal untuk pengguna yang ingin mengakses aplikasi melalui kedua protokol.

### 🎯 Mode yang Tersedia

#### 1. **Dual Mode** (`dual`)
- ✅ HTTP (port 80) - **TANPA redirect**
- ✅ HTTPS (port 443) - dengan SSL/TLS
- ✅ Kedua service berjalan bersamaan
- ✅ User bisa akses via `http://domain.com` atau `https://domain.com`

#### 2. **HTTPS Only** (`https-only`)
- ❌ HTTP (port 80) - redirect ke HTTPS
- ✅ HTTPS (port 443) - dengan SSL/TLS
- ✅ Auto redirect dari HTTP ke HTTPS

#### 3. **HTTP Only** (`http-only`)
- ✅ HTTP (port 80) - tanpa SSL
- ❌ HTTPS (port 443) - tidak tersedia
- ⚠️ Tidak direkomendasikan untuk production

### 🚀 Cara Penggunaan

#### Instalasi Aplikasi Baru dengan Dual Mode

```bash
# Install aplikasi baru dengan dual mode
sudo ./install.sh install myapp example.com

# Setelah instalasi, konfigurasi dual mode
sudo ./install.sh octane:dual myapp dual
```

#### Konfigurasi Mode untuk Aplikasi Existing

```bash
# Konfigurasi dual mode (HTTP + HTTPS tanpa redirect)
sudo ./install.sh octane:dual myapp dual

# Konfigurasi HTTPS only (dengan redirect)
sudo ./install.sh octane:dual myapp https-only

# Konfigurasi HTTP only
sudo ./install.sh octane:dual myapp http-only
```

#### Manajemen Service

```bash
# Start services
sudo ./install.sh octane:start-dual myapp dual

# Stop services
sudo ./install.sh octane:stop-dual myapp dual

# Check status
sudo ./install.sh octane:status-dual myapp dual

# Restart services
sudo ./install.sh octane:restart-dual myapp dual
```

### 🔧 Konfigurasi Systemd Services

#### Dual Mode Services

**HTTPS Service** (`octane-myapp-https.service`):
```ini
[Service]
ExecStart=/usr/bin/php artisan octane:frankenphp --host=example.com --port=443 --https --workers=4 --max-requests=1000 --log-level=info
```

**HTTP Service** (`octane-myapp-http.service`):
```ini
[Service]
ExecStart=/usr/bin/php artisan octane:frankenphp --host=example.com --port=80 --workers=4 --max-requests=1000 --log-level=info
```

#### HTTPS Only Service

```ini
[Service]
ExecStart=/usr/bin/php artisan octane:frankenphp --host=example.com --port=443 --https --http-redirect --workers=4 --max-requests=1000 --log-level=info
```

#### HTTP Only Service

```ini
[Service]
ExecStart=/usr/bin/php artisan octane:frankenphp --host=example.com --port=80 --workers=4 --max-requests=1000 --log-level=info
```

### 🌐 Contoh Akses

#### Dual Mode
```bash
# Akses via HTTP (tanpa redirect)
curl http://example.com

# Akses via HTTPS
curl https://example.com

# Kedua URL akan memberikan response yang sama
```

#### HTTPS Only
```bash
# Akses via HTTP (akan redirect ke HTTPS)
curl -L http://example.com

# Akses via HTTPS
curl https://example.com
```

### 🔍 Monitoring dan Debugging

#### Check Service Status
```bash
# Check semua service
sudo ./install.sh octane:status-dual myapp dual

# Check service individual
sudo systemctl status octane-myapp-https
sudo systemctl status octane-myapp-http
```

#### Check Port Usage
```bash
# Check port 80 dan 443
sudo netstat -tlnp | grep -E ":(80|443)"

# Check process
ps aux | grep "octane:frankenphp"
```

#### Check Logs
```bash
# Laravel logs
sudo ./install.sh logs myapp

# Systemd logs
sudo journalctl -u octane-myapp-https -f
sudo journalctl -u octane-myapp-http -f
```

### ⚡ Performance Considerations

#### Resource Usage
- **Dual Mode**: Menggunakan 2x worker processes
- **Memory**: ~80MB per worker (default 4 workers = 320MB per service)
- **CPU**: Minimal overhead karena Laravel Octane yang efisien

#### Optimization Tips
```bash
# Adjust workers berdasarkan CPU cores
CPU_CORES=$(nproc)
OPTIMAL_WORKERS=$((CPU_CORES + 2))

# Update service configuration
sudo sed -i "s/--workers=4/--workers=$OPTIMAL_WORKERS/g" /etc/systemd/system/octane-myapp-*.service
sudo systemctl daemon-reload
sudo ./install.sh octane:restart-dual myapp dual
```

### 🔒 Security Considerations

#### SSL/TLS Configuration
- **Automatic**: Let's Encrypt certificates
- **Manual**: Custom certificates di `/var/lib/frankenphp/myapp/`
- **Renewal**: Automatic via FrankenPHP

#### Security Headers
```php
// Di Laravel middleware atau config
header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
```

### 🚨 Troubleshooting

#### Common Issues

**1. Port Already in Use**
```bash
# Check what's using the port
sudo lsof -i :80
sudo lsof -i :443

# Kill process if needed
sudo kill -9 $(lsof -t -i:80)
```

**2. Permission Issues**
```bash
# Fix capabilities
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/php

# Fix ownership
sudo chown -R www-data:www-data /opt/laravel-apps/myapp
```

**3. SSL Certificate Issues**
```bash
# Check certificate status
sudo ./install.sh ssl:status myapp

# Renew certificates
sudo ./install.sh ssl:renew myapp
```

**4. Service Won't Start**
```bash
# Check detailed logs
sudo journalctl -u octane-myapp-https --no-pager -l

# Test manual start
cd /opt/laravel-apps/myapp
sudo -u www-data php artisan octane:frankenphp --host=example.com --port=443 --https
```

### 📊 Migration Guide

#### Dari Single Mode ke Dual Mode

```bash
# 1. Backup current configuration
sudo cp /etc/systemd/system/octane-myapp.service /etc/systemd/system/octane-myapp.service.backup

# 2. Stop current service
sudo systemctl stop octane-myapp

# 3. Configure dual mode
sudo ./install.sh octane:dual myapp dual

# 4. Start dual mode services
sudo ./install.sh octane:start-dual myapp dual

# 5. Verify both services are running
sudo ./install.sh octane:status-dual myapp dual
```

#### Dari Dual Mode ke Single Mode

```bash
# 1. Stop dual mode services
sudo ./install.sh octane:stop-dual myapp dual

# 2. Configure single mode
sudo ./install.sh octane:dual myapp https-only

# 3. Start single service
sudo ./install.sh octane:start-dual myapp https-only
```

### 🎯 Best Practices

#### Production Setup
```bash
# 1. Install dengan dual mode
sudo ./install.sh install myapp example.com
sudo ./install.sh octane:dual myapp dual

# 2. Optimize workers
sudo ./install.sh optimize myapp

# 3. Setup monitoring
sudo ./install.sh monitor myapp

# 4. Setup backup
sudo ./install.sh backup:setup myapp
```

#### Development Setup
```bash
# 1. Install dengan HTTP only untuk development
sudo ./install.sh install myapp-dev dev.example.com
sudo ./install.sh octane:dual myapp-dev http-only

# 2. Enable debug mode
sudo ./install.sh debug myapp-dev
```

### 📝 Configuration Files

#### App Configuration
```bash
# Location: /etc/laravel-apps/myapp.conf
APP_NAME="myapp"
DOMAIN="example.com"
APP_DIR="/opt/laravel-apps/myapp"
OCTANE_MODE="dual"  # dual, https-only, http-only
```

#### Environment Variables
```bash
# Location: /opt/laravel-apps/myapp/.env
OCTANE_SERVER=frankenphp
OCTANE_HTTPS=true
OCTANE_MAX_REQUESTS=1000
APP_ENV=production
APP_DEBUG=false
```

### 🔄 Automation Scripts

#### Auto Switch Mode
```bash
#!/bin/bash
# Script untuk switch mode berdasarkan waktu

HOUR=$(date +%H)
APP_NAME="myapp"

if [ $HOUR -ge 8 ] && [ $HOUR -le 18 ]; then
    # Business hours: Dual mode
    sudo ./install.sh octane:dual $APP_NAME dual
else
    # Off hours: HTTPS only (save resources)
    sudo ./install.sh octane:dual $APP_NAME https-only
fi
```

#### Health Check Script
```bash
#!/bin/bash
# Script untuk health check dual mode

APP_NAME="myapp"
DOMAIN="example.com"

# Check HTTP
if curl -f http://$DOMAIN > /dev/null 2>&1; then
    echo "✅ HTTP OK"
else
    echo "❌ HTTP FAILED"
fi

# Check HTTPS
if curl -f https://$DOMAIN > /dev/null 2>&1; then
    echo "✅ HTTPS OK"
else
    echo "❌ HTTPS FAILED"
fi
```

### 📞 Support

Jika mengalami masalah dengan fitur dual mode:

1. **Check logs**: `sudo ./install.sh logs myapp`
2. **Debug mode**: `sudo ./install.sh debug myapp`
3. **Service status**: `sudo ./install.sh octane:status-dual myapp dual`
4. **System resources**: `sudo ./install.sh resources`

### 🎉 Kesimpulan

Fitur **Dual Mode** memberikan fleksibilitas maksimal untuk deployment Laravel Octane dengan FrankenPHP. Dengan konfigurasi yang tepat, Anda bisa menjalankan aplikasi di HTTP dan HTTPS secara bersamaan tanpa redirect otomatis, memberikan pengalaman yang optimal untuk berbagai skenario penggunaan. 