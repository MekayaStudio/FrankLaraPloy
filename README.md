# FrankenPHP Multi-App Deployer dengan Laravel Octane

Script deployment otomatis untuk multiple Laravel apps menggunakan FrankenPHP dengan dukungan penuh Laravel Octane.

## 🚀 Fitur Utama

### Laravel Octane Integration
- **Automatic Detection**: Script secara otomatis mendeteksi Laravel apps dan menggunakan Laravel Octane
- **FrankenPHP Binary Management**: Otomatis download FrankenPHP binary via Laravel Octane
- **Smart Configuration**: Konfigurasi optimal berdasarkan resource server
- **Fallback Support**: Mendukung non-Laravel apps dengan standalone FrankenPHP

### Deployment Modes
- **🔥 Laravel Apps**: Menggunakan Laravel Octane + FrankenPHP untuk performa optimal
- **📁 Non-Laravel Apps**: Fallback ke standalone FrankenPHP
- **🔄 Mixed Environment**: Mendukung kedua mode secara bersamaan

### Resource Management
- **🛡️ Pre-flight Checks**: Mencegah resource overcommitment
- **🧠 Smart Worker Allocation**: Alokasi worker berdasarkan kapasitas server
- **⚠️ Warning System**: Sistem peringatan untuk threshold resource
- **📊 Real-time Monitoring**: Monitoring resource secara real-time

## 📦 Instalasi

### 1. Download Script
```bash
wget https://raw.githubusercontent.com/user/repo/main/frankenphp-multiapp-deployer.sh
chmod +x frankenphp-multiapp-deployer.sh
```

### 2. Jalankan Setup
```bash
sudo ./frankenphp-multiapp-deployer.sh
```

### 3. Download Octane Helper
```bash
wget https://raw.githubusercontent.com/user/repo/main/octane-helper.sh
chmod +x octane-helper.sh
```

## 🔧 Penggunaan

### Membuat Laravel App dengan Octane
```bash
# Otomatis menggunakan Laravel Octane jika app Laravel terdeteksi
create-laravel-app web_sam testingsetup.rizqis.com https://github.com/CompleteLabs/web-app-sam.git

# Script akan:
# 1. Clone repository
# 2. Install Laravel Octane
# 3. Download FrankenPHP binary via Octane
# 4. Konfigurasi optimal workers
# 5. Setup reverse proxy dengan Caddy
# 6. Buat systemd service untuk Octane
```

### Laravel Octane Helper Commands
```bash
# Install Octane pada Laravel app yang sudah ada
./octane-helper.sh install /opt/laravel-apps/web_sam

# Konfigurasi optimal untuk Octane
./octane-helper.sh configure .

# Start Octane server
./octane-helper.sh start

# Stop Octane server  
./octane-helper.sh stop

# Check status server
./octane-helper.sh status

# Optimize Laravel app untuk Octane
./octane-helper.sh optimize
```

### Management Commands
```bash
# List semua apps
list-laravel-apps

# Deploy ulang app
deploy-laravel-app web_sam

# Scale horizontal
scale-laravel-app web_sam scale-up 8001
scale-laravel-app web_sam scale-down 8001

# Status app
status-laravel-app web_sam

# Remove app
remove-laravel-app web_sam
```

### Resource Monitoring
```bash
# Monitor resource server
monitor-server-resources

# Analisis resource per app
analyze-app-resources

# Prediksi impact perubahan
predict-resource-impact new-app web_new_app
predict-resource-impact scale-up web_sam

# Optimisasi resource
optimize-server-resources
```

## 🏗️ Arsitektur

### Laravel Octane Mode
```
Internet -> Caddy (Port 80/443) -> Laravel Octane (Port 8000) -> FrankenPHP Workers
```

### Standalone Mode
```
Internet -> Caddy (Port 80/443) -> FrankenPHP Direct Serve
```

### Load Balancer Mode
```
Internet -> Caddy Load Balancer -> Multiple Octane/FrankenPHP Instances
```

## 📊 Konfigurasi Optimal

### Worker Calculation
Script menghitung jumlah worker optimal berdasarkan:
- **CPU Cores**: Base calculation dari jumlah CPU
- **Memory Available**: Constraint berdasarkan memory tersedia
- **Existing Apps**: Adjustment berdasarkan jumlah app yang sudah ada
- **Safety Margins**: Reserve 20% memory dan 25% CPU

### Resource Allocation
- **Single Core**: 2 workers
- **Dual Core**: 3 workers  
- **Quad Core**: 5 workers
- **8 Cores**: 10 workers
- **16+ Cores**: 75% cores + 4 workers

