#!/usr/bin/env bash
# Debug script to test gum and fx

echo "=========================================="
echo "DIAGNOSTIC TEST SCRIPT"
echo "=========================================="
echo

# Test 1: Check if running as root
echo "1. Checking user permissions..."
echo "   Current user: $(whoami)"
echo "   EUID: $EUID"
echo "   SUDO_USER: ${SUDO_USER:-not set}"
echo

# Test 2: Check if gum is installed and working
echo "2. Testing gum installation..."
if command -v gum &>/dev/null; then
    echo "   ✓ gum is installed: $(which gum)"
    echo "   Version: $(gum --version 2>&1 || echo 'version check failed')"

    echo
    echo "   Testing gum choose with simple options..."
    echo "   (This should show a menu - use arrow keys, Enter to select, ESC to cancel)"
    echo

    # Test gum choose
    result=$(gum choose --height 10 "Option 1" "Option 2" "Option 3" "Cancel" 2>&1)
    exit_code=$?

    echo
    echo "   Selected: '$result'"
    echo "   Exit code: $exit_code"
else
    echo "   ✗ gum is NOT installed"
    echo "   Install with: sudo apt install gum"
fi
echo

# Test 3: Check if fx is installed
echo "3. Testing fx installation..."
if command -v fx &>/dev/null; then
    echo "   ✓ fx is installed: $(which fx)"

    # Check if it's a snap
    if [[ "$(which fx)" == *"snap"* ]]; then
        echo "   Installed via: snap"
        snap info fx 2>&1 | head -5
    fi
else
    echo "   ✗ fx is NOT installed"
fi
echo

# Test 4: Test fx permissions
echo "4. Testing fx file access..."
TEST_FILE="/etc/cjdroute_46010.conf"

if [ -f "$TEST_FILE" ]; then
    echo "   Test file: $TEST_FILE"
    echo "   File exists: Yes"
    echo "   File permissions: $(ls -l $TEST_FILE)"
    echo "   Can read as current user: $([ -r "$TEST_FILE" ] && echo 'Yes' || echo 'No')"

    echo
    echo "   Attempting to open with fx..."
    if command -v fx &>/dev/null; then
        # Try to run fx with verbose output
        timeout 2s fx "$TEST_FILE" 2>&1 &
        FX_PID=$!
        sleep 1

        if ps -p $FX_PID > /dev/null 2>&1; then
            echo "   ✓ fx started successfully (PID: $FX_PID)"
            kill $FX_PID 2>/dev/null
        else
            echo "   ✗ fx failed to start or exited immediately"
        fi
    fi
else
    echo "   ✗ Test file not found: $TEST_FILE"
fi
echo

# Test 5: Test bash array syntax
echo "5. Testing bash array syntax compatibility..."
declare -a test_array=()

# Test the problematic syntax
if bash -c 'declare -a arr=(); echo ${#arr[@]:-0}' 2>/dev/null; then
    echo "   ✓ Syntax ${#arr[@]:-0} is supported"
else
    echo "   ✗ Syntax ${#arr[@]:-0} is NOT supported (bash version too old)"
    echo "   Bash version: $BASH_VERSION"
    echo "   Need to use alternative syntax"
fi
echo

# Test alternative syntax
LENGTH=${#test_array[@]}
LENGTH=${LENGTH:-0}
echo "   Alternative method result: $LENGTH"
echo

echo "=========================================="
echo "DIAGNOSTIC COMPLETE"
echo "=========================================="
echo
echo "Please copy ALL output above and send it back."
