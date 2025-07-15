#!/bin/bash

# =============================================
# Validation Module
# Modul validasi yang komprehensif dan reusable
# =============================================

# Pastikan module ini hanya di-load sekali
if [ -n "$VALIDATION_LOADED" ]; then
    return 0
fi
export VALIDATION_LOADED=1

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$SHARED_FUNCTIONS_LOADED" ]; then
    source "$SCRIPT_DIR/shared-functions.sh"
fi
if [ -z "$ERROR_HANDLER_LOADED" ]; then
    source "$SCRIPT_DIR/error-handler.sh"
fi

# =============================================
# Validation Configuration
# =============================================

# Validation modes
readonly VALIDATION_MODE_STRICT=1
readonly VALIDATION_MODE_LENIENT=2
readonly VALIDATION_MODE_DEVELOPMENT=3

# Default validation mode
VALIDATION_MODE=${VALIDATION_MODE:-$VALIDATION_MODE_STRICT}

# Validation result structure - compatible with older bash
VALIDATION_ERRORS=()
VALIDATION_WARNINGS=()
VALIDATION_RESULTS_KEYS=()
VALIDATION_RESULTS_VALUES=()

# =============================================
# Core Validation Functions
# =============================================

# Helper functions for validation results
set_validation_result() {
    local key="$1"
    local value="$2"
    
    # Check if key already exists
    local index=-1
    for i in "${!VALIDATION_RESULTS_KEYS[@]}"; do
        if [ "${VALIDATION_RESULTS_KEYS[$i]}" = "$key" ]; then
            index=$i
            break
        fi
    done
    
    if [ $index -eq -1 ]; then
        # Add new key-value pair
        VALIDATION_RESULTS_KEYS+=("$key")
        VALIDATION_RESULTS_VALUES+=("$value")
    else
        # Update existing value
        VALIDATION_RESULTS_VALUES[$index]="$value"
    fi
}

get_validation_result() {
    local key="$1"
    
    for i in "${!VALIDATION_RESULTS_KEYS[@]}"; do
        if [ "${VALIDATION_RESULTS_KEYS[$i]}" = "$key" ]; then
            echo "${VALIDATION_RESULTS_VALUES[$i]}"
            return 0
        fi
    done
    
    echo ""
    return 1
}

# Reset validation state
reset_validation() {
    VALIDATION_RESULTS_KEYS=()
    VALIDATION_RESULTS_VALUES=()
    VALIDATION_ERRORS=()
    VALIDATION_WARNINGS=()
}

# Add validation result
add_validation_result() {
    local key="$1"
    local result="$2"
    local message="$3"
    
    set_validation_result "$key" "$result"
    
    if [ "$result" = "error" ]; then
        VALIDATION_ERRORS+=("$key: $message")
    elif [ "$result" = "warning" ]; then
        VALIDATION_WARNINGS+=("$key: $message")
    fi
}

