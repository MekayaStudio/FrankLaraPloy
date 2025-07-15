#!/bin/bash

# =============================================
# Error Handler Module
# Modul untuk menangani error dan rollback
# =============================================

# Pastikan module ini hanya di-load sekali
if [ -n "$ERROR_HANDLER_LOADED" ]; then
    return 0
fi
export ERROR_HANDLER_LOADED=1

# Load shared functions if not already loaded
if [ -z "$SHARED_FUNCTIONS_LOADED" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/shared-functions.sh"
fi

# =============================================
# Error Types and Codes
# =============================================

# Error codes
readonly ERROR_VALIDATION=1
readonly ERROR_NETWORK=2
readonly ERROR_FILESYSTEM=3
readonly ERROR_DATABASE=4
readonly ERROR_SERVICE=5
readonly ERROR_RESOURCE=6
readonly ERROR_PERMISSION=7
readonly ERROR_DEPENDENCY=8
readonly ERROR_CONFIGURATION=9
readonly ERROR_UNKNOWN=99

# Error type descriptions - compatible with older bash
get_error_description() {
    local error_code="$1"
    case "$error_code" in
        $ERROR_VALIDATION) echo "Validation Error" ;;
        $ERROR_NETWORK) echo "Network Error" ;;
        $ERROR_FILESYSTEM) echo "Filesystem Error" ;;
        $ERROR_DATABASE) echo "Database Error" ;;
        $ERROR_SERVICE) echo "Service Error" ;;
        $ERROR_RESOURCE) echo "Resource Error" ;;
        $ERROR_PERMISSION) echo "Permission Error" ;;
        $ERROR_DEPENDENCY) echo "Dependency Error" ;;
        $ERROR_CONFIGURATION) echo "Configuration Error" ;;
        $ERROR_UNKNOWN) echo "Unknown Error" ;;
        *) echo "Unknown Error" ;;
    esac
}

# =============================================
# Global Error State
# =============================================

# Error tracking variables
ERROR_OCCURRED=false
ERROR_CODE=0
ERROR_MESSAGE=""
ERROR_CONTEXT=""
ERROR_TIMESTAMP=""
ERROR_STACK_TRACE=""

# Rollback tracking
ROLLBACK_NEEDED=false
ROLLBACK_ACTIONS=()

# =============================================
# Error Logging
# =============================================

# Log error to file
log_error_to_file() {
    local error_msg="$1"
    local error_code="$2"
    local context="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="${LOG_DIR}/error.log"
    
    ensure_directory "$(dirname "$log_file")"
    
    cat >> "$log_file" <<EOF
[$timestamp] ERROR: $error_msg
Code: $error_code ($(get_error_description $error_code))
Context: $context
Stack Trace: $ERROR_STACK_TRACE
---
EOF
}

# Generate stack trace
generate_stack_trace() {
    local stack_trace=""
    local frame=0
    
    while caller $frame >/dev/null 2>&1; do
        local line_info=$(caller $frame)
        stack_trace="$stack_trace\n  Frame $frame: $line_info"
        ((frame++))
    done
    
    echo -e "$stack_trace"
}

# =============================================
# Error Handling Functions
# =============================================

# Set error state
set_error() {
    local error_code="$1"
    local error_message="$2"
    local context="${3:-}"
    
    ERROR_OCCURRED=true
    ERROR_CODE="$error_code"
    ERROR_MESSAGE="$error_message"
    ERROR_CONTEXT="$context"
    ERROR_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    ERROR_STACK_TRACE=$(generate_stack_trace)
    
    # Log error
    log_error_to_file "$error_message" "$error_code" "$context"
    
    # Display error
    log_error "[$(get_error_description $error_code)] $error_message"
    if [ -n "$context" ]; then
        log_error "Context: $context"
    fi
    
    # Set rollback needed if not already set
    if [ "$ROLLBACK_NEEDED" = false ]; then
        ROLLBACK_NEEDED=true
    fi
}

# Clear error state
clear_error() {
    ERROR_OCCURRED=false
    ERROR_CODE=0
    ERROR_MESSAGE=""
    ERROR_CONTEXT=""
    ERROR_TIMESTAMP=""
    ERROR_STACK_TRACE=""
    ROLLBACK_NEEDED=false
    ROLLBACK_ACTIONS=()
}

# Check if error occurred
has_error() {
    [ "$ERROR_OCCURRED" = true ]
}

