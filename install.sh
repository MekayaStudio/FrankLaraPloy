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
source "$SCRIPT_DIR/lib/utils/shared-functions.sh"

# Load error handler
source "$SCRIPT_DIR/lib/utils/error-handler.sh"

# Load validation module
source "$SCRIPT_DIR/lib/utils/validation.sh"

# Load system setup module
source "$SCRIPT_DIR/lib/utils/system-setup.sh"

# Load app management (includes Laravel and Octane management)
source "$SCRIPT_DIR/lib/core/app-management.sh"

# Load Octane manager
source "$SCRIPT_DIR/lib/modules/octane-manager.sh"

# Load systemd manager
source "$SCRIPT_DIR/lib/modules/systemd-manager.sh"

# Load SSL manager
source "$SCRIPT_DIR/lib/modules/ssl-manager.sh"

# Load security module
source "$SCRIPT_DIR/lib/utils/security.sh"

# Load database manager
source "$SCRIPT_DIR/lib/modules/database-manager.sh"

# Load debug manager
source "$SCRIPT_DIR/lib/utils/debug-manager.sh"

# Load connection manager
source "$SCRIPT_DIR/lib/modules/connection-manager.sh"

# =============================================
# Configuration Variables
# =============================================

# Default versions
PHP_VERSION="8.3"
NODE_VERSION="18"

# Load error handler if not in test mode
if [ "${TEST_MODE:-false}" != "true" ]; then
    # Setup error handling
    setup_error_handling() {
        set -euo pipefail
        trap 'echo "Error occurred at line $LINENO. Exit code: $?" >&2' ERR
    }
    setup_error_handling
fi

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
    install <app> <domain> [repo] [db-name] [octane-mode] [http-mode]  Install new Laravel app
    remove <app>                    Remove Laravel app
    list                           List all installed apps
    resources                      Show multi-app resource usage
    status <app>                   Show app status
    logs <app> [lines]             Show app logs
    debug [app]                    Debug system or specific app
    
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
    
    Octane Dual Mode (HTTP/HTTPS):
    octane:dual <app> [mode]       Configure dual mode (dual/https-only/http-only)
    octane:start-dual <app> [mode] Start dual mode services
    octane:stop-dual <app> [mode]  Stop dual mode services
    octane:status-dual <app> [mode] Show dual mode status
    octane:restart-dual <app> [mode] Restart dual mode services

    SSL Management (FrankenPHP Automatic):
    ssl:status <app>               Show SSL status (automatic via FrankenPHP)
    ssl:info                       Show SSL information

EXAMPLES:
    # Setup system
    sudo ./install.sh setup
    
    # Install new Laravel app (with interactive mode selection)
    sudo ./install.sh install myapp example.com
    
    # Install with specific mode (skip interactive selection)
    sudo ./install.sh install myapp example.com "" "" smart dual
    
    # Install from GitHub with HTTPS-only mode
    sudo ./install.sh install myapp example.com https://github.com/user/repo.git myapp_db smart https-only
    
    # Check app status
    sudo ./install.sh status myapp
    
    # View logs
    sudo ./install.sh logs myapp 100
    
    # Configure dual mode (HTTP + HTTPS)
    sudo ./install.sh octane:dual myapp dual
    
    # Check dual mode status
    sudo ./install.sh octane:status-dual myapp dual

HTTP/HTTPS MODES:
    http-only    - Only HTTP (port 80) - ideal for development
    https-only   - Only HTTPS with HTTP redirect (port 443) - production with security
    dual         - Both HTTP and HTTPS (no redirect) - maximum compatibility

FEATURES:
    ✅ Laravel Octane with FrankenPHP (embedded web server)
    ✅ Automatic HTTPS with Let's Encrypt (built-in)
    ✅ HTTP/HTTPS dual mode support 
    ✅ Built-in PHP runtime (no PHP-FPM needed)
    ✅ HTTP/2 and HTTP/3 support
    ✅ Automatic database setup
    ✅ Systemd service management
    ✅ Queue worker management
    ✅ Scheduler setup
    ✅ Production optimization
    ✅ Zero-config SSL certificates

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
            
        "debug")
            shift
            debug_system "$@"
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
            
        # Dual mode commands
        "octane:dual")
            shift
            local app_name="$1"
            local mode="${2:-dual}"
            if [ -n "$app_name" ]; then
                octane_configure_mode "$app_name" "$mode"
            else
                log_error "Usage: octane:dual <app-name> [mode]"
                log_info "Available modes: dual, https-only, http-only"
                exit 1
            fi
            ;;
        "octane:start-dual")
            shift
            local app_name="$1"
            local mode="${2:-dual}"
            if [ -n "$app_name" ]; then
                octane_start_dual_mode "$app_name" "$mode"
            else
                log_error "Usage: octane:start-dual <app-name> [mode]"
                exit 1
            fi
            ;;
        "octane:stop-dual")
            shift
            local app_name="$1"
            local mode="${2:-dual}"
            if [ -n "$app_name" ]; then
                octane_stop_dual_mode "$app_name" "$mode"
            else
                log_error "Usage: octane:stop-dual <app-name> [mode]"
                exit 1
            fi
            ;;
        "octane:status-dual")
            shift
            local app_name="$1"
            local mode="${2:-dual}"
            if [ -n "$app_name" ]; then
                octane_status_dual_mode "$app_name" "$mode"
            else
                log_error "Usage: octane:status-dual <app-name> [mode]"
                exit 1
            fi
            ;;
        "octane:restart-dual")
            shift
            local app_name="$1"
            local mode="${2:-dual}"
            if [ -n "$app_name" ]; then
                octane_restart_dual_mode "$app_name" "$mode"
            else
                log_error "Usage: octane:restart-dual <app-name> [mode]"
                exit 1
            fi
            ;;
            
        # SSL commands (FrankenPHP automatic)
        "ssl:status")
            shift
            ssl_status "$1"
            ;;
        "ssl:info")
            ssl_info
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
