# FrankenPHP Multi-App - Simple Usage Guide

## 🚀 One-Command Installation

Semua functionality sekarang tersedia dalam satu command: `./install.sh`

### Quick Start

```bash
# 1. Setup sistem (one-time)
sudo ./install.sh setup

# 2. Install aplikasi Laravel
./install.sh install web_sam example.com https://github.com/user/repo.git

# 3. Atau quick install (setup + install sekaligus)
sudo ./install.sh quick web_sam example.com https://github.com/user/repo.git
```

**Setup akan:**
- ✅ Konfigurasi mirror Indonesia (lebih cepat)
- ✅ Hapus Apache/Nginx (mencegah konflik)
- ✅ Install PHP 8.3 tanpa Apache
- ✅ Install dependencies lainnya

## 📋 Available Commands

### 🏗️ System Commands
```bash
./install.sh setup                    # Setup sistem
./install.sh install <app> <domain> [repo]  # Install app baru
./install.sh deploy <app>             # Deploy ulang app
./install.sh remove <app>             # Hapus app
```

### 🔧 Laravel Octane Commands
```bash
./install.sh octane:install [dir]     # Install Octane + FrankenPHP
./install.sh octane:start [dir]       # Start server
./install.sh octane:stop [dir]        # Stop server
./install.sh octane:restart [dir]     # Restart server
./install.sh octane:status [dir]      # Check status
./install.sh octane:optimize [dir]    # Optimize production
```

### 📊 Management Commands
```bash
./install.sh list                     # List semua apps
./install.sh status <app>             # Status app
./install.sh scale <app> <up|down> <port>  # Scale app
./install.sh monitor                  # Monitor resources
./install.sh backup                   # Backup semua apps
```

### 🔍 Debug Commands
```bash
./install.sh debug [app]              # Debug system/app
./install.sh test                     # Test components
```

## 🎯 Common Use Cases

### 1. Deploy Laravel App dari GitHub
```bash
# Setup sistem (jika belum)
sudo ./install.sh setup

# Install app
./install.sh install web_sam example.com https://github.com/user/laravel-app.git

# Check status
./install.sh status web_sam

# Visit: https://example.com
```

### 2. Manual Laravel Octane Setup
```bash
# Masuk ke direktori Laravel
cd /path/to/laravel-app

# Install Octane + FrankenPHP
./install.sh octane:install

# Start server
./install.sh octane:start

# Optimize untuk production
./install.sh octane:optimize
```

### 3. Scale Aplikasi
```bash
# Scale up (tambah instance)
./install.sh scale web_sam up 8001
./install.sh scale web_sam up 8002

# Check status
./install.sh status web_sam

# Scale down
./install.sh scale web_sam down 8002
```

### 4. Monitor & Debug
```bash
# Monitor resource server
./install.sh monitor

# Debug aplikasi
./install.sh debug web_sam

# Test semua components
./install.sh test
```

## 📁 File Structure

```
scripts/
├── install.sh                       # 🎯 Main command
├── lib/                             # Libraries
│   ├── shared-functions.sh          # Common functions
│   ├── error-handler.sh             # Error handling
│   └── validation.sh                # Validation
├── config/
│   └── frankenphp-config.conf       # Configuration
├── frankenphp-multiapp-deployer.sh  # System deployer
├── octane-helper.sh                 # Octane helper
└── README.md                        # Full documentation
```

## 🔧 Configuration

Edit `config/frankenphp-config.conf` untuk custom settings:

```bash
# Resource limits
MEMORY_SAFETY_MARGIN=20
MAX_APPS_PER_SERVER=10
THREAD_MEMORY_USAGE=80

# Performance
PHP_MEMORY_LIMIT="512M"
OPCACHE_MEMORY_CONSUMPTION=256
```

## 🆘 Troubleshooting

```bash
# Debug system
./install.sh debug

# Debug specific app
./install.sh debug web_sam

# Check logs
tail -f /var/log/frankenphp/web_sam.log

# Monitor resources
./install.sh monitor
```

### Systemd Security Conflicts

Jika ada konflik dengan pengaturan systemd, edit `config/frankenphp-config.conf`:

```bash
# Matikan strict security untuk kompatibilitas
SYSTEMD_STRICT_SECURITY=false
SYSTEMD_PRIVATE_TMP=false
SYSTEMD_PRIVATE_DEVICES=false
SYSTEMD_PROTECT_SYSTEM=false
SYSTEMD_PROTECT_HOME=false
```

### Database Access Problems

Jika ada error "Access denied for user":

```bash
# Cek status database
sudo ./install.sh db:status

# List semua apps dan status database
sudo ./install.sh db:list

# Fix database access untuk app tertentu
sudo ./install.sh db:fix web_sam

# Lihat panduan lengkap
cat DATABASE_TROUBLESHOOTING.md
```

## 🎉 That's It!

Sekarang semua command tersedia dalam satu file `install.sh`. Tidak perlu mengingat banyak script yang berbeda!

**Happy Coding!** 🚀 