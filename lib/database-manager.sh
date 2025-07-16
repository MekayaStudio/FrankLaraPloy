#!/bin/bash

# =============================================
# Database Manager Library
# Library untuk manajemen database MySQL
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "${DATABASE_MANAGER_LOADED:-}" ]; then
    return 0
fi
export DATABASE_MANAGER_LOADED=1

# Load dependencies
if [ -z "${SHARED_FUNCTIONS_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/shared-functions.sh"
fi
if [ -z "${ERROR_HANDLER_LOADED:-}" ]; then
    source "$SCRIPT_DIR/lib/error-handler.sh"
fi

# =============================================
# MySQL Configuration
# =============================================

MYSQL_ROOT_PASSWORD_FILE="/root/.laravel-apps/mysql_root_password"

get_mysql_root_password() {
    if [ -f "$MYSQL_ROOT_PASSWORD_FILE" ]; then
        cat "$MYSQL_ROOT_PASSWORD_FILE"
    else
        handle_error "MySQL root password file not found" $ERROR_CONFIGURATION
        return 1
    fi
}

# =============================================
# MySQL Service Functions
# =============================================

check_mysql_service() {
    log_info "🔍 Checking MySQL service status..."

    if systemctl is-active --quiet mysql; then
        log_info "✅ MySQL service is running"
        return 0
    elif systemctl is-active --quiet mysqld; then
        log_info "✅ MySQL service is running (mysqld)"
        return 0
    else
        log_error "❌ MySQL service is not running"
        log_info "🔧 Try: systemctl start mysql"
        return 1
    fi
}

mysql_status() {
    log_info "📊 MySQL Service Status"
    echo "===================="

    # Check service status
    if systemctl is-active --quiet mysql; then
        log_info "✅ Status: Running"
        systemctl status mysql --no-pager -l
    else
        log_warning "⚠️  Status: Not running"
    fi

    # Check if port is listening
    if netstat -tlnp | grep -q ":3306"; then
        log_info "✅ Port 3306 is listening"
    else
        log_warning "⚠️  Port 3306 is not listening"
    fi

    # Show MySQL version
    local mysql_version=$(mysql --version 2>/dev/null | awk '{print $3}')
    if [ -n "$mysql_version" ]; then
        log_info "📋 MySQL Version: $mysql_version"
    fi

    # Show database count
    local root_password=$(get_mysql_root_password)
    if [ -n "$root_password" ]; then
        local db_count=$(mysql -u root -p"$root_password" -e "SHOW DATABASES;" 2>/dev/null | wc -l)
        log_info "📊 Database Count: $((db_count - 1))"
    fi
}

# =============================================
# Database Management Functions
# =============================================

setup_app_database() {
    local app_name="$1"
    
    log_info "🗃️  Setting up database for app: $app_name"
    
    # Get MySQL root password
    local root_password=$(get_mysql_root_password)
    if [ -z "$root_password" ]; then
        return 1
    fi
    
    # Generate random password for app database user
    local db_password=$(openssl rand -base64 32)
    
    # Create database and user
    mysql -u root -p"$root_password" << EOF
CREATE DATABASE IF NOT EXISTS \`$app_name\`;
CREATE USER IF NOT EXISTS \`$app_name\`@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON \`$app_name\`.* TO \`$app_name\`@'localhost';
FLUSH PRIVILEGES;
EOF
    
    if [ $? -eq 0 ]; then
        # Save database password
        local db_password_file="/root/.laravel-apps/${app_name}_db_password"
        echo "$db_password" > "$db_password_file"
        chmod 600 "$db_password_file"
        
        log_info "✅ Database setup completed for app: $app_name"
        echo "$db_password"
    else
        handle_error "Failed to setup database for app: $app_name" $ERROR_DATABASE
        return 1
    fi
}

check_app_database() {
    local app_name="$1"
    
    log_info "🔍 Checking database connection for app: $app_name"
    
    local db_password_file="/root/.laravel-apps/${app_name}_db_password"
    if [ ! -f "$db_password_file" ]; then
        log_error "Database password file not found for app: $app_name"
        return 1
    fi
    
    local db_password=$(cat "$db_password_file")
    
    # Test database connection
    if mysql -u "$app_name" -p"$db_password" -e "USE \`$app_name\`; SELECT 1;" &>/dev/null; then
        log_info "✅ Database connection successful for app: $app_name"
        return 0
    else
        log_error "❌ Database connection failed for app: $app_name"
        return 1
    fi
}

fix_app_database() {
    local app_name="$1"
    
    log_info "🔧 Fixing database for app: $app_name"
    
    # Remove existing database and user
    remove_app_database "$app_name"
    
    # Recreate database and user
    setup_app_database "$app_name"
    
    log_info "✅ Database fixed for app: $app_name"
}

remove_app_database() {
    local app_name="$1"
    
    log_info "🗑️  Removing database for app: $app_name"
    
    # Get MySQL root password
    local root_password=$(get_mysql_root_password)
    if [ -z "$root_password" ]; then
        return 1
    fi
    
    # Remove database and user
    mysql -u root -p"$root_password" << EOF
DROP DATABASE IF EXISTS \`$app_name\`;
DROP USER IF EXISTS \`$app_name\`@'localhost';
FLUSH PRIVILEGES;
EOF
    
    if [ $? -eq 0 ]; then
        # Remove password file
        rm -f "/root/.laravel-apps/${app_name}_db_password"
        
        log_info "✅ Database removed for app: $app_name"
    else
        handle_error "Failed to remove database for app: $app_name" $ERROR_DATABASE
        return 1
    fi
}

reset_app_database() {
    local app_name="$1"
    
    log_info "🔄 Resetting database for app: $app_name"
    
    local db_password_file="/root/.laravel-apps/${app_name}_db_password"
    if [ ! -f "$db_password_file" ]; then
        log_error "Database password file not found for app: $app_name"
        return 1
    fi
    
    local db_password=$(cat "$db_password_file")
    
    # Drop all tables
    mysql -u "$app_name" -p"$db_password" -e "
        SET FOREIGN_KEY_CHECKS = 0;
        SELECT CONCAT('DROP TABLE IF EXISTS \`', table_name, '\`;') 
        FROM information_schema.tables 
        WHERE table_schema = '$app_name';" | grep "DROP TABLE" | mysql -u "$app_name" -p"$db_password" "$app_name"
    
    if [ $? -eq 0 ]; then
        log_info "✅ Database reset completed for app: $app_name"
        
        # Run migrations if artisan exists
        local app_dir="$APPS_BASE_DIR/$app_name"
        if [ -f "$app_dir/artisan" ]; then
            log_info "🔄 Running fresh migrations..."
            cd "$app_dir"
            php artisan migrate --force
        fi
    else
        handle_error "Failed to reset database for app: $app_name" $ERROR_DATABASE
        return 1
    fi
}

list_apps_database() {
    log_info "📋 Laravel applications database status:"
    
    local root_password=$(get_mysql_root_password)
    if [ -z "$root_password" ]; then
        return 1
    fi
    
    echo ""
    printf "%-20s %-15s %-10s %-s\n" "APP NAME" "DATABASE" "USER" "STATUS"
    printf "%-20s %-15s %-10s %-s\n" "--------" "--------" "----" "------"
    
    if [ ! -d "$APPS_BASE_DIR" ]; then
        echo "No applications found"
        return 0
    fi
    
    for app_dir in "$APPS_BASE_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            local status="ERROR"
            
            # Check if database exists
            if mysql -u root -p"$root_password" -e "USE \`$app_name\`;" &>/dev/null; then
                # Check if user can connect
                if check_app_database "$app_name" &>/dev/null; then
                    status="OK"
                else
                    status="USER_ERROR"
                fi
            else
                status="NO_DATABASE"
            fi
            
            printf "%-20s %-15s %-10s %-s\n" "$app_name" "$app_name" "$app_name" "$status"
        fi
    done
    echo ""
}

# =============================================
# Database Backup Functions
# =============================================

backup_app_database() {
    local app_name="$1"
    local backup_file="${2:-}"
    
    log_info "💾 Backing up database for app: $app_name"
    
    local db_password_file="/root/.laravel-apps/${app_name}_db_password"
    if [ ! -f "$db_password_file" ]; then
        handle_error "Database password file not found for app: $app_name" $ERROR_CONFIGURATION
        return 1
    fi
    
    local db_password=$(cat "$db_password_file")
    
    # Set backup file path
    if [ -z "$backup_file" ]; then
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        backup_file="$BACKUP_DIR/database_${app_name}_${timestamp}.sql"
    fi
    
    # Create backup directory
    ensure_directory "$(dirname "$backup_file")"
    
    # Create database dump
    if mysqldump -u "$app_name" -p"$db_password" "$app_name" > "$backup_file"; then
        log_info "✅ Database backup created: $backup_file"
        echo "$backup_file"
    else
        handle_error "Failed to create database backup for app: $app_name" $ERROR_DATABASE
        return 1
    fi
}

restore_app_database() {
    local app_name="$1"
    local backup_file="$2"
    
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        handle_error "Backup file not found: $backup_file" $ERROR_FILESYSTEM
        return 1
    fi
    
    log_info "🔄 Restoring database for app: $app_name from: $backup_file"
    
    local db_password_file="/root/.laravel-apps/${app_name}_db_password"
    if [ ! -f "$db_password_file" ]; then
        handle_error "Database password file not found for app: $app_name" $ERROR_CONFIGURATION
        return 1
    fi
    
    local db_password=$(cat "$db_password_file")
    
    # Restore database
    if mysql -u "$app_name" -p"$db_password" "$app_name" < "$backup_file"; then
        log_info "✅ Database restored successfully for app: $app_name"
    else
        handle_error "Failed to restore database for app: $app_name" $ERROR_DATABASE
        return 1
    fi
}

# =============================================
# Database Maintenance Functions
# =============================================

optimize_app_database() {
    local app_name="$1"
    
    log_info "⚡ Optimizing database for app: $app_name"
    
    local db_password_file="/root/.laravel-apps/${app_name}_db_password"
    if [ ! -f "$db_password_file" ]; then
        handle_error "Database password file not found for app: $app_name" $ERROR_CONFIGURATION
        return 1
    fi
    
    local db_password=$(cat "$db_password_file")
    
    # Optimize tables
    mysql -u "$app_name" -p"$db_password" -e "
        SELECT CONCAT('OPTIMIZE TABLE \`', table_name, '\`;') 
        FROM information_schema.tables 
        WHERE table_schema = '$app_name';" | grep "OPTIMIZE TABLE" | mysql -u "$app_name" -p"$db_password" "$app_name"
    
    if [ $? -eq 0 ]; then
        log_info "✅ Database optimized for app: $app_name"
    else
        handle_error "Failed to optimize database for app: $app_name" $ERROR_DATABASE
        return 1
    fi
}

get_database_size() {
    local app_name="$1"
    
    local root_password=$(get_mysql_root_password)
    if [ -z "$root_password" ]; then
        return 1
    fi
    
    local size=$(mysql -u root -p"$root_password" -e "
        SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'DB Size in MB'
        FROM information_schema.tables
        WHERE table_schema = '$app_name';" 2>/dev/null | tail -1)
    
    echo "${size:-0}"
}
