#!/bin/bash

# =============================================
# Database Manager Library
# Library untuk manajemen database MySQL
# =============================================

# Pastikan library ini hanya di-load sekali
if [ -n "$DATABASE_MANAGER_LOADED" ]; then
    return 0
fi
export DATABASE_MANAGER_LOADED=1

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
}

get_mysql_root_password() {
    local password=""

    # Try to get password from debian-sys-maint
    if [ -f "/etc/mysql/debian.cnf" ]; then
        password=$(grep password /etc/mysql/debian.cnf | head -1 | cut -d'=' -f2 | xargs)
    fi

    # If still empty, try common locations
    if [ -z "$password" ]; then
        if [ -f "/root/.mysql_root_password" ]; then
            password=$(cat /root/.mysql_root_password)
        fi
    fi

    # Test connection
    if [ -n "$password" ]; then
        if mysql -u root -p"$password" -e "SELECT 1;" &>/dev/null; then
            log_info "✅ MySQL root connection successful"
            echo "$password"
            return 0
        fi
    fi

    # If all fails, try without password
    if mysql -u root -e "SELECT 1;" &>/dev/null; then
        log_info "✅ MySQL root connection successful (no password)"
        echo ""
        return 0
    fi

    log_error "❌ MySQL root connection failed"
    return 1
}

# =============================================
# Database Management Functions
# =============================================

check_app_database() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: check_app_database <app-name>"
        return 1
    fi

    log_info "🔍 Checking database for app: $app_name"

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    if [ ! -f "$app_config" ]; then
        log_error "App config not found: $app_config"
        return 1
    fi

    source "$app_config"

    # Get MySQL root password
    local root_password=$(get_mysql_root_password)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if database exists
    if [ -n "$root_password" ]; then
        mysql_cmd="mysql -u root -p$root_password"
    else
        mysql_cmd="mysql -u root"
    fi

    if $mysql_cmd -e "USE $DB_NAME;" 2>/dev/null; then
        log_info "✅ Database $DB_NAME exists"

        # Check if user can access database
        if $mysql_cmd -e "SELECT 1 FROM information_schema.tables WHERE table_schema='$DB_NAME' LIMIT 1;" 2>/dev/null; then
            log_info "✅ Database access works"

            # Test connection from Laravel app
            local app_dir="$APPS_BASE_DIR/$app_name"
            cd "$app_dir"
            if timeout 10 php artisan tinker --execute="DB::connection()->getPdo(); echo 'DB OK';" 2>/dev/null | grep -q "DB OK"; then
                log_info "✅ Laravel database connection works"
            else
                log_warning "⚠️  Laravel database connection failed"
            fi
        else
            log_error "❌ Database access failed"
        fi
    else
        log_error "❌ Database $DB_NAME does not exist"
    fi
}

fix_app_database() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: fix_app_database <app-name>"
        return 1
    fi

    log_info "🔧 Fixing database for app: $app_name"

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    # Get MySQL root password
    local root_password=$(get_mysql_root_password)
    if [ $? -ne 0 ]; then
        return 1
    fi

    if [ -n "$root_password" ]; then
        mysql_cmd="mysql -u root -p$root_password"
    else
        mysql_cmd="mysql -u root"
    fi

    # Create database if not exists
    log_info "📦 Creating database if not exists..."
    $mysql_cmd -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    # Create user if not exists
    log_info "👤 Creating database user..."
    $mysql_cmd -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"

    # Grant privileges
    log_info "🔑 Granting privileges..."
    $mysql_cmd -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    $mysql_cmd -e "FLUSH PRIVILEGES;"

    # Test connection
    log_info "🧪 Testing database connection..."
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "USE $DB_NAME; SELECT 1;" 2>/dev/null; then
        log_info "✅ Database connection test successful"

        # Run Laravel migrations
        local app_dir="$APPS_BASE_DIR/$app_name"
        cd "$app_dir"

        log_info "🚀 Running Laravel migrations..."
        if php artisan migrate --force; then
            log_info "✅ Migrations completed successfully"
        else
            log_warning "⚠️  Migration failed, but database is accessible"
        fi
    else
        log_error "❌ Database connection test failed"
        return 1
    fi
}

