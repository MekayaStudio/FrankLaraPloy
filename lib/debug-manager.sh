#!/bin/bash

# =============================================
# Debug Manager Library
# Library untuk debugging dan testing
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${DEBUG_MANAGER_LOADED:-}" ]; then
    return 0
fi
export DEBUG_MANAGER_LOADED=1

# Import log functions if not already available
if ! declare -f log_warning &> /dev/null; then
    log_warning() {
        echo -e "\033[1;33m[WARNING]\033[0m $1"
    }
fi

if ! declare -f log_error &> /dev/null; then
    log_error() {
        echo -e "\033[0;31m[ERROR]\033[0m $1"
    }
fi

if ! declare -f log_info &> /dev/null; then
    log_info() {
        echo -e "\033[0;32m[INFO]\033[0m $1"
    }
fi

# =============================================
# Test Components Functions
# =============================================

test_components() {
    log_info "🧪 Testing FrankenPHP Multi-App Installer components..."
    echo ""

    local tests_passed=0
    local tests_failed=0

    # Test 1: Check if all required libraries exist
    log_info "📚 Testing library files..."
    local required_libs=("shared-functions.sh" "error-handler.sh" "validation.sh" "app-management.sh" "octane-manager.sh")

    for lib in "${required_libs[@]}"; do
        if [ -f "$SCRIPT_DIR/lib/$lib" ]; then
            log_info "  ✅ $lib found"
            tests_passed=$((tests_passed + 1))
        else
            log_error "  ❌ $lib missing"
            tests_failed=$((tests_failed + 1))
        fi
    done

    # Test 2: Check system requirements
    log_info "🔧 Testing system requirements..."

    # Test PHP
    if command -v php &> /dev/null; then
        local php_version=$(php -v | head -n 1 | cut -d " " -f 2)
        log_info "  ✅ PHP installed: $php_version"
        tests_passed=$((tests_passed + 1))
    else
        log_error "  ❌ PHP not found"
        tests_failed=$((tests_failed + 1))
    fi

    # Test Composer
    if command -v composer &> /dev/null; then
        local composer_version=$(composer --version | cut -d " " -f 3)
        log_info "  ✅ Composer installed: $composer_version"
        tests_passed=$((tests_passed + 1))
    else
        log_error "  ❌ Composer not found"
        tests_failed=$((tests_failed + 1))
    fi

    # Test Node.js
    if command -v node &> /dev/null; then
        local node_version=$(node -v)
        log_info "  ✅ Node.js installed: $node_version"
        tests_passed=$((tests_passed + 1))
    else
        log_warning "  ⚠️  Node.js not found (optional)"
    fi

    # Test 3: Check directory structure
    log_info "📁 Testing directory structure..."
    local required_dirs=("lib" "config")

    for dir in "${required_dirs[@]}"; do
        if [ -d "$SCRIPT_DIR/$dir" ]; then
            log_info "  ✅ $dir directory exists"
            tests_passed=$((tests_passed + 1))
        else
            log_error "  ❌ $dir directory missing"
            tests_failed=$((tests_failed + 1))
        fi
    done

    # Test 4: Check configuration
    log_info "⚙️  Testing configuration..."
    local config_file="$SCRIPT_DIR/config/frankenphp-config.conf"

    if [ -f "$config_file" ]; then
        log_info "  ✅ Configuration file exists"
        tests_passed=$((tests_passed + 1))
    else
        log_warning "  ⚠️  Configuration file missing (will use defaults)"
    fi

    # Test 5: Check permissions
    log_info "🔐 Testing permissions..."

    if [ -x "$SCRIPT_DIR/install.sh" ]; then
        log_info "  ✅ install.sh is executable"
        tests_passed=$((tests_passed + 1))
    else
        log_error "  ❌ install.sh is not executable"
        tests_failed=$((tests_failed + 1))
    fi

    # Test 6: Check MySQL connection (if available)
    log_info "🗄️  Testing MySQL connection..."

    if command -v mysql &> /dev/null; then
        if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null; then
            log_info "  ✅ MySQL service is running"
            tests_passed=$((tests_passed + 1))
        else
            log_warning "  ⚠️  MySQL service not running"
        fi
    else
        log_warning "  ⚠️  MySQL not installed"
    fi

    # Test 7: Check systemd
    log_info "🔧 Testing systemd..."

    if command -v systemctl &> /dev/null; then
        log_info "  ✅ systemd available"
        tests_passed=$((tests_passed + 1))
    else
        log_error "  ❌ systemd not available"
        tests_failed=$((tests_failed + 1))
    fi

    # Test 8: Check curl
    log_info "🌐 Testing curl..."

    if command -v curl &> /dev/null; then
        log_info "  ✅ curl available"
        tests_passed=$((tests_passed + 1))
    else
        log_error "  ❌ curl not available"
        tests_failed=$((tests_failed + 1))
    fi

    # Summary
    echo ""
    log_info "📊 Test Results:"
    log_info "  ✅ Passed: $tests_passed"

    if [ $tests_failed -gt 0 ]; then
        log_error "  ❌ Failed: $tests_failed"
    else
        log_info "  ❌ Failed: $tests_failed"
    fi

    if [ $tests_failed -eq 0 ]; then
        log_info "🎉 All tests passed! System is ready to use."
        return 0
    else
        log_warning "⚠️  Some tests failed. Please check the issues above."
        return 1
    fi
}