# Check if validation passed
validation_passed() {
    [ ${#VALIDATION_ERRORS[@]} -eq 0 ]
}

# Get validation summary
get_validation_summary() {
    local total_checks=${#VALIDATION_RESULTS_KEYS[@]}
    local error_count=${#VALIDATION_ERRORS[@]}
    local warning_count=${#VALIDATION_WARNINGS[@]}
    local success_count=$((total_checks - error_count - warning_count))
    
    echo "Validation Summary:"
    echo "  Total checks: $total_checks"
    echo "  Passed: $success_count"
    echo "  Warnings: $warning_count"
    echo "  Errors: $error_count"
    
    if [ $error_count -gt 0 ]; then
        echo ""
        echo "Errors:"
        printf '  - %s\n' "${VALIDATION_ERRORS[@]}"
    fi
    
    if [ $warning_count -gt 0 ]; then
        echo ""
        echo "Warnings:"
        printf '  - %s\n' "${VALIDATION_WARNINGS[@]}"
    fi
}

# =============================================
# String Validation Functions
# =============================================

# Validate string is not empty
validate_not_empty() {
    local value="$1"
    local field_name="$2"
    
    if [ -z "$value" ]; then
        add_validation_result "$field_name" "error" "Field cannot be empty"
        return 1
    fi
    
    add_validation_result "$field_name" "success" "Field is not empty"
    return 0
}

# Validate string length
validate_length() {
    local value="$1"
    local field_name="$2"
    local min_length="${3:-0}"
    local max_length="${4:-255}"
    
    local length=${#value}
    
    if [ $length -lt $min_length ]; then
        add_validation_result "$field_name" "error" "Length $length is less than minimum $min_length"
        return 1
    fi
    
    if [ $length -gt $max_length ]; then
        add_validation_result "$field_name" "error" "Length $length exceeds maximum $max_length"
        return 1
    fi
    
    add_validation_result "$field_name" "success" "Length $length is valid"
    return 0
}

# Validate string format with regex
validate_format() {
    local value="$1"
    local field_name="$2"
    local pattern="$3"
    local description="$4"
    
    if ! [[ "$value" =~ $pattern ]]; then
        add_validation_result "$field_name" "error" "Format invalid: $description"
        return 1
    fi
    
    add_validation_result "$field_name" "success" "Format is valid"
    return 0
}

# Validate string contains only allowed characters
validate_allowed_chars() {
    local value="$1"
    local field_name="$2"
    local allowed_pattern="$3"
    local description="$4"
    
    if ! [[ "$value" =~ ^[$allowed_pattern]+$ ]]; then
        add_validation_result "$field_name" "error" "Contains invalid characters: $description"
        return 1
    fi
    
    add_validation_result "$field_name" "success" "Contains only allowed characters"
    return 0
}

# =============================================
# Network Validation Functions
# =============================================

# Validate domain name
validate_domain() {
    local domain="$1"
    local field_name="${2:-domain}"
    
    # Check if empty
    if ! validate_not_empty "$domain" "$field_name"; then
        return 1
    fi
    
    # Check length
    if ! validate_length "$domain" "$field_name" 1 253; then
        return 1
    fi
    
    # Special cases
    if [ "$domain" = "localhost" ]; then
        add_validation_result "$field_name" "success" "localhost is valid"
        return 0
    fi
    
    # IP address validation
    if [[ "$domain" =~ ^[0-9.]+$ ]]; then
        return validate_ip_address "$domain" "$field_name"
    fi
    
    # Domain format validation
    local domain_pattern="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$"
    if ! validate_format "$domain" "$field_name" "$domain_pattern" "Valid domain format"; then
        return 1
    fi
    
    # Check for consecutive dots
    if [[ "$domain" =~ \.\. ]]; then
        add_validation_result "$field_name" "error" "Contains consecutive dots"
        return 1
    fi
    
    # Check starts/ends with dot or hyphen
    if [[ "$domain" =~ ^[.-] ]] || [[ "$domain" =~ [.-]$ ]]; then
        add_validation_result "$field_name" "error" "Cannot start or end with dot or hyphen"
        return 1
    fi
    
    add_validation_result "$field_name" "success" "Domain format is valid"
    return 0
}

# Validate IP address
validate_ip_address() {
    local ip="$1"
    local field_name="${2:-ip_address}"
    
    # Check format
    local ip_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    if ! validate_format "$ip" "$field_name" "$ip_pattern" "Valid IP address format"; then
        return 1
    fi
    
    # Validate octets
    IFS='.' read -ra OCTETS <<< "$ip"
    
    if [ ${#OCTETS[@]} -ne 4 ]; then
        add_validation_result "$field_name" "error" "Must have exactly 4 octets"
        return 1
    fi
    
    for i in "${!OCTETS[@]}"; do
        local octet="${OCTETS[$i]}"
        
        # Check if empty
        if [ -z "$octet" ]; then
            add_validation_result "$field_name" "error" "Octet $((i+1)) is empty"
            return 1
        fi
        
        # Check if numeric
        if ! [[ "$octet" =~ ^[0-9]+$ ]]; then
            add_validation_result "$field_name" "error" "Octet $((i+1)) is not numeric"
            return 1
        fi
        
        # Check range
        if [ $octet -gt 255 ]; then
            add_validation_result "$field_name" "error" "Octet $((i+1)) exceeds 255"
            return 1
        fi
        
        # Check leading zeros
        if [ ${#octet} -gt 1 ] && [ "${octet:0:1}" = "0" ]; then
            add_validation_result "$field_name" "error" "Octet $((i+1)) has leading zeros"
            return 1
        fi
    done
    
    add_validation_result "$field_name" "success" "IP address is valid"
    return 0
}

# Validate port number
validate_port() {
    local port="$1"
    local field_name="${2:-port}"
    local check_in_use="${3:-true}"
    
    # Check if empty
    if ! validate_not_empty "$port" "$field_name"; then
        return 1
    fi
    
    # Check if numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        add_validation_result "$field_name" "error" "Port must be numeric"
        return 1
    fi
    
    # Check range
    if [ $port -lt 1 ] || [ $port -gt 65535 ]; then
        add_validation_result "$field_name" "error" "Port must be between 1-65535"
        return 1
    fi
    
    # Warning for privileged ports
    if [ $port -lt 1024 ]; then
        add_validation_result "$field_name" "warning" "Port $port is privileged (< 1024)"
    fi
    
    # Check if port is in use
    if [ "$check_in_use" = "true" ]; then
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            add_validation_result "$field_name" "error" "Port $port is already in use"
            return 1
        fi
    fi
    
    add_validation_result "$field_name" "success" "Port is valid and available"
    return 0
}

# =============================================
# Application Validation Functions
# =============================================

# Validate application name
validate_app_name() {
    local app_name="$1"
    local field_name="${2:-app_name}"
    
    # Check if empty
    if ! validate_not_empty "$app_name" "$field_name"; then
        return 1
    fi
    
    # Check length
    if ! validate_length "$app_name" "$field_name" 1 60; then
        return 1
    fi
    
    # Check format
    local app_pattern="^[a-zA-Z][a-zA-Z0-9_]*$"
    if ! validate_format "$app_name" "$field_name" "$app_pattern" "Must start with letter, contain only letters, numbers, and underscores"; then
        return 1
    fi
    
    # Check reserved words
    local reserved_words=("mysql" "root" "admin" "test" "information_schema" "performance_schema" "sys")
    for reserved in "${reserved_words[@]}"; do
        if [ "${app_name,,}" = "${reserved,,}" ]; then
            add_validation_result "$field_name" "error" "Cannot use reserved word: $reserved"
            return 1
        fi
    done
    
    # Check if app already exists
    if [ -f "$CONFIG_DIR/$app_name.conf" ]; then
        add_validation_result "$field_name" "error" "Application already exists"
        return 1
    fi
    
    add_validation_result "$field_name" "success" "Application name is valid"
    return 0
}

# Validate Laravel application directory
validate_laravel_app() {
    local app_dir="$1"
    local field_name="${2:-laravel_app}"
    
    # Check if directory exists
    if [ ! -d "$app_dir" ]; then
        add_validation_result "$field_name" "error" "Directory does not exist: $app_dir"
        return 1
    fi
    
    # Check for artisan file
    if [ ! -f "$app_dir/artisan" ]; then
        add_validation_result "$field_name" "error" "artisan file not found in $app_dir"
        return 1
    fi
    
    # Check for composer.json
    if [ ! -f "$app_dir/composer.json" ]; then
        add_validation_result "$field_name" "error" "composer.json not found in $app_dir"
        return 1
    fi
    
    # Check if it's a Laravel app
    if ! grep -q "laravel/framework" "$app_dir/composer.json" 2>/dev/null; then
        add_validation_result "$field_name" "warning" "May not be a Laravel application"
    fi
    
    # Check directory permissions
    if [ ! -r "$app_dir" ] || [ ! -w "$app_dir" ]; then
        add_validation_result "$field_name" "error" "Insufficient permissions for directory: $app_dir"
        return 1
    fi
    
    add_validation_result "$field_name" "success" "Laravel application directory is valid"
    return 0
}

# =============================================
# System Validation Functions
# =============================================

# Validate system requirements
validate_system_requirements() {
    local field_name="${1:-system_requirements}"
    local errors=0
    
    # Check operating system
    if [ "$(uname -s)" != "Linux" ]; then
        add_validation_result "${field_name}_os" "error" "Only Linux is supported"
        ((errors++))
    else
        add_validation_result "${field_name}_os" "success" "Operating system is supported"
    fi
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        add_validation_result "${field_name}_root" "error" "Must run as root"
        ((errors++))
    else
        add_validation_result "${field_name}_root" "success" "Running as root"
    fi
    
    # Check required commands
    local required_commands=("curl" "wget" "git" "mysql" "php" "composer" "node" "npm")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            add_validation_result "${field_name}_cmd_$cmd" "error" "Required command not found: $cmd"
            ((errors++))
        else
            add_validation_result "${field_name}_cmd_$cmd" "success" "Command available: $cmd"
        fi
    done
    
    # Check PHP version
    if command_exists php; then
        local php_version=$(php -r "echo PHP_VERSION;" 2>/dev/null)
        if [ -n "$php_version" ]; then
            local php_major=$(echo "$php_version" | cut -d. -f1)
            local php_minor=$(echo "$php_version" | cut -d. -f2)
            
            if [ $php_major -lt 8 ] || ([ $php_major -eq 8 ] && [ $php_minor -lt 1 ]); then
                add_validation_result "${field_name}_php_version" "error" "PHP 8.1+ required, found $php_version"
                ((errors++))
            else
                add_validation_result "${field_name}_php_version" "success" "PHP version is compatible: $php_version"
            fi
        fi
    fi
    
    # Check disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if [ $available_space -lt $required_space ]; then
        add_validation_result "${field_name}_disk_space" "error" "Insufficient disk space (need 1GB)"
        ((errors++))
    else
        add_validation_result "${field_name}_disk_space" "success" "Sufficient disk space available"
    fi
    
    # Check memory
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    local required_memory=512
    
    if [ $available_memory -lt $required_memory ]; then
        add_validation_result "${field_name}_memory" "warning" "Low available memory (< 512MB)"
    else
        add_validation_result "${field_name}_memory" "success" "Sufficient memory available"
    fi
    
    return $errors
}

# Validate database connection
validate_database_connection() {
    local field_name="${1:-database_connection}"
    
    # Check if MySQL credentials exist
    if [ ! -f "$MYSQL_CREDENTIALS_FILE" ]; then
        add_validation_result "$field_name" "error" "MySQL credentials file not found"
        return 1
    fi
    
    # Test connection
    if ! test_mysql_connection; then
        add_validation_result "$field_name" "error" "Cannot connect to MySQL"
        return 1
    fi
    
    add_validation_result "$field_name" "success" "Database connection is working"
    return 0
}

# =============================================
# Resource Validation Functions
# =============================================

# Validate resource availability
validate_resource_availability() {
    local field_name="${1:-resource_availability}"
    local app_name="$2"
    
    # Get system resources
    local resources=($(get_system_resources))
    local total_memory_mb=${resources[0]}
    local available_memory_mb=${resources[1]}
    local total_cpu_cores=${resources[2]}
    local cpu_usage=${resources[3]}
    
    # Get current app usage
    local usage=($(get_app_resource_usage))
    local existing_apps=${usage[0]}
    local total_memory_used=${usage[2]}
    
    # Check hard limits
    if [ $existing_apps -ge $MAX_APPS_PER_SERVER ]; then
        add_validation_result "${field_name}_app_limit" "error" "Maximum apps per server reached ($MAX_APPS_PER_SERVER)"
        return 1
    else
        add_validation_result "${field_name}_app_limit" "success" "App limit not exceeded ($existing_apps/$MAX_APPS_PER_SERVER)"
    fi
    
    # Check memory availability
    if [ $available_memory_mb -lt $MIN_MEMORY_PER_APP ]; then
        add_validation_result "${field_name}_memory" "error" "Insufficient memory (need ${MIN_MEMORY_PER_APP}MB, have ${available_memory_mb}MB)"
        return 1
    else
        add_validation_result "${field_name}_memory" "success" "Sufficient memory available"
    fi
    
    # Check CPU usage
    local cpu_usage_int=$(echo "$cpu_usage" | cut -d'.' -f1)
    if [ $cpu_usage_int -gt 80 ]; then
        add_validation_result "${field_name}_cpu" "error" "High CPU usage detected (${cpu_usage}%)"
        return 1
    elif [ $cpu_usage_int -gt 70 ]; then
        add_validation_result "${field_name}_cpu" "warning" "Moderate CPU usage (${cpu_usage}%)"
    else
        add_validation_result "${field_name}_cpu" "success" "CPU usage is acceptable (${cpu_usage}%)"
    fi
    
    # Check memory usage percentage
    local memory_usage_percent=$(($total_memory_used * 100 / $total_memory_mb))
    if [ $memory_usage_percent -gt 80 ]; then
        add_validation_result "${field_name}_memory_usage" "error" "High memory usage (${memory_usage_percent}%)"
        return 1
    elif [ $memory_usage_percent -gt 70 ]; then
        add_validation_result "${field_name}_memory_usage" "warning" "Moderate memory usage (${memory_usage_percent}%)"
    else
        add_validation_result "${field_name}_memory_usage" "success" "Memory usage is acceptable (${memory_usage_percent}%)"
    fi
    
    return 0
}

# =============================================
# GitHub Repository Validation
# =============================================

# Validate GitHub repository
validate_github_repository() {
    local repo_url="$1"
    local field_name="${2:-github_repository}"
    
    # Check if empty (optional field)
    if [ -z "$repo_url" ]; then
        add_validation_result "$field_name" "success" "GitHub repository is optional"
        return 0
    fi
    
    # Check URL format
    local github_pattern="^https://github\.com/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+\.git$"
    if ! validate_format "$repo_url" "$field_name" "$github_pattern" "Valid GitHub repository URL"; then
        # Try without .git extension
        local github_pattern_no_git="^https://github\.com/[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$"
        if ! validate_format "$repo_url" "$field_name" "$github_pattern_no_git" "Valid GitHub repository URL"; then
            return 1
        fi
    fi
    
    # Check if repository is accessible (optional, requires network)
    if [ "$VALIDATION_MODE" = "$VALIDATION_MODE_STRICT" ]; then
        if ! curl -s --head "$repo_url" | head -1 | grep -q "200 OK"; then
            add_validation_result "$field_name" "warning" "Repository may not be accessible"
        else
            add_validation_result "$field_name" "success" "Repository is accessible"
        fi
    else
        add_validation_result "$field_name" "success" "Repository URL format is valid"
    fi
    
    return 0
}

# =============================================
# Comprehensive Validation Functions
# =============================================

# Validate new app creation parameters
validate_new_app_params() {
    local app_name="$1"
    local domain="$2"
    local github_repo="$3"
    local db_name="$4"
    
    reset_validation
    
    # Validate app name
    validate_app_name "$app_name" "app_name"
    
    # Validate domain
    validate_domain "$domain" "domain"
    
    # Validate GitHub repository (optional)
    validate_github_repository "$github_repo" "github_repository"
    
    # Validate database name
    if [ -n "$db_name" ]; then
        validate_app_name "$db_name" "database_name"
    fi
    
    # Validate system requirements
    validate_system_requirements "system"
    
    # Validate database connection
    validate_database_connection "database"
    
    # Validate resource availability
    validate_resource_availability "resources" "$app_name"
    
    return $([ ${#VALIDATION_ERRORS[@]} -eq 0 ] && echo 0 || echo 1)
}

# Validate octane installation parameters
validate_octane_params() {
    local app_dir="$1"
    
    reset_validation
    
    # Validate Laravel application
    validate_laravel_app "$app_dir" "laravel_app"
    
    # Validate system requirements
    validate_system_requirements "system"
    
    # Check if Octane is already installed
    if [ -f "$app_dir/composer.json" ] && grep -q "laravel/octane" "$app_dir/composer.json"; then
        add_validation_result "octane_installed" "warning" "Laravel Octane is already installed"
    else
        add_validation_result "octane_installed" "success" "Laravel Octane is not installed yet"
    fi
    
    return $([ ${#VALIDATION_ERRORS[@]} -eq 0 ] && echo 0 || echo 1)
}

# =============================================
# Validation Reporting
# =============================================

# Display validation results
display_validation_results() {
    local show_success="${1:-false}"
    
    if [ ${#VALIDATION_ERRORS[@]} -gt 0 ]; then
        log_error "Validation failed with ${#VALIDATION_ERRORS[@]} error(s):"
        for error in "${VALIDATION_ERRORS[@]}"; do
            log_error "  ❌ $error"
        done
    fi
    
    if [ ${#VALIDATION_WARNINGS[@]} -gt 0 ]; then
        log_warning "Validation warnings (${#VALIDATION_WARNINGS[@]}):"
        for warning in "${VALIDATION_WARNINGS[@]}"; do
            log_warning "  ⚠️  $warning"
        done
    fi
    
    if [ "$show_success" = "true" ]; then
        local success_count=0
        for i in "${!VALIDATION_RESULTS_KEYS[@]}"; do
            if [ "${VALIDATION_RESULTS_VALUES[$i]}" = "success" ]; then
                ((success_count++))
            fi
        done
        
        if [ $success_count -gt 0 ]; then
            log_info "Validation successes ($success_count):"
            for i in "${!VALIDATION_RESULTS_KEYS[@]}"; do
                if [ "${VALIDATION_RESULTS_VALUES[$i]}" = "success" ]; then
                    log_info "  ✅ ${VALIDATION_RESULTS_KEYS[$i]}"
                fi
            done
        fi
    fi
    
    # Return summary
    if [ ${#VALIDATION_ERRORS[@]} -eq 0 ]; then
        if [ ${#VALIDATION_WARNINGS[@]} -eq 0 ]; then
            log_info "✅ All validations passed"
        else
            log_info "✅ All validations passed with ${#VALIDATION_WARNINGS[@]} warning(s)"
        fi
        return 0
    else
        log_error "❌ Validation failed with ${#VALIDATION_ERRORS[@]} error(s)"
        return 1
    fi
}

# =============================================
# Initialization
# =============================================

# Initialize validation module
init_validation() {
    # Load configuration if available
    if [ -f "$SCRIPT_DIR/../config/frankenphp-config.conf" ]; then
        source "$SCRIPT_DIR/../config/frankenphp-config.conf"
    fi
    
    log_debug "Validation module initialized"
}

# Auto-initialize when sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    init_validation
fi 