# Get error details
get_error_details() {
    if has_error; then
        echo "Error Code: $ERROR_CODE"
        echo "Error Message: $ERROR_MESSAGE"
        echo "Error Context: $ERROR_CONTEXT"
        echo "Error Timestamp: $ERROR_TIMESTAMP"
        echo "Error Type: $(get_error_description $ERROR_CODE)"
    else
        echo "No error occurred"
    fi
}

# =============================================
# Rollback System
# =============================================

# Add rollback action
add_rollback_action() {
    local action="$1"
    local description="$2"
    
    ROLLBACK_ACTIONS+=("$action|$description")
    log_debug "Rollback action added: $description"
}

# Execute rollback actions
execute_rollback() {
    if [ ${#ROLLBACK_ACTIONS[@]} -eq 0 ]; then
        log_info "No rollback actions to execute"
        return 0
    fi
    
    log_warning "Executing rollback actions..."
    
    # Execute rollback actions in reverse order
    local i
    for ((i=${#ROLLBACK_ACTIONS[@]}-1; i>=0; i--)); do
        local action_data="${ROLLBACK_ACTIONS[$i]}"
        local action="${action_data%%|*}"
        local description="${action_data##*|}"
        
        log_info "Rollback: $description"
        
        # Execute action with error handling
        if eval "$action" 2>/dev/null; then
            log_info "✅ Rollback action completed: $description"
        else
            log_error "❌ Rollback action failed: $description"
        fi
    done
    
    log_info "Rollback completed"
    clear_error
}

# =============================================
# Specific Error Handlers
# =============================================

# Handle validation errors
handle_validation_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_VALIDATION "$message" "$context"
}

# Handle network errors
handle_network_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_NETWORK "$message" "$context"
}

# Handle filesystem errors
handle_filesystem_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_FILESYSTEM "$message" "$context"
}

# Handle database errors
handle_database_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_DATABASE "$message" "$context"
}

# Handle service errors
handle_service_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_SERVICE "$message" "$context"
}

# Handle resource errors
handle_resource_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_RESOURCE "$message" "$context"
}

# Handle permission errors
handle_permission_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_PERMISSION "$message" "$context"
}

# Handle dependency errors
handle_dependency_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_DEPENDENCY "$message" "$context"
}

# Handle configuration errors
handle_configuration_error() {
    local message="$1"
    local context="${2:-}"
    set_error $ERROR_CONFIGURATION "$message" "$context"
}

# =============================================
# Error Recovery Functions
# =============================================

# Try to recover from error
try_recover() {
    local recovery_function="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-5}"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "Recovery attempt $attempt of $max_attempts..."
        
        if eval "$recovery_function"; then
            log_info "Recovery successful"
            clear_error
            return 0
        else
            log_warning "Recovery attempt $attempt failed"
            if [ $attempt -lt $max_attempts ]; then
                log_info "Waiting ${delay}s before next attempt..."
                sleep "$delay"
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Recovery failed after $max_attempts attempts"
    return 1
}

# =============================================
# Deployment-Specific Rollback Actions
# =============================================