# =============================================
# Debug System Functions
# =============================================

debug_system() {
    local app_name="$1"

    if [ -n "$app_name" ]; then
        debug_app "$app_name"
    else
        debug_system_overview
    fi
}

debug_system_overview() {
    log_info "🔍 System Debug Overview"
    echo ""

    # System Information
    log_info "💻 System Information:"
    log_info "  OS: $(uname -s)"
    log_info "  Kernel: $(uname -r)"
    log_info "  Architecture: $(uname -m)"

    # Memory Information
    log_info "💾 Memory Information:"
    free -h | head -2

    # Disk Information
    log_info "💿 Disk Information:"
    df -h | head -2

    # Process Information
    log_info "⚙️  Process Information:"
    ps aux | head -5

    # Network Information
    log_info "🌐 Network Information:"
    ip addr show | grep -E "inet|link" | head -5

    # Service Status
    log_info "🔧 Service Status:"

    # Check MySQL
    if systemctl is-active --quiet mysql 2>/dev/null; then
        log_info "  ✅ MySQL: Running"
    else
        log_warning "  ⚠️  MySQL: Not running"
    fi

    # Check Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_info "  ✅ Nginx: Running"
    else
        log_warning "  ⚠️  Nginx: Not running"
    fi

    # Check FrankenPHP services
    local frankenphp_services=$(systemctl list-units --type=service --state=active | grep frankenphp | wc -l)
    if [ $frankenphp_services -gt 0 ]; then
        log_info "  ✅ FrankenPHP services: $frankenphp_services running"
    else
        log_warning "  ⚠️  FrankenPHP services: None running"
    fi
}

debug_app() {
    local app_name="$1"

    log_info "🔍 Debug information for app: $app_name"
    echo ""

    # Check if app exists
    local app_dir="$APPS_BASE_DIR/$app_name"
    if [ ! -d "$app_dir" ]; then
        log_error "App directory not found: $app_dir"
        return 1
    fi

    # App basic info
    log_info "📱 App Information:"
    log_info "  Name: $app_name"
    log_info "  Directory: $app_dir"

    # Check config file
    local config_file="$CONFIG_DIR/$app_name.conf"
    if [ -f "$config_file" ]; then
        log_info "  Config: $config_file"
        source "$config_file"
        log_info "  Domain: $DOMAIN"
        log_info "  Database: $DB_NAME"
    else
        log_error "  Config file not found: $config_file"
    fi

    # Service status
    local service_name="frankenphp-$app_name"
    log_info "🔧 Service Status:"

    if systemctl is-active --quiet "$service_name"; then
        log_info "  ✅ Service: Running"
        log_info "  Process: $(pgrep -f "$service_name" || echo "N/A")"
    else
        log_warning "  ⚠️  Service: Not running"
    fi

    # Port status
    log_info "🌐 Port Status:"
    local ports=("80" "443" "8000")

    for port in "${ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            log_info "  ✅ Port $port: Listening"
        else
            log_warning "  ⚠️  Port $port: Not listening"
        fi
    done

    # Laravel specific checks
    if [ -f "$app_dir/artisan" ]; then
        log_info "🚀 Laravel Checks:"

        cd "$app_dir"

        # Check Laravel version
        local laravel_version=$(php artisan --version 2>/dev/null | cut -d " " -f 3 || echo "Unknown")
        log_info "  Laravel version: $laravel_version"

        # Check if Octane is installed
        if php artisan list | grep -q "octane:"; then
            log_info "  ✅ Octane: Installed"
        else
            log_warning "  ⚠️  Octane: Not installed"
        fi

        # Check database connection
        if timeout 5 php artisan tinker --execute="DB::connection()->getPdo(); echo 'OK';" 2>/dev/null | grep -q "OK"; then
            log_info "  ✅ Database: Connected"
        else
            log_warning "  ⚠️  Database: Connection failed"
        fi

        # Check storage permissions
        if [ -w "$app_dir/storage" ]; then
            log_info "  ✅ Storage: Writable"
        else
            log_warning "  ⚠️  Storage: Not writable"
        fi

        # Check cache status
        if [ -f "$app_dir/bootstrap/cache/config.php" ]; then
            log_info "  ✅ Config: Cached"
        else
            log_warning "  ⚠️  Config: Not cached"
        fi
    else
        log_warning "🚀 Not a Laravel application"
    fi

    # Recent logs
    log_info "📋 Recent Logs:"
    if [ -f "/var/log/frankenphp/$app_name.log" ]; then
        tail -5 "/var/log/frankenphp/$app_name.log" 2>/dev/null || log_info "  No recent logs"
    else
        log_info "  No log file found"
    fi
}

