#!/bin/bash

# =============================================
# Configuration Module
# Berisi semua variabel global dan konstanta
# =============================================

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfigurasi Global
APPS_BASE_DIR="/opt/laravel-apps"
LOG_DIR="/var/log/frankenphp"
BACKUP_DIR="/var/backups/laravel-apps"
CONFIG_DIR="/etc/laravel-apps"

# Resource constants dan limits
MEMORY_SAFETY_MARGIN=20  # Reserve 20% of total memory
CPU_SAFETY_MARGIN=25     # Reserve 25% of total CPU
MIN_MEMORY_PER_APP=512   # Minimum MB per app
MAX_MEMORY_PER_APP=2048  # Maximum MB per app
MIN_CPU_PER_APP=0.5      # Minimum CPU cores per app
THREAD_MEMORY_USAGE=80   # Average MB per thread
MAX_APPS_PER_SERVER=10   # Hard limit for apps per server

# Mirror Ubuntu Indonesia
UBUNTU_MIRROR="http://mirror.unpad.ac.id/ubuntu"
UBUNTU_SECURITY_MIRROR="http://mirror.unpad.ac.id/ubuntu"

# PHP dan Node.js versions
PHP_VERSION="8.3"
NODE_VERSION="20"

# Database settings
MYSQL_VERSION="8.0"

# Variabel global untuk rollback
ROLLBACK_NEEDED=false
CREATED_DATABASE=""
CREATED_DB_USER=""
CREATED_APP_DIR=""
CREATED_CONFIG_FILE=""
CREATED_SERVICE_FILE=""
CREATED_SUPERVISOR_FILE=""
CREATED_CRON_JOBS=""
CURRENT_APP_NAME=""

# Export semua variabel agar bisa digunakan di modul lain
export RED GREEN YELLOW BLUE NC
export APPS_BASE_DIR LOG_DIR BACKUP_DIR CONFIG_DIR
export MEMORY_SAFETY_MARGIN CPU_SAFETY_MARGIN MIN_MEMORY_PER_APP MAX_MEMORY_PER_APP
export MIN_CPU_PER_APP THREAD_MEMORY_USAGE MAX_APPS_PER_SERVER
export UBUNTU_MIRROR UBUNTU_SECURITY_MIRROR
export PHP_VERSION NODE_VERSION MYSQL_VERSION
export ROLLBACK_NEEDED CREATED_DATABASE CREATED_DB_USER CREATED_APP_DIR
export CREATED_CONFIG_FILE CREATED_SERVICE_FILE CREATED_SUPERVISOR_FILE
export CREATED_CRON_JOBS CURRENT_APP_NAME 