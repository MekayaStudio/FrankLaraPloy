#!/bin/bash

# =============================================
# Laravel Octane + FrankenPHP Helper Script
# Membantu instalasi dan konfigurasi Laravel Octane
# =============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${BLUE}$1${NC}"
}

show_help() {
    echo ""
    log_header "🚀 Laravel Octane + FrankenPHP Helper"
    log_header "===================================="
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  install [directory]     - Install Laravel Octane with FrankenPHP"
    echo "  configure [directory]   - Configure existing Laravel app for Octane"
    echo "  start [directory]       - Start Laravel Octane server"
    echo "  stop [directory]        - Stop Laravel Octane server"
    echo "  status [directory]      - Check Octane server status"
    echo "  optimize [directory]    - Optimize Laravel app for Octane"
    echo "  help                    - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 install /opt/laravel-apps/web_sam"
    echo "  $0 configure ."
    echo "  $0 start"
    echo "  $0 optimize /var/www/laravel-app"
    echo ""
}

check_laravel_app() {
    local dir="${1:-.}"
    
    if [ ! -f "$dir/artisan" ]; then
        log_error "Tidak ditemukan file artisan di $dir"
        log_error "Pastikan Anda berada di direktori Laravel yang valid"
        return 1
    fi
    
    if [ ! -f "$dir/composer.json" ]; then
        log_error "Tidak ditemukan file composer.json di $dir"
        return 1
    fi
    
    log_info "✅ Laravel app ditemukan di $dir"
    return 0
}

install_octane() {
    local dir="${1:-.}"
    
    log_info "🚀 Menginstal Laravel Octane dengan FrankenPHP..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Check if Octane is already installed
    if grep -q "laravel/octane" composer.json; then
        log_info "✅ Laravel Octane sudah terinstal"
    else
        log_info "📦 Menginstal Laravel Octane package..."
        composer require laravel/octane
    fi
    
    # Install FrankenPHP via Octane
    log_info "⬇️  Menginstal FrankenPHP via Octane..."
    php artisan octane:install --server=frankenphp --force
    
    # Publish Octane config
    if [ ! -f "config/octane.php" ]; then
        log_info "📝 Mempublish konfigurasi Octane..."
        php artisan vendor:publish --provider="Laravel\Octane\OctaneServiceProvider" --tag=config
    fi
    
    log_info "✅ Laravel Octane dengan FrankenPHP berhasil diinstal!"
    log_info "🔧 Untuk memulai server: php artisan octane:start --server=frankenphp"
}

configure_octane() {
    local dir="${1:-.}"
    
    log_info "🔧 Mengkonfigurasi Laravel app untuk Octane..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Create optimized Octane config
    if [ -f "config/octane.php" ]; then
        log_info "📝 Mengoptimalkan konfigurasi Octane..."
        
        # Calculate optimal workers based on CPU cores
        local cpu_cores=$(nproc)
        local optimal_workers
        
        if [ $cpu_cores -eq 1 ]; then
            optimal_workers=2
        elif [ $cpu_cores -eq 2 ]; then
            optimal_workers=3
        elif [ $cpu_cores -le 4 ]; then
            optimal_workers=$((cpu_cores + 1))
        elif [ $cpu_cores -le 8 ]; then
            optimal_workers=$((cpu_cores + 2))
        else
            optimal_workers=$(((cpu_cores * 3 / 4) + 4))
        fi
        
        # Ensure minimum of 2 workers and maximum of 32
        if [ $optimal_workers -lt 2 ]; then
            optimal_workers=2
        elif [ $optimal_workers -gt 32 ]; then
            optimal_workers=32
        fi
        
        log_info "🧵 Mengatur jumlah workers optimal: $optimal_workers (berdasarkan $cpu_cores CPU cores)"
        
        # Update Octane config with optimal settings
        cat > config/octane.php <<CONFIG_EOF
<?php

return [
    'server' => env('OCTANE_SERVER', 'frankenphp'),
    
    'https' => [
        'host' => env('OCTANE_HTTPS_HOST', '0.0.0.0'),
        'port' => env('OCTANE_HTTPS_PORT', 443),
        'cert' => env('OCTANE_HTTPS_CERT'),
        'key' => env('OCTANE_HTTPS_KEY'),
    ],
    
    'servers' => [
        'frankenphp' => [
            'host' => env('OCTANE_HOST', '0.0.0.0'),
            'port' => env('OCTANE_PORT', 8000),
            'workers' => env('OCTANE_WORKERS', $optimal_workers),
            'task_workers' => env('OCTANE_TASK_WORKERS', 0),
            'max_requests' => env('OCTANE_MAX_REQUESTS', 500),
            'caddyfile' => base_path('Caddyfile'),
        ],
    ],
    
    'listeners' => [
        WorkerStarting::class => [
            EnsureUploadedFilesAreValid::class,
            EnsureUploadedFilesCanBeMoved::class,
        ],
        
        RequestReceived::class => [
            ...Octane::prepareApplicationForNextOperation(),
            ...Octane::prepareApplicationForNextRequest(),
        ],
        
        RequestHandled::class => [
            //
        ],
        
        RequestTerminated::class => [
            FlushTemporaryContainerInstances::class,
        ],
        
        TaskReceived::class => [
            ...Octane::prepareApplicationForNextOperation(),
        ],
        
        TaskTerminated::class => [
            FlushTemporaryContainerInstances::class,
        ],
        
        TickReceived::class => [
            ...Octane::prepareApplicationForNextOperation(),
        ],
        
        TickTerminated::class => [
            FlushTemporaryContainerInstances::class,
        ],
        
        WorkerErrorOccurred::class => [
            ReportException::class,
            StopWorkerIfNecessary::class,
        ],
        
        WorkerStopping::class => [
            //
        ],
    ],
    
    'warm' => [
        ...Octane::defaultServicesToWarm(),
    ],
    
    'cache' => [
        'driver' => env('OCTANE_CACHE_DRIVER', 'octane'),
        'store' => env('OCTANE_CACHE_STORE'),
    ],
    
    'tables' => [
        'example:1000' => [
            'name' => 'string:50',
            'votes' => 'int',
        ],
    ],
    
    'garbage_collection' => [
        'enabled' => env('OCTANE_GC_ENABLED', true),
        'app_memory' => env('OCTANE_GC_APP_MEMORY', 50),
        'reset_memory' => env('OCTANE_GC_RESET_MEMORY', 100),
        'reset_requests' => env('OCTANE_GC_RESET_REQUESTS', 1000),
    ],
    
    'watch' => [
        'app',
        'bootstrap',
        'config',
        'database',
        'resources/**/*.php',
        'routes',
        '.env',
    ],
];
CONFIG_EOF
        
        log_info "✅ Konfigurasi Octane dioptimalkan"
    else
        log_warning "⚠️  File config/octane.php tidak ditemukan"
        log_info "Jalankan: php artisan vendor:publish --provider=\"Laravel\\Octane\\OctaneServiceProvider\" --tag=config"
    fi
    
    # Update .env for Octane
    log_info "📝 Mengupdate .env untuk Octane..."
    
    if [ -f ".env" ]; then
        # Add Octane variables if not exist
        if ! grep -q "OCTANE_SERVER" .env; then
            echo "" >> .env
            echo "# Laravel Octane Configuration" >> .env
            echo "OCTANE_SERVER=frankenphp" >> .env
            echo "OCTANE_HOST=0.0.0.0" >> .env
            echo "OCTANE_PORT=8000" >> .env
            echo "OCTANE_WORKERS=$optimal_workers" >> .env
            echo "OCTANE_MAX_REQUESTS=500" >> .env
            echo "OCTANE_TASK_WORKERS=0" >> .env
            echo "OCTANE_GC_ENABLED=true" >> .env
            echo "OCTANE_GC_APP_MEMORY=50" >> .env
            echo "OCTANE_GC_RESET_MEMORY=100" >> .env
            echo "OCTANE_GC_RESET_REQUESTS=1000" >> .env
            
            log_info "✅ Variabel Octane ditambahkan ke .env"
        else
            log_info "✅ Variabel Octane sudah ada di .env"
        fi
    else
        log_warning "⚠️  File .env tidak ditemukan"
    fi
    
    log_info "✅ Konfigurasi Laravel Octane selesai!"
}