# =============================================
# Performance Debug Functions
# =============================================

debug_performance() {
    local app_name="$1"

    log_info "⚡ Performance Debug for: $app_name"
    echo ""

    # System performance
    log_info "💻 System Performance:"

    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    log_info "  CPU Usage: ${cpu_usage}%"

    # Memory usage
    local memory_usage=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
    log_info "  Memory Usage: ${memory_usage}%"

    # Disk usage
    local disk_usage=$(df -h / | awk 'NR==2{print $5}')
    log_info "  Disk Usage: $disk_usage"

    # App specific performance
    if [ -n "$app_name" ]; then
        local app_dir="$APPS_BASE_DIR/$app_name"

        if [ -d "$app_dir" ]; then
            log_info "📱 App Performance:"

            # App process info
            local service_name="frankenphp-$app_name"
            local pid=$(pgrep -f "$service_name" | head -1)

            if [ -n "$pid" ]; then
                # Memory usage by process
                local app_memory=$(ps -p "$pid" -o %mem --no-headers | xargs)
                log_info "  App Memory: ${app_memory}%"

                # CPU usage by process
                local app_cpu=$(ps -p "$pid" -o %cpu --no-headers | xargs)
                log_info "  App CPU: ${app_cpu}%"
            else
                log_warning "  App process not found"
            fi
        fi
    fi
}

# =============================================
# Quick Setup and Install
# =============================================

quick_setup_and_install() {
    local app_name="$1"
    local domain="$2"
    local repo="$3"

    if [ -z "$app_name" ] || [ -z "$domain" ]; then
        log_error "Usage: quick_setup_and_install <app-name> <domain> [repo]"
        return 1
    fi

    log_info "🚀 Quick Setup and Install for: $app_name"
    echo ""

    # Check if system is set up
    if ! command -v create-laravel-app &> /dev/null; then
        log_info "🏗️  System not set up yet. Running setup..."
        if [ "$EUID" -ne 0 ]; then
            log_error "Please run as root for setup: sudo $0 quick $app_name $domain"
            return 1
        fi

        setup_system

        if [ $? -ne 0 ]; then
            log_error "Setup failed"
            return 1
        fi
    fi

    # Install app
    log_info "📱 Installing app..."
    install_app "$app_name" "$domain" "$repo"

    if [ $? -eq 0 ]; then
        log_info "🎉 Quick setup and install completed successfully!"
        log_info "🌐 Your app is available at: https://$domain"
    else
        log_error "Quick setup and install failed"
        return 1
    fi
}

# =============================================
# Library Testing Functions
# =============================================

test_library_loading() {
    log_info "📚 Testing library loading..."

    local libraries=("database" "systemd" "ssl" "connection")

    for lib in "${libraries[@]}"; do
        log_info "  Testing $lib library..."

        if load_module "$lib"; then
            log_info "  ✅ $lib library loaded successfully"
        else
            log_error "  ❌ $lib library failed to load"
        fi
    done
}

test_function_availability() {
    log_info "🔧 Testing function availability..."

    # Test core functions
    local core_functions=("log_info" "log_error" "load_module")

    for func in "${core_functions[@]}"; do
        if declare -f "$func" &> /dev/null; then
            log_info "  ✅ $func available"
        else
            log_error "  ❌ $func not available"
        fi
    done
}

# =============================================
# Command Testing Functions
# =============================================

test_all_commands() {
    log_info "🧪 Testing all commands (dry run)..."

    local commands=(
        "help"
        "list"
        "db:status"
        "systemd:list"
        "octane:status"
    )

    for cmd in "${commands[@]}"; do
        log_info "  Testing: $cmd"

        if ./install.sh "$cmd" &>/dev/null; then
            log_info "  ✅ $cmd works"
        else
            log_warning "  ⚠️  $cmd has issues"
        fi
    done
}