# Rollback database creation
rollback_database_creation() {
    local db_name="$1"
    local db_user="$2"
    
    if [ -n "$db_name" ] && [ -n "$db_user" ]; then
        local mysql_pass=$(get_mysql_credentials)
        if [ $? -eq 0 ]; then
            mysql -u root -p"$mysql_pass" <<MYSQL_EOF 2>/dev/null || true
DROP DATABASE IF EXISTS \`$db_name\`;
DROP USER IF EXISTS '$db_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_EOF
            log_info "Database and user removed: $db_name, $db_user"
        fi
    fi
}

# Rollback directory creation
rollback_directory_creation() {
    local dir_path="$1"
    
    if [ -n "$dir_path" ] && [ -d "$dir_path" ]; then
        rm -rf "$dir_path"
        log_info "Directory removed: $dir_path"
    fi
}

# Rollback file creation
rollback_file_creation() {
    local file_path="$1"
    
    if [ -n "$file_path" ] && [ -f "$file_path" ]; then
        rm -f "$file_path"
        log_info "File removed: $file_path"
    fi
}

# Rollback service creation
rollback_service_creation() {
    local service_name="$1"
    
    if [ -n "$service_name" ]; then
        systemctl stop "$service_name" 2>/dev/null || true
        systemctl disable "$service_name" 2>/dev/null || true
        rm -f "/etc/systemd/system/${service_name}.service"
        systemctl daemon-reload 2>/dev/null || true
        log_info "Service removed: $service_name"
    fi
}

# Rollback cron job creation
rollback_cron_creation() {
    local cron_pattern="$1"
    local user="${2:-www-data}"
    
    if [ -n "$cron_pattern" ]; then
        crontab -u "$user" -l 2>/dev/null | grep -v "$cron_pattern" | crontab -u "$user" - 2>/dev/null || true
        log_info "Cron job removed: $cron_pattern"
    fi
}

# =============================================
# Error Trap Setup
# =============================================

# Enhanced error trap handler
enhanced_error_trap() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    
    # Skip if error already handled
    if has_error; then
        return $exit_code
    fi
    
    # Set error details
    ERROR_OCCURRED=true
    ERROR_CODE=$exit_code
    ERROR_MESSAGE="Command failed at line $line_number: $command"
    ERROR_CONTEXT="Exit code: $exit_code"
    ERROR_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    ERROR_STACK_TRACE=$(generate_stack_trace)
    
    # Log error
    log_error_to_file "$ERROR_MESSAGE" "$exit_code" "$ERROR_CONTEXT"
    log_error "Command failed at line $line_number (exit code: $exit_code)"
    log_error "Command: $command"
    
    # Execute rollback if needed
    if [ "$ROLLBACK_NEEDED" = true ]; then
        execute_rollback
    fi
    
    exit $exit_code
}

# Set up enhanced error trap
setup_enhanced_error_trap() {
    set -eE  # Exit on error and inherit traps
    trap 'enhanced_error_trap $LINENO "$BASH_COMMAND"' ERR
}

# =============================================
# Validation with Error Handling
# =============================================

# Validate with error handling
validate_with_error_handling() {
    local validation_function="$1"
    local error_message="$2"
    local context="${3:-}"
    
    if ! eval "$validation_function"; then
        handle_validation_error "$error_message" "$context"
        return 1
    fi
    
    return 0
}

# =============================================
# Safe Execution Functions
# =============================================

# Execute command safely with error handling
safe_execute() {
    local command="$1"
    local error_message="$2"
    local context="${3:-}"
    local rollback_action="${4:-}"
    
    # Add rollback action if provided
    if [ -n "$rollback_action" ]; then
        add_rollback_action "$rollback_action" "Rollback for: $command"
    fi
    
    # Execute command
    if ! eval "$command"; then
        set_error $ERROR_UNKNOWN "$error_message" "$context"
        return 1
    fi
    
    return 0
}

# Execute with retry and error handling
safe_execute_with_retry() {
    local command="$1"
    local error_message="$2"
    local max_attempts="${3:-3}"
    local delay="${4:-5}"
    local context="${5:-}"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if eval "$command"; then
            return 0
        else
            log_warning "Command failed on attempt $attempt: $command"
            if [ $attempt -lt $max_attempts ]; then
                log_info "Retrying in ${delay}s..."
                sleep "$delay"
            fi
        fi
        ((attempt++))
    done
    
    set_error $ERROR_UNKNOWN "$error_message" "$context"
    return 1
}

# =============================================
# Error Reporting
# =============================================

# Generate error report
generate_error_report() {
    local report_file="${LOG_DIR}/error-report-$(date +%Y%m%d_%H%M%S).log"
    
    ensure_directory "$(dirname "$report_file")"
    
    cat > "$report_file" <<EOF
FrankenPHP Multi-App Error Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')
===============================================

Error Details:
- Code: $ERROR_CODE
- Type: $(get_error_description $ERROR_CODE)
- Message: $ERROR_MESSAGE
- Context: $ERROR_CONTEXT
- Timestamp: $ERROR_TIMESTAMP

Stack Trace:
$ERROR_STACK_TRACE

System Information:
- OS: $(uname -a)
- User: $(whoami)
- Working Directory: $(pwd)
- Memory: $(free -h | grep ^Mem)
- Disk: $(df -h | grep -E "/$|/opt")

Rollback Actions Executed:
$(printf '%s\n' "${ROLLBACK_ACTIONS[@]}" | sed 's/|/ - /')

===============================================
EOF
    
    log_info "Error report generated: $report_file"
    echo "$report_file"
}

# =============================================
# Initialization
# =============================================

# Initialize error handler
init_error_handler() {
    # Setup enhanced error trap
    setup_enhanced_error_trap
    
    # Ensure log directory exists
    ensure_directory "$LOG_DIR"
    
    log_debug "Error handler initialized"
}

# Auto-initialize when sourced (only for root commands)
if [ "${BASH_SOURCE[0]}" != "${0}" ] && [ "$EUID" -eq 0 ]; then
    init_error_handler
fi 