start_octane() {
    local dir="${1:-.}"
    
    log_info "🚀 Memulai Laravel Octane server..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Check if Octane is installed
    if ! grep -q "laravel/octane" composer.json; then
        log_error "Laravel Octane belum terinstal!"
        log_info "Jalankan: $0 install"
        return 1
    fi
    
    # Get configuration from .env
    local host="0.0.0.0"
    local port="8000"
    local workers="4"
    
    if [ -f ".env" ]; then
        if grep -q "OCTANE_HOST" .env; then
            host=$(grep "OCTANE_HOST" .env | cut -d'=' -f2)
        fi
        if grep -q "OCTANE_PORT" .env; then
            port=$(grep "OCTANE_PORT" .env | cut -d'=' -f2)
        fi
        if grep -q "OCTANE_WORKERS" .env; then
            workers=$(grep "OCTANE_WORKERS" .env | cut -d'=' -f2)
        fi
    fi
    
    log_info "🌐 Starting server pada $host:$port dengan $workers workers..."
    
    # Start Octane server
    php artisan octane:start --server=frankenphp --host=$host --port=$port --workers=$workers
}

stop_octane() {
    local dir="${1:-.}"
    
    log_info "🛑 Menghentikan Laravel Octane server..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Stop Octane server
    php artisan octane:stop || log_info "Server mungkin sudah berhenti"
    
    log_info "✅ Laravel Octane server dihentikan"
}

status_octane() {
    local dir="${1:-.}"
    
    log_info "📊 Memeriksa status Laravel Octane server..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Check Octane status
    php artisan octane:status || log_info "Server tidak berjalan"
}

optimize_octane() {
    local dir="${1:-.}"
    
    log_info "⚡ Mengoptimalkan Laravel app untuk Octane..."
    
    if ! check_laravel_app "$dir"; then
        return 1
    fi
    
    cd "$dir"
    
    # Laravel optimizations
    log_info "🔧 Menjalankan optimisasi Laravel..."
    
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache
    
    # Octane specific optimizations
    if grep -q "laravel/octane" composer.json; then
        log_info "🚀 Menjalankan optimisasi Octane..."
        
        # Clear Octane cache
        php artisan octane:clear
        
        # Reload workers if running
        php artisan octane:reload || log_info "Server tidak berjalan, skip reload"
    fi
    
    log_info "✅ Optimisasi selesai!"
}

# Main script logic
case "${1:-help}" in
    "install")
        install_octane "$2"
        ;;
    "configure")
        configure_octane "$2"
        ;;
    "start")
        start_octane "$2"
        ;;
    "stop")
        stop_octane "$2"
        ;;
    "status")
        status_octane "$2"
        ;;
    "optimize")
        optimize_octane "$2"
        ;;
    "help"|*)
        show_help
        ;;
esac 