reset_app_database() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: reset_app_database <app-name>"
        return 1
    fi

    log_warning "⚠️  This will DELETE ALL DATA in the database!"
    read -p "Are you sure you want to reset database for $app_name? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Database reset cancelled"
        return 0
    fi

    log_info "🔄 Resetting database for app: $app_name"

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    # Get MySQL root password
    local root_password=$(get_mysql_root_password)
    if [ $? -ne 0 ]; then
        return 1
    fi

    if [ -n "$root_password" ]; then
        mysql_cmd="mysql -u root -p$root_password"
    else
        mysql_cmd="mysql -u root"
    fi

    # Drop and recreate database
    log_info "🗑️  Dropping database..."
    $mysql_cmd -e "DROP DATABASE IF EXISTS $DB_NAME;"

    log_info "📦 Creating fresh database..."
    $mysql_cmd -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    # Ensure user has access
    $mysql_cmd -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    $mysql_cmd -e "FLUSH PRIVILEGES;"

    # Run fresh migrations
    local app_dir="$APPS_BASE_DIR/$app_name"
    cd "$app_dir"

    log_info "🚀 Running fresh migrations..."
    if php artisan migrate:fresh --force; then
        log_info "✅ Database reset completed successfully"
    else
        log_error "❌ Migration failed"
        return 1
    fi
}

list_apps_database() {
    log_info "📋 Database status for all apps:"
    echo ""
    printf "%-20s %-20s %-15s %-10s\n" "App" "Database" "User" "Status"
    echo "================================================================"

    local apps_dir="$APPS_BASE_DIR"

    for app_dir in "$apps_dir"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            local config_file="$CONFIG_DIR/$app_name.conf"

            if [ -f "$config_file" ]; then
                source "$config_file"

                # Test database connection
                local status="❌ Failed"
                if mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "USE $DB_NAME; SELECT 1;" 2>/dev/null; then
                    status="✅ OK"
                fi

                printf "%-20s %-20s %-15s %-10s\n" "$app_name" "$DB_NAME" "$DB_USER" "$status"
            fi
        fi
    done
}

# =============================================
# Database Backup Functions
# =============================================

backup_app_database() {
    local app_name="$1"
    local backup_file="$2"

    if [ -z "$app_name" ]; then
        log_error "Usage: backup_app_database <app-name> [backup-file]"
        return 1
    fi

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    # Set backup file if not provided
    if [ -z "$backup_file" ]; then
        backup_file="$BACKUP_DIR/db_${app_name}_$(date +%Y%m%d_%H%M%S).sql"
    fi

    # Create backup directory
    mkdir -p "$(dirname "$backup_file")"

    log_info "💾 Backing up database $DB_NAME to $backup_file"

    # Create backup
    if mysqldump -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" > "$backup_file"; then
        log_info "✅ Database backup completed"
        log_info "📁 Backup saved to: $backup_file"
        return 0
    else
        log_error "❌ Database backup failed"
        return 1
    fi
}

restore_app_database() {
    local app_name="$1"
    local backup_file="$2"

    if [ -z "$app_name" ] || [ -z "$backup_file" ]; then
        log_error "Usage: restore_app_database <app-name> <backup-file>"
        return 1
    fi

    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_warning "⚠️  This will overwrite the current database!"
    read -p "Are you sure you want to restore database for $app_name? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Database restore cancelled"
        return 0
    fi

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    log_info "🔄 Restoring database $DB_NAME from $backup_file"

    # Restore database
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$backup_file"; then
        log_info "✅ Database restore completed"
        return 0
    else
        log_error "❌ Database restore failed"
        return 1
    fi
}

# =============================================
# Database Optimization Functions
# =============================================

optimize_app_database() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "Usage: optimize_app_database <app-name>"
        return 1
    fi

    # Load app config
    local app_config="$CONFIG_DIR/$app_name.conf"
    source "$app_config"

    log_info "⚡ Optimizing database $DB_NAME"

    # Optimize tables
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "USE $DB_NAME; OPTIMIZE TABLE $(mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "USE $DB_NAME; SHOW TABLES;" | tail -n +2 | tr '\n' ',' | sed 's/,$//');" 2>/dev/null; then
        log_info "✅ Database optimization completed"
    else
        log_warning "⚠️  Database optimization failed"
    fi
}
