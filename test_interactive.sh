#!/usr/bin/env bash
# Test script to diagnose gum TTY issues and compare with fzf

echo "=========================================="
echo "INTERACTIVE MENU TEST"
echo "=========================================="
echo

# Check TTY status
echo "1. Checking TTY status..."
echo "   tty: $(tty 2>&1)"
echo "   TERM: ${TERM:-not set}"
echo "   Is TTY: $([ -t 0 ] && echo 'Yes (stdin)' || echo 'No (stdin)')"
echo "   Is TTY output: $([ -t 1 ] && echo 'Yes (stdout)' || echo 'No (stdout)')"
echo "   Terminal size: $(tput cols 2>/dev/null)x$(tput lines 2>/dev/null)"
echo

# Test 1: Basic gum choose
echo "=========================================="
echo "TEST 1: Basic gum choose"
echo "=========================================="
echo "This should show a menu with 4 peers."
echo "Use arrow keys to move, SPACE to select, ENTER to confirm"
echo
sleep 2

if command -v gum &>/dev/null; then
    result=$(gum choose --no-limit --height 10 \
        "[ ] 192.168.1.1 | ESTABLISHED | Quality: 95%" \
        "[ ] 192.168.1.2 | UNRESPONSIVE | Quality: 20%" \
        "[ ] 192.168.1.3 | ESTABLISHED | Quality: 88%" \
        "[ ] 192.168.1.4 | UNRESPONSIVE | Quality: 0%" \
        2>&1)
    exit_code=$?

    echo
    echo "Result:"
    if [ -n "$result" ]; then
        echo "$result" | while IFS= read -r line; do
            echo "  - Selected: $line"
        done
    else
        echo "  (Nothing selected or cancelled)"
    fi
    echo "Exit code: $exit_code"
else
    echo "✗ gum not installed"
fi

echo
echo "Press Enter to continue to next test..."
read -r

# Test 2: fzf multi-select
echo "=========================================="
echo "TEST 2: fzf multi-select (for comparison)"
echo "=========================================="
echo "This should show a menu with checkboxes."
echo "Use arrow keys to move, TAB to select, ENTER to confirm"
echo
sleep 2

if command -v fzf &>/dev/null; then
    result=$(printf "%s\n" \
        "192.168.1.1 | ESTABLISHED | Quality: 95%" \
        "192.168.1.2 | UNRESPONSIVE | Quality: 20%" \
        "192.168.1.3 | ESTABLISHED | Quality: 88%" \
        "192.168.1.4 | UNRESPONSIVE | Quality: 0%" \
        | fzf --multi --height 10 --border --header "Select peers (Tab to toggle)" 2>&1)
    exit_code=$?

    echo
    echo "Result:"
    if [ -n "$result" ]; then
        echo "$result" | while IFS= read -r line; do
            echo "  - Selected: $line"
        done
    else
        echo "  (Nothing selected or cancelled)"
    fi
    echo "Exit code: $exit_code"
else
    echo "✗ fzf not installed"
    echo "  Install with: sudo apt install fzf"
fi

echo
echo "Press Enter to continue to next test..."
read -r

# Test 3: Try gum with explicit TTY
echo "=========================================="
echo "TEST 3: gum with explicit TTY redirection"
echo "=========================================="
echo "Trying to force TTY for gum..."
echo
sleep 2

if command -v gum &>/dev/null; then
    result=$(gum choose --no-limit --height 10 \
        "[ ] 192.168.1.1 | ESTABLISHED | Quality: 95%" \
        "[ ] 192.168.1.2 | UNRESPONSIVE | Quality: 20%" \
        "[ ] 192.168.1.3 | ESTABLISHED | Quality: 88%" \
        "[ ] 192.168.1.4 | UNRESPONSIVE | Quality: 0%" \
        </dev/tty >/dev/tty 2>&1)
    exit_code=$?

    echo
    echo "Result:"
    if [ -n "$result" ]; then
        echo "$result" | while IFS= read -r line; do
            echo "  - Selected: $line"
        done
    else
        echo "  (Nothing selected or cancelled)"
    fi
    echo "Exit code: $exit_code"
else
    echo "✗ gum not installed"
fi

echo
echo "=========================================="
echo "COMPARISON SUMMARY"
echo "=========================================="
echo
echo "Which one worked better for you?"
echo "1) gum (Tests 1 and 3)"
echo "2) fzf (Test 2)"
echo "3) Neither worked"
echo
echo "Type your answer (1, 2, or 3) and tell me what you saw!"
echo "=========================================="
