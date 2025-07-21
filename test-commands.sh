#!/bin/bash

# =============================================
# FrankenPHP Multi-App Deployer Testing Script
# Script untuk menguji semua command yang tersedia
# =============================================

set -e

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to log test results
log_test() {
    local test_name="$1"
    local status="$2"
    local output="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        if [ -n "$output" ]; then
            echo -e "${YELLOW}   Output: $output${NC}"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Function to run command and test
test_command() {
    local test_name="$1"
    local command="$2"
    local expected_in_output="$3"
    
    echo -e "${BLUE}🧪 Testing: $test_name${NC}"
    
    # Run command and capture output and exit code
    output=$(eval "$command" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    
    # Check if command succeeded and contains expected output
    if [ $exit_code -eq 0 ] && [[ "$output" =~ $expected_in_output ]]; then
        log_test "$test_name" "PASS"
    else
        log_test "$test_name" "FAIL" "Exit code: $exit_code, Expected: '$expected_in_output'"
    fi
    
    echo ""
}

# Function to test help and info commands
test_info_commands() {
    echo -e "${BLUE}📋 Testing Information Commands${NC}"
    echo "=========================================="
    
    test_command "Help Command" "./install.sh --help" "FrankenPHP Multi-App Deployer"
    test_command "List Apps" "./install.sh list" "Listing all Laravel apps"
    test_command "Systemd List" "./install.sh systemd:list" "Laravel Octane systemd services"
    test_command "Database Status" "./install.sh db:status" "MySQL Service Status"
    test_command "Database List" "./install.sh db:list" "Laravel applications database status"
    test_command "SSL Info" "./install.sh ssl:info" "SSL Information - FrankenPHP Built-in"
    test_command "Debug System" "./install.sh debug" "System Debug Overview"
}

# Function to test validation commands
test_validation_commands() {
    echo -e "${BLUE}🔍 Testing Validation Commands${NC}"
    echo "=========================================="
    
    # Test invalid commands
    test_command "Invalid Command" "./install.sh invalid_command 2>&1 | grep -q 'Unknown command'" "Unknown command"
    
    # Test commands with missing parameters
    output=$(./install.sh install 2>&1) || true
    if [[ "$output" =~ "Usage:" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "required" ]]; then
        log_test "Missing Parameters - Install" "PASS"
    else
        log_test "Missing Parameters - Install" "FAIL" "Should show usage or error"
    fi
    
    output=$(./install.sh remove 2>&1) || true
    if [[ "$output" =~ "Usage:" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "required" ]]; then
        log_test "Missing Parameters - Remove" "PASS"
    else
        log_test "Missing Parameters - Remove" "FAIL" "Should show usage or error"
    fi
}

# Function to test app management commands (without actually creating apps)
test_app_management() {
    echo -e "${BLUE}📱 Testing App Management Commands${NC}"
    echo "=========================================="
    
    # Test status for non-existent app
    output=$(./install.sh status nonexistent 2>&1) || true
    if [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "does not exist" ]]; then
        log_test "Status Non-existent App" "PASS"
    else
        log_test "Status Non-existent App" "FAIL" "Should show error for non-existent app"
    fi
    
    # Test logs for non-existent app
    output=$(./install.sh logs nonexistent 2>&1) || true
    if [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "does not exist" ]]; then
        log_test "Logs Non-existent App" "PASS"
    else
        log_test "Logs Non-existent App" "FAIL" "Should show error for non-existent app"
    fi
}

# Function to test octane commands
test_octane_commands() {
    echo -e "${BLUE}🚀 Testing Octane Commands${NC}"
    echo "=========================================="
    
    # Test octane commands for non-existent app
    output=$(./install.sh octane:status nonexistent 2>&1) || true
    if [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "could not be found" ]]; then
        log_test "Octane Status Non-existent" "PASS"
    else
        log_test "Octane Status Non-existent" "FAIL" "Should show error for non-existent app"
    fi
    
    # Test dual mode commands
    output=$(./install.sh octane:dual 2>&1) || true
    if [[ "$output" =~ "Usage:" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "required" ]]; then
        log_test "Octane Dual Missing Params" "PASS"
    else
        log_test "Octane Dual Missing Params" "FAIL" "Should show usage error"
    fi
}

# Function to test database commands
test_database_commands() {
    echo -e "${BLUE}🗄️ Testing Database Commands${NC}"
    echo "=========================================="
    
    # Test database commands for non-existent app
    output=$(./install.sh db:check nonexistent 2>&1) || true
    if [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "does not exist" ]]; then
        log_test "DB Check Non-existent" "PASS"
    else
        log_test "DB Check Non-existent" "FAIL" "Should show error for non-existent app"
    fi
}

# Function to test systemd commands
test_systemd_commands() {
    echo -e "${BLUE}⚙️ Testing Systemd Commands${NC}"
    echo "=========================================="
    
    # Test systemd commands for non-existent app
    output=$(./install.sh systemd:check nonexistent 2>&1) || true
    if [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Error" ]] || [[ "$output" =~ "could not be found" ]]; then
        log_test "Systemd Check Non-existent" "PASS"
    else
        log_test "Systemd Check Non-existent" "FAIL" "Should show error for non-existent app"
    fi
}

# Main testing function
main() {
    echo -e "${GREEN}🧪 FrankenPHP Multi-App Deployer - Command Testing${NC}"
    echo "=================================================="
    echo "Testing all available commands..."
    echo ""
    
    # Make sure script is executable
    chmod +x install.sh
    
    # Run all test suites
    test_info_commands
    test_validation_commands
    test_app_management
    test_octane_commands
    test_database_commands
    test_systemd_commands
    
    # Show final results
    echo ""
    echo -e "${BLUE}📊 Test Results Summary${NC}"
    echo "=========================="
    echo -e "Total Tests: ${YELLOW}$TOTAL_TESTS${NC}"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed! Script is working correctly.${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed. Please check the output above.${NC}"
        exit 1
    fi
}

# Check if script exists
if [ ! -f "./install.sh" ]; then
    echo -e "${RED}❌ Error: install.sh not found in current directory${NC}"
    exit 1
fi

# Run main function
main "$@"
