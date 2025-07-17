#!/bin/bash

# =============================================
# Test Script untuk HTTP/HTTPS Dual Mode
# =============================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configuration
APP_NAME="${1:-testapp}"
DOMAIN="${2:-test.example.com}"
MODE="${3:-dual}"

if [ -z "$APP_NAME" ] || [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <app-name> <domain> [mode]"
    echo "Example: $0 testapp test.example.com dual"
    exit 1
fi

log_info "🧪 Testing HTTP/HTTPS Dual Mode"
log_info "App: $APP_NAME"
log_info "Domain: $DOMAIN"
log_info "Mode: $MODE"
echo ""

# Test 1: Check if app exists
log_info "Test 1: Checking if app exists..."
if [ -d "/opt/laravel-apps/$APP_NAME" ]; then
    log_success "App directory exists"
else
    log_warning "App directory not found, creating test app..."
    sudo ./install.sh install "$APP_NAME" "$DOMAIN"
fi

# Test 2: Configure dual mode
log_info "Test 2: Configuring dual mode..."
if sudo ./install.sh octane:dual "$APP_NAME" "$MODE"; then
    log_success "Dual mode configured successfully"
else
    log_error "Failed to configure dual mode"
    exit 1
fi

# Test 3: Start services
log_info "Test 3: Starting services..."
if sudo ./install.sh octane:start-dual "$APP_NAME" "$MODE"; then
    log_success "Services started successfully"
else
    log_error "Failed to start services"
    exit 1
fi

# Wait for services to be ready
log_info "Waiting for services to be ready..."
sleep 5

# Test 4: Check service status
log_info "Test 4: Checking service status..."
if sudo ./install.sh octane:status-dual "$APP_NAME" "$MODE"; then
    log_success "Service status check completed"
else
    log_warning "Service status check failed"
fi

# Test 5: Check port usage
log_info "Test 5: Checking port usage..."
if netstat -tlnp | grep -E ":(80|443)" | grep -q "$APP_NAME"; then
    log_success "Ports are listening correctly"
else
    log_warning "Port check failed"
fi

# Test 6: HTTP connectivity test
log_info "Test 6: Testing HTTP connectivity..."
if curl -f -s "http://$DOMAIN" > /dev/null 2>&1; then
    log_success "HTTP connectivity: OK"
else
    log_warning "HTTP connectivity: FAILED"
fi

# Test 7: HTTPS connectivity test (if mode supports it)
if [ "$MODE" != "http-only" ]; then
    log_info "Test 7: Testing HTTPS connectivity..."
    if curl -f -s -k "https://$DOMAIN" > /dev/null 2>&1; then
        log_success "HTTPS connectivity: OK"
    else
        log_warning "HTTPS connectivity: FAILED (this might be normal for new domains)"
    fi
fi

# Test 8: Check for redirect behavior
log_info "Test 8: Testing redirect behavior..."
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN")
HTTPS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$DOMAIN")

if [ "$MODE" = "dual" ]; then
    if [ "$HTTP_RESPONSE" = "200" ] && [ "$HTTPS_RESPONSE" = "200" ]; then
        log_success "Dual mode: Both HTTP and HTTPS return 200 (no redirect)"
    else
        log_warning "Dual mode: Unexpected response codes (HTTP: $HTTP_RESPONSE, HTTPS: $HTTPS_RESPONSE)"
    fi
elif [ "$MODE" = "https-only" ]; then
    if [ "$HTTP_RESPONSE" = "301" ] || [ "$HTTP_RESPONSE" = "302" ]; then
        log_success "HTTPS-only mode: HTTP redirects to HTTPS correctly"
    else
        log_warning "HTTPS-only mode: HTTP should redirect but got $HTTP_RESPONSE"
    fi
elif [ "$MODE" = "http-only" ]; then
    if [ "$HTTP_RESPONSE" = "200" ]; then
        log_success "HTTP-only mode: HTTP works correctly"
    else
        log_warning "HTTP-only mode: HTTP returned $HTTP_RESPONSE"
    fi
fi

# Test 9: Performance test
log_info "Test 9: Performance test..."
echo "Testing 10 requests to HTTP..."
for i in {1..10}; do
    curl -s -o /dev/null "http://$DOMAIN" &
done
wait
log_success "HTTP performance test completed"

if [ "$MODE" != "http-only" ]; then
    echo "Testing 10 requests to HTTPS..."
    for i in {1..10}; do
        curl -s -o /dev/null -k "https://$DOMAIN" &
    done
    wait
    log_success "HTTPS performance test completed"
fi

# Test 10: Resource usage
log_info "Test 10: Checking resource usage..."
echo "Memory usage:"
ps aux | grep "octane:frankenphp" | grep "$APP_NAME" | awk '{print $6/1024 " MB"}'

echo "CPU usage:"
ps aux | grep "octane:frankenphp" | grep "$APP_NAME" | awk '{print $3 "%"}'

# Summary
echo ""
log_info "🎉 Dual Mode Testing Summary"
echo "================================"
echo "App Name: $APP_NAME"
echo "Domain: $DOMAIN"
echo "Mode: $MODE"
echo "HTTP Response: $HTTP_RESPONSE"
if [ "$MODE" != "http-only" ]; then
    echo "HTTPS Response: $HTTPS_RESPONSE"
fi
echo ""

# Cleanup option
read -p "Do you want to clean up the test app? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleaning up test app..."
    sudo ./install.sh remove "$APP_NAME"
    log_success "Test app removed"
fi

log_success "Dual mode testing completed!"
echo ""
echo "📖 For more information, see: DUAL_MODE_GUIDE.md" 