#!/bin/bash

# =============================================
# FrankenPHP Multi-App Installer (Complete Solution)
# One-command installer untuk FrankenPHP + Laravel Octane
# Version: 3.0 - Production Ready with Modular Libraries
# =============================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================
# Load Required Libraries
# =============================================

# Load shared functions (contains logging, constants, etc)
source "$SCRIPT_DIR/lib/shared-functions.sh"

# Load error handler
source "$SCRIPT_DIR/lib/error-handler.sh"

# Load validation module
source "$SCRIPT_DIR/lib/validation.sh"

# Load system setup module
source "$SCRIPT_DIR/lib/system-setup.sh"

# Load Laravel manager
source "$SCRIPT_DIR/lib/laravel-manager.sh"

# Load Octane manager
source "$SCRIPT_DIR/lib/octane-manager.sh"

# Load systemd manager
source "$SCRIPT_DIR/lib/systemd-manager.sh"

# Load SSL manager
source "$SCRIPT_DIR/lib/ssl-manager.sh"

# Load security module
source "$SCRIPT_DIR/lib/security.sh"

# Load database manager
source "$SCRIPT_DIR/lib/database-manager.sh"

# Load app management
source "$SCRIPT_DIR/lib/app-management.sh"

# Load debug manager
source "$SCRIPT_DIR/lib/debug-manager.sh"

# Load connection manager
source "$SCRIPT_DIR/lib/connection-manager.sh"

# =============================================
# Configuration Variables
# =============================================

# Default versions
PHP_VERSION="8.3"
NODE_VERSION="18"

# Setup error handling
setup_error_handling

# =============================================
# Help Functions
# =============================================

show_help() {
    cat << 'EOF'
FrankenPHP Multi-App Deployer - Laravel Octane Management Tool

USAGE:
    sudo ./install.sh <command> [options]

COMMANDS:
    
    System Commands:
    setup                           Setup system with FrankenPHP + Laravel Octane
    
    App Management:
    install <app> <domain> [repo]   Install new Laravel app
    remove <app>                    Remove Laravel app
    list                           List all installed apps
    resources                      Show multi-app resource usage
    status <app>                   Show app status
    logs <app> [lines]             Show app logs
    
    Service Management:
    systemd:check <app>            Check systemd service
    systemd:fix <app>              Fix systemd service
    systemd:fix-all                Fix all systemd services
    systemd:list                   List all services
    
    Database Management:
    db:check <app>                 Check database connection
    db:fix <app>                   Fix database issues
    db:reset <app>                 Reset database
    db:list                        List app databases
    db:status                      Show MySQL status
    
    Octane Management:
    octane:install <app>           Install Octane in existing app
    octane:start <app>             Start Octane server
    octane:stop <app>              Stop Octane server
    octane:restart <app>           Restart Octane server
    octane:status <app>            Show Octane status

EXAMPLES:
    # Setup system
    sudo ./install.sh setup
    
    # Install new Laravel app
    sudo ./install.sh install myapp example.com
    
    # Install from GitHub
    sudo ./install.sh install myapp example.com https://github.com/user/repo.git
    
    # Check app status
    sudo ./install.sh status myapp
    
    # View logs
    sudo ./install.sh logs myapp 100

FEATURES:
    ✅ Laravel Octane with FrankenPHP (no nginx/apache needed)
    ✅ Automatic HTTPS with Let's Encrypt
    ✅ Built-in PHP runtime (no PHP-FPM)
    ✅ HTTP/2 and HTTP/3 support
    ✅ Automatic database setup
    ✅ Systemd service management
    ✅ Queue worker management
    ✅ Scheduler setup
    ✅ Production optimization

EOF
}

# =============================================
# Main Function
# =============================================

main() {
    local command="${1:-}"
    
    # Show help if no command provided
    if [[ -z "$command" || "$command" == "help" || "$command" == "--help" || "$command" == "-h" ]]; then
        show_help
        exit 0
    fi
    
    # Handle commands
    case "$command" in
        "setup")
            setup_system
            ;;
            
        "install")
            shift
            install_app "$@"
            ;;
            
        "remove")
            shift
            remove_app "$@"
            ;;
            
        "status")
            shift
            status_app "$@"
            ;;
            
        "list")
            list_apps
            ;;
            
        "resources")
            show_multi_app_resource_usage
            ;;
            
        "logs")
            shift
            logs_app "$@"
            ;;
            
        # Database commands
        "db:check")
            shift
            check_mysql_service
            check_app_database "$1"
            ;;
        "db:fix")
            shift
            check_mysql_service
            fix_app_database "$1"
            ;;
        "db:reset")
            shift
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
            
        # Systemd commands
        "systemd:check")
            shift
            systemd_check_service "$1"
            ;;
        "systemd:fix")
            shift
            systemd_fix_service "$1"
            ;;
        "systemd:fix-all")
            systemd_fix_all_services
            ;;
        "systemd:list")
            systemd_list_services
            ;;
            
        # Octane commands
        "octane:install")
            shift
            local app_dir="${1:-$(pwd)}"
            if [ -n "$1" ] && [ -d "$APPS_BASE_DIR/$1" ]; then
                app_dir="$APPS_BASE_DIR/$1"
            fi
            octane_install "$app_dir"
            ;;
        "octane:start")
            shift
            octane_start "$@"
            ;;
        "octane:stop")
            shift
            octane_stop "$@"
            ;;
        "octane:restart")
            shift
            octane_restart "$@"
            ;;
        "octane:status")
            shift
            octane_status "$@"
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
