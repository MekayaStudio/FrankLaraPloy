#!/bin/bash

# =============================================
# FrankenPHP Multi-App Installer (Refactored)
# One-command installer untuk FrankenPHP + Laravel Octane
# =============================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Simple functions for help
log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Load dependencies only for non-help commands
load_dependencies() {
    # Load core libraries in correct order
    source "$SCRIPT_DIR/lib/shared-functions.sh"
    source "$SCRIPT_DIR/lib/error-handler.sh"
    source "$SCRIPT_DIR/lib/validation.sh"

    # Load feature libraries
    source "$SCRIPT_DIR/lib/app-management.sh"
    source "$SCRIPT_DIR/lib/octane-manager.sh"

    # Load configuration
    if [ -f "$SCRIPT_DIR/config/frankenphp-config.conf" ]; then
        source "$SCRIPT_DIR/config/frankenphp-config.conf"
    fi
}

# Lazy loading for specific modules
load_module() {
    local module="$1"

    case "$module" in
        "database")
            [ -z "$DATABASE_MANAGER_LOADED" ] && source "$SCRIPT_DIR/lib/database-manager.sh"
            ;;
        "systemd")
            [ -z "$SYSTEMD_MANAGER_LOADED" ] && source "$SCRIPT_DIR/lib/systemd-manager.sh"
            ;;
        "ssl")
            [ -z "$SSL_MANAGER_LOADED" ] && source "$SCRIPT_DIR/lib/ssl-manager.sh"
            ;;
        "performance")
            [ -z "$PERFORMANCE_MANAGER_LOADED" ] && source "$SCRIPT_DIR/lib/performance-manager.sh"
            ;;
        "logs")
            [ -z "$LOG_MANAGER_LOADED" ] && source "$SCRIPT_DIR/lib/log-manager.sh"
            ;;
        "health")
            [ -z "$HEALTH_MANAGER_LOADED" ] && source "$SCRIPT_DIR/lib/health-manager.sh"
            ;;
        "debug")
            [ -z "$DEBUG_MANAGER_LOADED" ] && source "$SCRIPT_DIR/lib/debug-manager.sh"
            ;;
        "connection")
            [ -z "$CONNECTION_MANAGER_LOADED" ] && source "$SCRIPT_DIR/lib/connection-manager.sh"
            ;;
    esac
}

# Initialize for commands that need system directories
init_system_dirs() {
    if [ "$EUID" -eq 0 ]; then
        init_shared_functions
        init_error_handler
    fi
}

# =============================================
# Help System
# =============================================

