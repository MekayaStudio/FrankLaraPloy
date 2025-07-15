# Systemd Namespace Issues Fix Guide

## 🚨 Error: systemd service failed with exit code 226/NAMESPACE

Error ini terjadi ketika systemd security settings terlalu strict dan menyebabkan konflik namespace. Biasanya terlihat seperti:

```
● frankenphp-testing.service - Laravel Octane FrankenPHP Server for testing
     Loaded: loaded (/etc/systemd/system/frankenphp-testing.service; enabled)
     Active: activating (auto-restart) (Result: exit-code)
    Process: 64204 ExecStart=/usr/bin/php artisan octane:start --server=franken...
   Main PID: 64204 (code=exited, status=226/NAMESPACE)
```

## 🔍 Penyebab Masalah

Systemd security settings berikut menyebabkan namespace conflicts:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `ReadWritePaths=...`
- `ReadOnlyPaths=...`

## 🛠️ Solusi Cepat

### 1. Gunakan Fix Script (Recommended)

```bash
# Fix service tertentu
sudo ./fix-systemd-namespace.sh fix frankenphp-testing

# Fix semua frankenphp services
sudo ./fix-systemd-namespace.sh fix-all

# Check status service
sudo ./fix-systemd-namespace.sh check frankenphp-testing

# List semua services
sudo ./fix-systemd-namespace.sh list
```

### 2. Manual Fix

Jika script tidak tersedia, lakukan manual fix:

```bash
# 1. Edit service file
sudo nano /etc/systemd/system/frankenphp-testing.service

# 2. Hapus atau comment out baris berikut:
# NoNewPrivileges=true
# PrivateTmp=true
# PrivateDevices=true
# ProtectSystem=strict
# ProtectHome=true
# ReadWritePaths=...
# ReadOnlyPaths=...

# 3. Reload systemd dan restart service
sudo systemctl daemon-reload
sudo systemctl restart frankenphp-testing

# 4. Check status
sudo systemctl status frankenphp-testing
```

## 📋 Konfigurasi Service yang Benar

Service file yang sudah diperbaiki akan terlihat seperti ini:

```ini
[Unit]
Description=Laravel Octane FrankenPHP Server for testing
After=network.target mysql.service redis.service
Wants=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/laravel-apps/testing
ExecStart=/usr/bin/php artisan octane:start --server=frankenphp --host=0.0.0.0 --port=8000 --workers=4
ExecReload=/bin/kill -USR1 $MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=10
Restart=always
RestartSec=5
SyslogIdentifier=octane-testing

Environment=APP_ENV=production
Environment=APP_DEBUG=false

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768

# Security settings - disabled to prevent namespace conflicts
# NoNewPrivileges, PrivateTmp, ProtectSystem, ProtectHome disabled
# to avoid systemd namespace issues (exit code 226/NAMESPACE)

[Install]
WantedBy=multi-user.target
```

## 🔧 Troubleshooting Commands

```bash
# Check service status
sudo systemctl status frankenphp-testing

# Check logs
sudo journalctl -u frankenphp-testing -f

# Check for namespace errors
sudo journalctl -u frankenphp-testing | grep "226/NAMESPACE"

# Restart service
sudo systemctl restart frankenphp-testing

# Check if service is running
sudo systemctl is-active frankenphp-testing
```

## 📊 Verifikasi Fix

Setelah fix, service harus:

1. **Status**: `Active: active (running)`
2. **Logs**: Tidak ada error 226/NAMESPACE
3. **Process**: Laravel Octane berjalan normal
4. **Access**: Aplikasi dapat diakses melalui browser

```bash
# Check semua indikator
sudo systemctl status frankenphp-testing
curl -I http://localhost:8000
```

## 🔄 Untuk Service Baru

Mulai dari sekarang, semua service baru yang dibuat oleh system akan otomatis tanpa security settings yang bermasalah. File konfigurasi sudah diupdate:

**File: `config/frankenphp-config.conf`**
```bash
# Systemd Security Settings
# DISABLED by default to prevent namespace conflicts (exit code 226/NAMESPACE)
SYSTEMD_STRICT_SECURITY=false
SYSTEMD_PRIVATE_TMP=false
SYSTEMD_PRIVATE_DEVICES=false
SYSTEMD_PROTECT_SYSTEM=false
SYSTEMD_PROTECT_HOME=false
SYSTEMD_NO_NEW_PRIVILEGES=false
```

## 📝 Script Commands

**Fix Script Commands:**
```bash
# Help
sudo ./fix-systemd-namespace.sh help

# Fix specific service
sudo ./fix-systemd-namespace.sh fix frankenphp-testing

# Fix all services
sudo ./fix-systemd-namespace.sh fix-all

# Check service
sudo ./fix-systemd-namespace.sh check frankenphp-testing

# List all services
sudo ./fix-systemd-namespace.sh list
```

## 🎯 Expected Results

Setelah fix, Anda akan melihat:

```
● frankenphp-testing.service - Laravel Octane FrankenPHP Server for testing
     Loaded: loaded (/etc/systemd/system/frankenphp-testing.service; enabled)
     Active: active (running) since Tue 2025-07-15 15:45:00 UTC; 2min ago
   Main PID: 64500 (php)
      Tasks: 5 (limit: 4915)
     Memory: 45.2M
        CPU: 1.234s
     CGroup: /system.slice/frankenphp-testing.service
             └─64500 /usr/bin/php artisan octane:start --server=frankenphp...

Jul 15 15:45:00 server systemd[1]: Started Laravel Octane FrankenPHP Server for testing.
Jul 15 15:45:01 server php[64500]: Laravel Octane server started successfully.
```

## 🚨 Troubleshooting

Jika masih bermasalah setelah fix:

1. **Check PHP/Composer**: Pastikan PHP dan Composer berfungsi
2. **Check Permissions**: Pastikan www-data memiliki akses ke direktori
3. **Check Dependencies**: Pastikan Laravel Octane terinstall
4. **Check Ports**: Pastikan port 8000 tidak digunakan process lain

```bash
# Debug commands
php -v
composer --version
ls -la /opt/laravel-apps/testing
sudo -u www-data php /opt/laravel-apps/testing/artisan octane:start --help
sudo netstat -tlnp | grep :8000
```

Fix ini akan menyelesaikan masalah systemd namespace dan membuat service berjalan normal! 🚀 