## 🔄 Scaling

### Horizontal Scaling
```bash
# Scale up - tambah instance baru
scale-laravel-app web_sam scale-up 8001

# Load balancer otomatis dikonfigurasi:
# - Main instance: localhost:8000
# - New instance: localhost:8001
# - Round robin load balancing
# - Health checks
```

### Auto-scaling Features
- **Load Balancer**: Otomatis setup reverse proxy
- **Health Checks**: Monitoring kesehatan instance
- **Failover**: Automatic failover jika instance down
- **Session Affinity**: Sticky sessions jika diperlukan

## 📝 Konfigurasi Files

### Systemd Service (Laravel Octane)
```ini
[Unit]
Description=Laravel Octane FrankenPHP Server for web_sam
After=network.target mysql.service redis.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/laravel-apps/web_sam
ExecStart=/usr/bin/php artisan octane:start --server=frankenphp --host=0.0.0.0 --port=8000 --workers=8
Restart=always
```

### Caddyfile (Reverse Proxy)
```
testingsetup.rizqis.com {
    encode zstd gzip
    
    reverse_proxy localhost:8000 {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote}
        header_up X-Forwarded-For {http.request.remote}
        header_up X-Forwarded-Proto {http.request.scheme}
        
        health_uri /health
        health_interval 30s
        health_timeout 5s
    }
}
```

### Octane Configuration
```php
// config/octane.php
return [
    'server' => 'frankenphp',
    'servers' => [
        'frankenphp' => [
            'host' => '0.0.0.0',
            'port' => 8000,
            'workers' => 8,
            'max_requests' => 500,
        ],
    ],
    'garbage_collection' => [
        'enabled' => true,
        'app_memory' => 50,
        'reset_memory' => 100,
        'reset_requests' => 1000,
    ],
];
```

## 🚨 Troubleshooting

### Laravel Octane Issues
```bash
# Check Octane status
./octane-helper.sh status

# Restart Octane
systemctl restart frankenphp-web_sam

# Check logs
tail -f /var/log/frankenphp/web_sam.log

# Clear Octane cache
./octane-helper.sh optimize
```

### Resource Issues
```bash
# Check resource usage
monitor-server-resources

# Optimize resources
optimize-server-resources

# Check specific app
analyze-app-resources
```

### Performance Tuning
```bash
# Optimize PHP for Octane
# File: /etc/php/8.3/cli/conf.d/99-frankenphp-optimizations.ini
opcache.enable=1
opcache.enable_cli=1
memory_limit=512M
realpath_cache_size=4096k
```

## 📈 Performance Benefits

### Laravel Octane + FrankenPHP
- **10x Faster**: Dibandingkan dengan traditional PHP-FPM
- **Memory Efficient**: Shared memory antar workers
- **Persistent State**: Database connections, compiled views
- **Zero Cold Start**: Workers selalu warm
- **HTTP/2 Support**: Native HTTP/2 dan HTTP/3

### Resource Optimization
- **Smart Allocation**: Worker count berdasarkan resource
- **Garbage Collection**: Automatic memory management
- **Request Limiting**: Prevent memory leaks
- **Health Monitoring**: Automatic worker restart

## 🔐 Security

### Systemd Hardening
```ini
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/laravel-apps/web_sam/storage
```

### Network Security
- **Firewall Rules**: Otomatis konfigurasi UFW
- **HTTPS Only**: Automatic HTTPS dengan Let's Encrypt
- **Security Headers**: HSTS, CSP, XSS Protection
- **Rate Limiting**: Built-in rate limiting

## 🎯 Best Practices

### Laravel Octane Development
1. **Stateless Code**: Hindari global state
2. **Memory Management**: Monitor memory usage
3. **Database Connections**: Gunakan connection pooling
4. **Caching**: Leverage Redis untuk session dan cache
5. **Queue Workers**: Gunakan separate queue workers

### Deployment Strategy
1. **Pre-flight Checks**: Selalu jalankan resource check
2. **Gradual Scaling**: Scale bertahap, monitor resource
3. **Health Monitoring**: Setup monitoring dan alerting
4. **Backup Strategy**: Regular backup database dan files
5. **Update Strategy**: Blue-green deployment untuk zero downtime

## 📞 Support

Untuk pertanyaan dan dukungan:
- **GitHub Issues**: Report bugs dan feature requests
- **Documentation**: Lihat dokumentasi lengkap
- **Community**: Join Discord/Slack community

---

**Happy Deploying dengan Laravel Octane + FrankenPHP!** 🚀
