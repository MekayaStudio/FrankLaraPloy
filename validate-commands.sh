#!/bin/bash

# =============================================
# Simple FrankenPHP Command Validation
# Quick validation of all available commands
# =============================================

echo "🧪 FrankenPHP Multi-App Deployer - Quick Command Test"
echo "=================================================="

# Make sure script is executable
chmod +x install.sh

echo "✅ Testing help command..."
./install.sh --help > /dev/null 2>&1 && echo "   Help command works" || echo "   ❌ Help command failed"

echo "✅ Testing list command..."
./install.sh list > /dev/null 2>&1 && echo "   List command works" || echo "   ❌ List command failed"

echo "✅ Testing systemd list command..."
./install.sh systemd:list > /dev/null 2>&1 && echo "   Systemd list works" || echo "   ❌ Systemd list failed"

echo "✅ Testing database status..."
./install.sh db:status > /dev/null 2>&1 && echo "   Database status works" || echo "   ❌ Database status failed"

echo "✅ Testing SSL info..."
./install.sh ssl:info > /dev/null 2>&1 && echo "   SSL info works" || echo "   ❌ SSL info failed"

echo "✅ Testing debug command..."
./install.sh debug > /dev/null 2>&1 && echo "   Debug command works" || echo "   ❌ Debug command failed"

echo ""
echo "📋 Available Commands Summary:"
echo "------------------------------"
echo "System Commands:"
echo "  - setup: Setup system with FrankenPHP + Laravel Octane"
echo "  - debug [app]: Debug system or specific app"
echo ""
echo "App Management:"
echo "  - install <app> <domain> [repo] [db-name] [octane-mode] [http-mode]: Install new Laravel app"
echo "  - remove <app>: Remove Laravel app"
echo "  - list: List all installed apps"
echo "  - resources: Show multi-app resource usage"
echo "  - status <app>: Show app status"
echo "  - logs <app> [lines]: Show app logs"
echo ""
echo "Service Management:"
echo "  - systemd:check <app>: Check systemd service"
echo "  - systemd:fix <app>: Fix systemd service"
echo "  - systemd:fix-all: Fix all systemd services"
echo "  - systemd:list: List all services"
echo ""
echo "Database Management:"
echo "  - db:check <app>: Check database connection"
echo "  - db:fix <app>: Fix database issues"
echo "  - db:reset <app>: Reset database"
echo "  - db:list: List app databases"
echo "  - db:status: Show MySQL status"
echo ""
echo "Octane Management:"
echo "  - octane:install <app>: Install Octane in existing app"
echo "  - octane:start <app>: Start Octane server"
echo "  - octane:stop <app>: Stop Octane server"
echo "  - octane:restart <app>: Restart Octane server"
echo "  - octane:status <app>: Show Octane status"
echo ""
echo "Octane Dual Mode (HTTP/HTTPS):"
echo "  - octane:dual <app> [mode]: Configure dual mode"
echo "  - octane:start-dual <app> [mode]: Start dual mode services"
echo "  - octane:stop-dual <app> [mode]: Stop dual mode services"
echo "  - octane:status-dual <app> [mode]: Show dual mode status"
echo "  - octane:restart-dual <app> [mode]: Restart dual mode services"
echo ""
echo "SSL Management:"
echo "  - ssl:status <app>: Show SSL status"
echo "  - ssl:info: Show SSL information"
echo ""
echo "✅ Command validation completed!"
echo "📖 See README.md for detailed usage examples and documentation."