show_help() {
    echo -e "\033[0;34m🚀 FrankenPHP Multi-App Installer\033[0m"
    echo -e "\033[0;34m=================================\033[0m"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "🏗️  System Commands:"
    echo "  setup                       - Setup sistem (install dependencies)"
    echo "  install <app> <domain> [repo] - Install Laravel app baru"
    echo "  deploy <app>                - Deploy ulang app"
    echo "  remove <app>                - Hapus app"
    echo ""
    echo "🔧 Laravel Octane Commands:"
    echo "  octane:install [dir]        - Install Laravel Octane + FrankenPHP"
    echo "  octane:start [dir]          - Start Octane server"
    echo "  octane:stop [dir]           - Stop Octane server"
    echo "  octane:restart [dir]        - Restart Octane server"
    echo "  octane:status [dir]         - Check Octane status"
    echo "  octane:optimize [dir]       - Optimize untuk production"
    echo "  octane:check <app>          - Check Octane installation status"
    echo "  octane:analyze <app>        - Analyze Octane setup and recommendations"
    echo "  octane:fix <app>            - Fix Octane setup issues"
    echo ""
    echo "📊 Management Commands:"
    echo "  list                        - List semua apps"
    echo "  status <app>                - Status app"
    echo "  scale <app> <up|down> <port> - Scale app"
    echo "  monitor                     - Monitor resources"
    echo "  backup                      - Backup semua apps"
    echo ""
    echo "🗄️  Database Commands:"
    echo "  db:check <app>              - Check database access untuk app"
    echo "  db:fix <app>                - Fix database access untuk app"
    echo "  db:reset <app>              - Reset database untuk app"
    echo "  db:list                     - List semua apps dan status database"
    echo "  db:status                   - Check MySQL service status"
    echo ""
    echo "🔧 Systemd Commands:"
    echo "  systemd:fix <app>           - Fix systemd namespace issues"
    echo "  systemd:fix-all             - Fix all frankenphp services"
    echo "  systemd:check <app>         - Check service status dan logs"
    echo "  systemd:list                - List all frankenphp services"
    echo ""
    echo "🌐 HTTPS & SSL Commands:"
    echo "  ssl:enable <app>            - Enable HTTPS untuk app"
    echo "  ssl:disable <app>           - Disable HTTPS untuk app"
    echo "  ssl:status <app>            - Check SSL certificate status"
    echo "  ssl:renew <app>             - Renew SSL certificate"
    echo ""
    echo "⚡ Performance Commands:"
    echo "  perf:tune <app>             - Tune performance settings"
    echo "  perf:cache <app>            - Optimize caching"
    echo "  perf:analyze <app>          - Analyze performance"
    echo ""
    echo "🔍 Debug & Health Commands:"
    echo "  debug [app]                 - Debug app atau system"
    echo "  health:check <app>          - Check app health"
    echo "  health:monitor <app>        - Monitor app continuously"
    echo "  test                        - Test semua components"
    echo ""
    echo "📋 Log Commands:"
    echo "  logs:view <app>             - View app logs"
    echo "  logs:clear <app>            - Clear app logs"
    echo "  logs:rotate <app>           - Rotate app logs"
    echo ""
    echo "🔧 Connection Commands:"
    echo "  connection:check <app>      - Check app connection issues"
    echo "  connection:fix <app>        - Fix connection issues"
    echo "  connection:test <app>       - Test connectivity"
    echo ""
    echo "Examples:"
    echo "  $0 setup                                    # Setup sistem"
    echo "  $0 install web_sam example.com             # Install app"
    echo "  $0 octane:install                           # Install Octane"
    echo "  $0 list                                     # List apps"
    echo "  $0 health:check testingsam                  # Check health"
    echo ""
}

# =============================================
# System Setup
# =============================================

setup_system() {
    log_info "🏗️ Setting up FrankenPHP Multi-App System..."

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run setup as root: sudo $0 setup"
        return 1
    fi

    # Initialize system directories
    init_system_dirs

    # Validate system requirements
    if ! validate_system_requirements "system_setup"; then
        display_validation_results
        return 1
    fi

    # Setup system dependencies
    log_info "📦 Installing system dependencies..."
    apt-get update
    apt-get install -y curl wget git unzip software-properties-common

    # Install PHP 8.2+
    log_info "🐘 Installing PHP 8.2..."
    add-apt-repository ppa:ondrej/php -y
    apt-get update
    apt-get install -y php8.2 php8.2-cli php8.2-fpm php8.2-mysql php8.2-xml php8.2-curl php8.2-zip php8.2-mbstring php8.2-intl php8.2-bcmath php8.2-gd php8.2-redis

    # Install Composer
    log_info "🎵 Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # Install Node.js (for asset compilation)
    log_info "� Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # Setup MySQL
    log_info "🗄️ Setting up MySQL..."
    apt-get install -y mysql-server
    systemctl start mysql
    systemctl enable mysql

    # Create necessary directories
    mkdir -p /var/log/frankenphp
    mkdir -p /etc/laravel-apps
    mkdir -p /opt/laravel-apps

    # Set permissions
    chown -R www-data:www-data /opt/laravel-apps
    chown -R www-data:www-data /var/log/frankenphp

    log_info "✅ System setup completed!"
    log_info "🔧 You can now use: $0 install <app> <domain> [repo]"
    log_info ""
    log_info "📖 Laravel Octane + FrankenPHP will be installed automatically per app"
}

# =============================================
# Main Command Router
# =============================================

