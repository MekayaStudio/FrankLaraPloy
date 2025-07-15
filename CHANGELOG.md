# Changelog - Laravel Octane Integration

## [2.0.0] - 2024-12-19

### 🚀 Major Features Added

#### Laravel Octane Integration
- **Automatic Laravel Detection**: Script otomatis mendeteksi Laravel apps dan menggunakan Laravel Octane
- **FrankenPHP Binary Management**: Menggunakan `php artisan octane:install --server=frankenphp` untuk download binary
- **Smart Deployment Mode**: Otomatis pilih antara Laravel Octane atau standalone FrankenPHP
- **Reverse Proxy Architecture**: Caddy sebagai reverse proxy ke Laravel Octane (port 8000)

#### Enhanced Architecture
- **Laravel Octane Mode**: `Internet -> Caddy -> Laravel Octane (8000) -> FrankenPHP Workers`
- **Standalone Mode**: `Internet -> Caddy -> FrankenPHP Direct Serve` (untuk non-Laravel apps)
- **Mixed Environment**: Mendukung kedua mode secara bersamaan

#### New Helper Script
- **octane-helper.sh**: Script terpisah untuk management Laravel Octane
  - `install`: Install Laravel Octane dengan FrankenPHP
  - `configure`: Konfigurasi optimal untuk Octane
  - `start/stop/status`: Management server Octane
  - `optimize`: Optimisasi Laravel app untuk Octane

### 🔧 Technical Changes

#### Systemd Service Updates
- **Laravel Apps**: Menggunakan `php artisan octane:start --server=frankenphp`
- **Non-Laravel Apps**: Fallback ke `frankenphp run --config Caddyfile`
- **Dynamic Worker Allocation**: Worker count berdasarkan resource server

#### Caddyfile Configuration
- **Laravel Apps**: Reverse proxy ke `localhost:8000`
- **Non-Laravel Apps**: Direct PHP serving dengan `php_server`
- **Load Balancer**: Otomatis konfigurasi untuk scaling

#### Scaling Improvements
- **Laravel Octane Scaling**: Multiple Octane instances pada port berbeda
- **Load Balancer**: Otomatis setup reverse proxy dengan health checks
- **Resource Optimization**: Smart worker allocation per instance

### 📊 Performance Improvements

#### Laravel Octane Benefits
- **10x Performance**: Dibandingkan traditional PHP-FPM
- **Memory Efficiency**: Shared memory antar workers
- **Persistent State**: Database connections, compiled views
- **Zero Cold Start**: Workers selalu warm
- **HTTP/2 Support**: Native HTTP/2 dan HTTP/3

#### Resource Management
- **Smart Worker Calculation**: Berdasarkan CPU cores dan memory
- **Garbage Collection**: Automatic memory management
- **Request Limiting**: Prevent memory leaks dengan `max_requests`
- **Health Monitoring**: Automatic worker restart

### 🔄 Migration Path

#### Existing Apps
- **Backward Compatibility**: Existing apps tetap menggunakan standalone FrankenPHP
- **Gradual Migration**: Dapat migrate ke Laravel Octane dengan `octane-helper.sh`
- **Zero Downtime**: Migration tidak mempengaruhi apps yang sudah berjalan

#### New Apps
- **Auto-Detection**: Laravel apps otomatis menggunakan Octane
- **Optimal Configuration**: Konfigurasi optimal berdasarkan server resource
- **GitHub Integration**: Otomatis setup Octane saat clone dari GitHub

### 📝 Configuration Updates

#### Octane Configuration
```php
// config/octane.php - Auto-generated optimal config
'servers' => [
    'frankenphp' => [
        'workers' => env('OCTANE_WORKERS', $optimal_workers),
        'max_requests' => env('OCTANE_MAX_REQUESTS', 500),
        'host' => env('OCTANE_HOST', '0.0.0.0'),
        'port' => env('OCTANE_PORT', 8000),
    ],
],
```

#### Environment Variables
```bash
# Auto-added to .env for Laravel apps
OCTANE_SERVER=frankenphp
OCTANE_HOST=0.0.0.0
OCTANE_PORT=8000
OCTANE_WORKERS=8
OCTANE_MAX_REQUESTS=500
```

### 🛠️ Developer Experience

#### New Commands
```bash
# Laravel Octane Helper
./octane-helper.sh install /opt/laravel-apps/web_sam
./octane-helper.sh configure .
./octane-helper.sh start
./octane-helper.sh optimize

# Enhanced Main Commands
create-laravel-app web_sam domain.com https://github.com/user/repo.git
# ^ Otomatis setup Laravel Octane jika Laravel app
```

#### Improved Logging
- **Octane-specific logs**: `/var/log/frankenphp/web_sam.log`
- **Service identification**: `octane-web_sam` vs `frankenphp-web_sam`
- **Health check logs**: Monitoring kesehatan workers

### 🔍 Monitoring & Debugging

#### Enhanced Resource Monitoring
- **Worker Tracking**: Monitor jumlah workers per app
- **Memory Usage**: Track memory usage per worker
- **Request Metrics**: Monitor requests per worker
- **Health Status**: Real-time health check monitoring

#### Debugging Tools
```bash
# Check Octane status
./octane-helper.sh status

# Monitor worker health
tail -f /var/log/frankenphp/web_sam.log

# Resource analysis
analyze-app-resources
```

### 🚨 Breaking Changes

#### None for Existing Users
- **Full Backward Compatibility**: Existing deployments tidak terpengaruh
- **Gradual Adoption**: Dapat migrate ke Octane secara bertahap
- **Fallback Support**: Non-Laravel apps tetap menggunakan standalone FrankenPHP

#### New Default Behavior
- **Laravel Apps**: Default menggunakan Laravel Octane
- **Port Allocation**: Laravel apps menggunakan port 8000 internal
- **Service Names**: Laravel apps menggunakan `octane-` prefix

### 📚 Documentation Updates

#### New Documentation
- **README.md**: Comprehensive guide untuk Laravel Octane
- **octane-helper.sh**: Built-in help dan examples
- **Architecture Diagrams**: Visual representation of deployment modes

#### Updated Examples
- **Laravel Octane**: Contoh deployment dengan Octane
- **Mixed Environment**: Contoh environment dengan Laravel + non-Laravel apps
- **Scaling**: Contoh horizontal scaling dengan Octane

### 🎯 Future Roadmap

#### Planned Features
- **Auto-scaling**: Automatic scaling berdasarkan load
- **Health Dashboard**: Web-based monitoring dashboard
- **Performance Metrics**: Detailed performance monitoring
- **Blue-Green Deployment**: Zero-downtime deployment strategy

#### Optimization Targets
- **Memory Usage**: Further optimization untuk memory efficiency
- **Worker Management**: Dynamic worker scaling
- **Cache Integration**: Better integration dengan Redis/Memcached
- **Database Pooling**: Connection pooling untuk better performance

---

### Migration Guide

#### For New Users
1. Download updated script
2. Run installation
3. Create Laravel apps - otomatis menggunakan Octane

#### For Existing Users
1. Update script ke versi terbaru
2. Existing apps tetap berjalan normal
3. New apps otomatis menggunakan Octane
4. Optional: Migrate existing Laravel apps dengan `octane-helper.sh`

#### Testing Migration
```bash
# Test dengan app baru
create-laravel-app test_octane test.domain.com

# Verify Octane berjalan
./octane-helper.sh status /opt/laravel-apps/test_octane

# Check performance
curl -w "@curl-format.txt" -o /dev/null -s "http://test.domain.com"
```

---

**Happy deploying dengan Laravel Octane + FrankenPHP!** 🚀 