main() {
    local command="$1"

    # Show help for empty command or help commands
    if [ -z "$command" ] || [ "$command" = "help" ] || [ "$command" = "--help" ] || [ "$command" = "-h" ]; then
        show_help
        exit 0
    fi

    # Test command doesn't need dependencies
    if [ "$command" = "test" ]; then
        load_module "debug"
        test_components
        exit 0
    fi

    shift

    # Load dependencies for other commands
    load_dependencies

    case "$command" in
        # System commands
        "setup")
            setup_system
            ;;
        "install")
            install_app "$@"
            ;;
        "deploy")
            deploy_app "$@"
            ;;
        "remove")
            remove_app "$@"
            ;;

        # Laravel Octane commands
        "octane:install")
            octane_install "$@"
            ;;
        "octane:start")
            octane_start "$@"
            ;;
        "octane:stop")
            octane_stop "$@"
            ;;
        "octane:restart")
            octane_restart "$@"
            ;;
        "octane:status")
            octane_status "$@"
            ;;
        "octane:optimize")
            octane_optimize "$@"
            ;;

        # Octane analysis commands
        "octane:check")
            load_module "debug"
            octane_check_status "$@"
            ;;
        "octane:analyze")
            load_module "debug"
            octane_analyze_setup "$@"
            ;;
        "octane:fix")
            load_module "debug"
            octane_fix_setup "$@"
            ;;

        # Management commands
        "list")
            list_apps
            ;;
        "status")
            status_app "$@"
            ;;
        "scale")
            scale_app "$@"
            ;;
        "monitor")
            load_module "performance"
            monitor_resources
            ;;
        "backup")
            backup_apps
            ;;

        # Database commands
        "db:"*)
            load_module "database"
            case "$command" in
                "db:check")
                    check_mysql_service
                    check_app_database "$1"
                    ;;
                "db:fix")
                    check_mysql_service
                    fix_app_database "$1"
                    ;;
                "db:reset")
                    check_mysql_service
                    reset_app_database "$1"
                    ;;
                "db:list")
                    check_mysql_service
                    list_apps_database
                    ;;
                "db:status")
                    mysql_status
                    ;;
            esac
            ;;

        # Systemd commands
        "systemd:"*)
            load_module "systemd"
            case "$command" in
                "systemd:fix")
                    systemd_fix_service "$1"
                    ;;
                "systemd:fix-all")
                    systemd_fix_all_services
                    ;;
                "systemd:check")
                    systemd_check_service "$1"
                    ;;
                "systemd:list")
                    systemd_list_services
                    ;;
            esac
            ;;

        # SSL/HTTPS commands
        "ssl:"*)
            load_module "ssl"
            case "$command" in
                "ssl:enable")
                    ssl_enable "$1"
                    ;;
                "ssl:disable")
                    ssl_disable "$1"
                    ;;
                "ssl:status")
                    ssl_status "$1"
                    ;;
                "ssl:renew")
                    ssl_renew "$1"
                    ;;
            esac
            ;;

        # Performance commands
        "perf:"*)
            load_module "performance"
            case "$command" in
                "perf:tune")
                    perf_tune "$1"
                    ;;
                "perf:cache")
                    perf_cache "$1"
                    ;;
                "perf:analyze")
                    perf_analyze "$1"
                    ;;
            esac
            ;;

        # Debug commands
        "debug")
            load_module "debug"
            debug_system "$@"
            ;;

        # Health commands
        "health:"*)
            load_module "health"
            case "$command" in
                "health:check")
                    health_check "$1"
                    ;;
                "health:monitor")
                    health_monitor "$1"
                    ;;
            esac
            ;;

        # Log commands
        "logs:"*)
            load_module "logs"
            case "$command" in
                "logs:view")
                    logs_view "$1"
                    ;;
                "logs:clear")
                    logs_clear "$1"
                    ;;
                "logs:rotate")
                    logs_rotate "$1"
                    ;;
            esac
            ;;

        # Connection commands
        "connection:"*)
            load_module "connection"
            case "$command" in
                "connection:check")
                    connection_check "$1"
                    ;;
                "connection:fix")
                    connection_fix "$1"
                    ;;
                "connection:test")
                    connection_test "$1"
                    ;;
            esac
            ;;

        # Quick commands
        "quick")
            load_module "debug"
            quick_setup_and_install "$@"
            ;;

        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# =============================================
# Script Execution
# =============================================

# Run main function
main "$@"
