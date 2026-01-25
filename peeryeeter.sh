#!/usr/bin/env bash
# CJDNS Peer Manager - PeerYeeter
# Interactive tool for managing CJDNS peers with quality tracking

set -euo pipefail

# Check for sudo/root access - Required for /etc/ operations
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges to:"
    echo "  - Access and modify cjdns config files in /etc/"
    echo "  - Create backups in /etc/cjdns_backups/"
    echo "  - Restart cjdns service"
    echo
    echo "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

# Get script directory (for portable relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/peers.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/database.sh"
source "$SCRIPT_DIR/lib/master_list.sh"
source "$SCRIPT_DIR/lib/editor.sh"
source "$SCRIPT_DIR/lib/prerequisites.sh"
source "$SCRIPT_DIR/lib/interactive.sh"
source "$SCRIPT_DIR/lib/guided_editor.sh"

# Global variables (will be set during initialization)
CJDNS_CONFIG=""
CJDNS_SERVICE=""
CJDROUTE_BIN=""
ADMIN_IP=""
ADMIN_PORT=""
ADMIN_PASSWORD=""
WORK_DIR=""

# Cleanup on exit
cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

# Initialize - detect cjdns installation and config
initialize() {
    clear
    print_ascii_header
    print_header "PeerYeeter - Initialization"

    # Check for required tools
    print_subheader "Checking Requirements"

    local missing_tools=()

    if ! command -v jq &>/dev/null; then
        missing_tools+=("jq")
    fi

    if ! command -v git &>/dev/null; then
        missing_tools+=("git")
    fi

    if ! command -v wget &>/dev/null; then
        missing_tools+=("wget")
    fi

    if ! command -v sqlite3 &>/dev/null; then
        missing_tools+=("sqlite3")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo
        echo "Please install them:"
        echo "  sudo apt-get install ${missing_tools[*]}"
        exit 1
    fi

    print_success "All required tools found (jq, git, wget, sqlite3)"

    # Check for gum (interactive menu tool)
    print_subheader "Checking Interactive Tools"

    if ! check_gum; then
        print_warning "gum not found (required for interactive menus)"
        echo
        if ! check_prerequisites; then
            exit 1
        fi
    else
        print_success "gum found (interactive menus enabled)"
    fi

    # Check cjdnstool
    print_subheader "Checking cjdnstool"

    local cjdnstool_version
    if cjdnstool_version=$(check_cjdnstool); then
        print_success "cjdnstool found: $cjdnstool_version"
    else
        print_error "cjdnstool not found"
        echo
        echo "cjdnstool is required to communicate with cjdns."
        echo "Please install it from: https://github.com/furetosan/cjdnstool"
        exit 1
    fi

    # Detect cjdns config and service
    print_subheader "Detecting CJDNS Configuration"

    local detection_result
    local service_detected=0
    if detection_result=$(detect_cjdns_service); then
        CJDNS_SERVICE=$(echo "$detection_result" | cut -d'|' -f1)
        CJDNS_CONFIG=$(echo "$detection_result" | cut -d'|' -f2)

        print_success "Detected cjdns service: $CJDNS_SERVICE"
        print_success "Detected config file: $CJDNS_CONFIG"
        echo

        if ! ask_yes_no "Are these settings correct?"; then
            CJDNS_CONFIG=""
            CJDNS_SERVICE=""
        else
            service_detected=1
        fi
    fi

    # Manual configuration if auto-detection failed or was rejected
    if [ -z "$CJDNS_CONFIG" ]; then
        print_warning "Auto-detection failed or was rejected"
        print_subheader "Manual Configuration"
        echo

        # Prompt for service name
        echo "CJDNS Service Name (EXAMPLE: cjdns.service)"
        echo "If your service has a different name or you don't have a systemd service,"
        echo "you can enter it here or leave blank to continue without service management."
        echo
        CJDNS_SERVICE=$(ask_input "Service name (or press Enter to skip)" "")

        # Validate service if provided
        if [ -n "$CJDNS_SERVICE" ]; then
            echo
            print_info "Validating service: $CJDNS_SERVICE"
            if systemctl list-unit-files "$CJDNS_SERVICE" &>/dev/null; then
                print_success "Service found: $CJDNS_SERVICE"
                service_detected=1
            else
                print_warning "Service '$CJDNS_SERVICE' not found on this system"
                echo
                if ask_yes_no "Continue without service management? (You'll need to restart cjdns manually)"; then
                    print_info "Continuing without service management"
                    CJDNS_SERVICE=""
                else
                    if ask_yes_no "Try a different service name?"; then
                        CJDNS_SERVICE=$(ask_input "Service name")
                        if systemctl list-unit-files "$CJDNS_SERVICE" &>/dev/null; then
                            print_success "Service found: $CJDNS_SERVICE"
                            service_detected=1
                        else
                            print_error "Service still not found. Continuing without service management."
                            CJDNS_SERVICE=""
                        fi
                    else
                        print_info "Continuing without service management"
                        CJDNS_SERVICE=""
                    fi
                fi
            fi
        fi

        # Prompt for config file location
        echo
        echo "Config file location (ex. /etc/cjdroute_PORT.conf):"
        echo "This is REQUIRED for PeerYeeter to function."
        echo

        # Try to find configs as suggestions
        local configs
        mapfile -t configs < <(list_cjdns_configs)

        if [ ${#configs[@]} -gt 0 ]; then
            print_info "Found these config files:"
            for cfg in "${configs[@]}"; do
                echo "  - $cfg"
            done
            echo
        fi

        while true; do
            CJDNS_CONFIG=$(ask_input "Config file path")

            # Validate config file
            if [ ! -f "$CJDNS_CONFIG" ]; then
                print_error "File not found: $CJDNS_CONFIG"
                echo
                if ask_yes_no "Try again?"; then
                    continue
                else
                    print_error "Cannot proceed without a valid config file"
                    exit 1
                fi
            else
                break
            fi
        done
    fi

    # Warn if service management is disabled
    if [ -z "$CJDNS_SERVICE" ] && [ "$service_detected" -eq 0 ]; then
        echo
        print_warning "Service management disabled - you'll need to restart cjdns manually after config changes"
    fi

    # Detect cjdroute binary
    print_subheader "Detecting cjdroute Binary"

    if CJDROUTE_BIN=$(detect_cjdroute_binary "$CJDNS_SERVICE"); then
        print_success "Found cjdroute: $CJDROUTE_BIN"
    else
        print_warning "cjdroute binary not found - config validation will be limited"
        print_info "The program will still work, but cannot validate configs before applying them"
        echo
        if ask_yes_no "Continue without cjdroute validation?"; then
            print_info "Continuing with limited validation (JSON structure only)"
        else
            print_error "Cannot proceed without cjdroute binary"
            echo
            echo "Please ensure cjdroute is installed and in your PATH, or install it from:"
            echo "  https://github.com/cjdelisle/cjdns"
            exit 1
        fi
    fi

    # Validate config file
    print_subheader "Validating Configuration"

    if ! validate_config "$CJDNS_CONFIG"; then
        print_error "Invalid or corrupted config file: $CJDNS_CONFIG"
        exit 1
    fi

    print_success "Config file is valid JSON"

    # Extract admin connection info
    local admin_info
    if admin_info=$(get_admin_info "$CJDNS_CONFIG"); then
        local bind=$(echo "$admin_info" | cut -d'|' -f1)
        ADMIN_IP=$(echo "$bind" | cut -d':' -f1)
        ADMIN_PORT=$(echo "$bind" | cut -d':' -f2)
        ADMIN_PASSWORD=$(echo "$admin_info" | cut -d'|' -f2)

        print_success "Admin interface: $ADMIN_IP:$ADMIN_PORT"

        # Test connection
        if test_cjdnstool_connection "$ADMIN_IP" "$ADMIN_PORT" "$ADMIN_PASSWORD"; then
            print_success "Successfully connected to cjdns"
        else
            print_error "Cannot connect to cjdns admin interface"
            echo
            echo "Make sure cjdns is running:"
            if [ -n "$CJDNS_SERVICE" ]; then
                echo "  sudo systemctl start $CJDNS_SERVICE"
            else
                echo "  sudo systemctl start cjdroute"
            fi
            exit 1
        fi
    else
        print_error "Could not extract admin connection info from config"
        exit 1
    fi

    # Initialize database and local address database
    print_subheader "Initializing Database & Local Address Database"

    # Create backup directory with proper permissions
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        print_error "Cannot create backup directory: $BACKUP_DIR"
        exit 1
    fi

    # Ensure backup directory has proper permissions
    chmod 755 "$BACKUP_DIR" 2>/dev/null

    if init_database; then
        print_success "Peer tracking database ready"
    else
        print_error "Failed to initialize database"
        exit 1
    fi

    if init_master_list; then
        print_success "Locally stored address list downloaded and initialized"
    else
        print_error "Failed to initialize locally stored address list"
        exit 1
    fi

    # Show current stats from locally stored address list
    local counts=$(get_master_counts)
    local local_ipv4=$(echo "$counts" | cut -d'|' -f1)
    local local_ipv6=$(echo "$counts" | cut -d'|' -f2)

    if [ "$local_ipv4" -gt 0 ] || [ "$local_ipv6" -gt 0 ]; then
        print_success "Locally stored address list contains: $local_ipv4 IPv4 addresses, and $local_ipv6 IPv6 addresses"
    else
        print_error "Locally stored address list contains: $local_ipv4 IPv4 addresses, and $local_ipv6 IPv6 addresses"
    fi

    # Show current config file peer counts
    local config_ipv4=$(get_peer_count "$CJDNS_CONFIG" 0)
    local config_ipv6=$(get_peer_count "$CJDNS_CONFIG" 1)

    if [ "$config_ipv4" -gt 0 ] || [ "$config_ipv6" -gt 0 ]; then
        print_success "CJDNS config file currently contains: $config_ipv4 IPv4 peers, and $config_ipv6 IPv6 peers"
    else
        print_error "CJDNS config file currently contains: $config_ipv4 IPv4 peers, and $config_ipv6 IPv6 peers"
    fi

    # Create working directory
    WORK_DIR=$(mktemp -d -t cjdns-manager.XXXXXX)
    print_success "Working directory: $WORK_DIR"

    echo
    print_success "Initialization complete!"
    echo
    read -p "Press Enter to continue..."
}

# Main menu
show_menu() {
    clear
    print_ascii_header
    print_header "PeerYeeter - Main Menu"
    echo "Config: $CJDNS_CONFIG"
    echo "Backup: $BACKUP_DIR"
    echo
    echo "1) 🧙 Peer Adding Wizard (Recommended)"
    echo "2) 🔍 Discover & Preview Peers"
    echo "3) ✏️  Edit Config File"
    echo "4) 🗑️  View Status & Remove Peers"
    echo "5) 📊 View Peer Status"
    echo "6) ⚙️  Maintenance & Settings"
    echo "0) Exit"
    echo
}

# Peer Adding Wizard - Main automated workflow
peer_adding_wizard() {
    clear
    print_ascii_header
    print_header "Peer Adding Wizard"

    print_info "This wizard will guide you through discovering, testing, and adding peers."
    echo

    # Verify config structure
    local ipv4_interface_exists=$(jq -e '.interfaces.UDPInterface[0]' "$CJDNS_CONFIG" &>/dev/null && echo 1 || echo 0)
    local ipv6_interface_exists=$(jq -e '.interfaces.UDPInterface[1]' "$CJDNS_CONFIG" &>/dev/null && echo 1 || echo 0)

    # Step 1: Ask protocol selection
    print_subheader "Step 1: Protocol Selection"
    echo "What protocol would you like to discover peers for?"
    echo "  4) IPv4 only"
    echo "  6) IPv6 only"
    echo "  B) Both IPv4 and IPv6"
    echo "  0) Cancel and return to main menu"
    echo

    local protocol
    while true; do
        read -p "Enter selection (4/6/B/0): " -r protocol < /dev/tty
        case "$protocol" in
            4|[Ii][Pp][Vv]4)
                if [ "$ipv4_interface_exists" -eq 0 ]; then
                    print_error "IPv4 interface (UDPInterface[0]) not found in config!"
                    continue
                fi
                protocol="ipv4"
                print_success "IPv4 only selected"
                break
                ;;
            6|[Ii][Pp][Vv]6)
                if [ "$ipv6_interface_exists" -eq 0 ]; then
                    print_error "IPv6 interface (UDPInterface[1]) not found in config!"
                    continue
                fi
                protocol="ipv6"
                print_success "IPv6 only selected"
                break
                ;;
            [Bb]|[Bb][Oo][Tt][Hh])
                if [ "$ipv4_interface_exists" -eq 0 ] || [ "$ipv6_interface_exists" -eq 0 ]; then
                    print_error "Both interfaces not available in config!"
                    print_info "IPv4: $([ "$ipv4_interface_exists" -eq 1 ] && echo "Available" || echo "Missing")"
                    print_info "IPv6: $([ "$ipv6_interface_exists" -eq 1 ] && echo "Available" || echo "Missing")"
                    continue
                fi
                protocol="both"
                print_success "Both IPv4 and IPv6 selected"
                break
                ;;
            0|[Cc]|[Cc][Aa][Nn][Cc][Ee][Ll])
                print_info "Cancelled"
                echo
                read -p "Press Enter to continue..."
                return
                ;;
            *)
                print_error "Please enter 4, 6, B, or 0"
                ;;
        esac
    done
    echo

    # Step 2: Update local address database
    print_subheader "Step 2: Updating Local Address Database"
    echo
    print_bold "Fetching latest addresses from online sources..."
    echo

    local result=$(update_master_list)
    local master_ipv4=$(echo "$result" | cut -d'|' -f1)
    local master_ipv6=$(echo "$result" | cut -d'|' -f2)

    echo
    print_bold "✓ Local Address Database updated"
    echo -e "  ${YELLOW}$master_ipv4${NC} IPv4 addresses found"
    echo -e "  ${ORANGE}$master_ipv6${NC} IPv6 addresses found"
    echo

    # Step 3: Filter for new peers
    print_subheader "Step 3: Finding New Peers"

    local discovered_ipv4="$WORK_DIR/discovered_ipv4.json"
    local discovered_ipv6="$WORK_DIR/discovered_ipv6.json"
    local new_ipv4="$WORK_DIR/new_ipv4.json"
    local new_ipv6="$WORK_DIR/new_ipv6.json"
    local updates_ipv4="$WORK_DIR/updates_ipv4.json"
    local updates_ipv6="$WORK_DIR/updates_ipv6.json"

    # Get peers from local address database
    if [ "$protocol" = "ipv4" ] || [ "$protocol" = "both" ]; then
        get_master_peers "ipv4" > "$discovered_ipv4"
    else
        echo "{}" > "$discovered_ipv4"
    fi

    if [ "$protocol" = "ipv6" ] || [ "$protocol" = "both" ]; then
        get_master_peers "ipv6" > "$discovered_ipv6"
    else
        echo "{}" > "$discovered_ipv6"
    fi

    # Smart duplicate detection (non-interactive mode - just collect data)
    local new_counts_ipv4="0|0"
    local new_counts_ipv6="0|0"

    if [ "$protocol" = "ipv4" ] || [ "$protocol" = "both" ]; then
        new_counts_ipv4=$(smart_duplicate_check "$discovered_ipv4" "$CJDNS_CONFIG" 0 "$new_ipv4" "$updates_ipv4" 0)
    else
        echo "{}" > "$new_ipv4"
        echo "{}" > "$updates_ipv4"
    fi

    if [ "$protocol" = "ipv6" ] || [ "$protocol" = "both" ]; then
        new_counts_ipv6=$(smart_duplicate_check "$discovered_ipv6" "$CJDNS_CONFIG" 1 "$new_ipv6" "$updates_ipv6" 0)
    else
        echo "{}" > "$new_ipv6"
        echo "{}" > "$updates_ipv6"
    fi

    local new_ipv4_count=$(echo "$new_counts_ipv4" | cut -d'|' -f1)
    local update_ipv4_count=$(echo "$new_counts_ipv4" | cut -d'|' -f2)
    local new_ipv6_count=$(echo "$new_counts_ipv6" | cut -d'|' -f1)
    local update_ipv6_count=$(echo "$new_counts_ipv6" | cut -d'|' -f2)

    echo
    echo "Summary:"
    echo -e "  ${YELLOW}$new_ipv4_count${NC} new IPv4 peers not in config"
    echo -e "  ${ORANGE}$new_ipv6_count${NC} new IPv6 peers not in config"
    if [ "$update_ipv4_count" -gt 0 ] || [ "$update_ipv6_count" -gt 0 ]; then
        echo
        print_warning "═══════════════════════════════════════════════════════════════"
        print_warning "  Peers with updated credentials detected!"
        print_warning "═══════════════════════════════════════════════════════════════"
        echo
        print_info "These peers are ALREADY in your config, but have newer metadata in the database:"
        echo

        # List IPv4 peers with updates
        if [ "$update_ipv4_count" -gt 0 ]; then
            echo -e "${YELLOW}IPv4 peers with updates ($update_ipv4_count):${NC}"
            jq -r 'keys[]' "$updates_ipv4" 2>/dev/null | while IFS= read -r addr; do
                echo -e "  ${YELLOW}•${NC} $addr"
            done
            echo
        fi

        # List IPv6 peers with updates
        if [ "$update_ipv6_count" -gt 0 ]; then
            echo -e "${ORANGE}IPv6 peers with updates ($update_ipv6_count):${NC}"
            jq -r 'keys[]' "$updates_ipv6" 2>/dev/null | while IFS= read -r addr; do
                echo -e "  ${ORANGE}•${NC} $addr"
            done
            echo
        fi

        echo -e "${DIM}These updates may include changes to: peerName, contact, location, gpg, etc.${NC}"
        echo -e "${DIM}(The password and publicKey remain the same - only metadata is updated)${NC}"
        echo

        # Always offer to show detailed preview
        if ask_yes_no "View detailed credential differences?"; then
            wizard_preview_updates "$updates_ipv4" "$updates_ipv6" "$CJDNS_CONFIG"
            echo
        fi
    fi
    echo

    if [ "$new_ipv4_count" -eq 0 ] && [ "$new_ipv6_count" -eq 0 ]; then
        print_warning "No new peers to add"
        if [ "$update_ipv4_count" -gt 0 ] || [ "$update_ipv6_count" -gt 0 ]; then
            print_info "But there are updated peer credentials available"
            if ask_yes_no "Apply updates now?"; then
                wizard_apply_updates "$updates_ipv4" "$updates_ipv6" "$update_ipv4_count" "$update_ipv6_count"
            fi
        fi
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Step 4: Test connectivity
    print_subheader "Step 4: Testing Connectivity"

    if ! ask_yes_no "Test connectivity to discovered peers? (May take several minutes)"; then
        print_info "Skipping connectivity tests"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    local active_ipv4="$WORK_DIR/active_ipv4.json"
    local active_ipv6="$WORK_DIR/active_ipv6.json"
    local inactive_ipv4="$WORK_DIR/inactive_ipv4.json"
    local inactive_ipv6="$WORK_DIR/inactive_ipv6.json"

    wizard_test_peers "$new_ipv4" "$new_ipv6" "$active_ipv4" "$active_ipv6" "$inactive_ipv4" "$inactive_ipv6"

    local active_ipv4_count=$(jq 'length' "$active_ipv4")
    local active_ipv6_count=$(jq 'length' "$active_ipv6")
    local inactive_ipv4_count=$(jq 'length' "$inactive_ipv4")
    local inactive_ipv6_count=$(jq 'length' "$inactive_ipv6")

    echo
    echo "Local address database test results:"
    print_success "  Active: $active_ipv4_count IPv4, $active_ipv6_count IPv6"
    print_warning "  Inactive: $inactive_ipv4_count IPv4, $inactive_ipv6_count IPv6"
    echo

    # Step 5: Selection options
    print_subheader "Step 5: Select Peers to Add"
    echo
    echo "Summary:"
    echo "  • Active IPv4 peers: $active_ipv4_count"
    echo "  • Active IPv6 peers: $active_ipv6_count"
    echo "  • Credential updates: $update_ipv4_count IPv4, $update_ipv6_count IPv6"
    echo

    wizard_select_and_add "$active_ipv4" "$active_ipv6" "$inactive_ipv4" "$inactive_ipv6" \
                          "$updates_ipv4" "$updates_ipv6" \
                          "$active_ipv4_count" "$active_ipv6_count" \
                          "$update_ipv4_count" "$update_ipv6_count"

    echo
    read -p "Press Enter to continue..."
}

# Wizard helper: test peers
wizard_test_peers() {
    local new_ipv4="$1"
    local new_ipv6="$2"
    local active_ipv4="$3"
    local active_ipv6="$4"
    local inactive_ipv4="$5"
    local inactive_ipv6="$6"

    echo "{}" > "$active_ipv4"
    echo "{}" > "$active_ipv6"
    echo "{}" > "$inactive_ipv4"
    echo "{}" > "$inactive_ipv6"

    local total_ipv4=$(jq 'length' "$new_ipv4")
    local total_ipv6=$(jq 'length' "$new_ipv6")

    # Test IPv4
    if [ "$total_ipv4" -gt 0 ]; then
        print_info "Testing $total_ipv4 IPv4 peers..."
        local tested=0
        local active=0

        while IFS= read -r addr; do
            tested=$((tested + 1))
            echo -n "[$tested/$total_ipv4] Testing $addr... "

            local peer_data=$(jq --arg addr "$addr" '.[$addr]' "$new_ipv4")

            if test_peer_connectivity "$addr" 2; then
                echo -e "${GREEN}✓${NC}"
                active=$((active + 1))
                jq -s --arg addr "$addr" --argjson peer "$peer_data" \
                    '.[0] + {($addr): $peer}' "$active_ipv4" > "$active_ipv4.tmp"
                mv "$active_ipv4.tmp" "$active_ipv4"
            else
                echo -e "${RED}✗${NC}"
                jq -s --arg addr "$addr" --argjson peer "$peer_data" \
                    '.[0] + {($addr): $peer}' "$inactive_ipv4" > "$inactive_ipv4.tmp"
                mv "$inactive_ipv4.tmp" "$inactive_ipv4"
            fi
        done < <(jq -r 'keys[]' "$new_ipv4")

        print_success "IPv4: $active active out of $tested"
    fi

    # Test IPv6
    if [ "$total_ipv6" -gt 0 ]; then
        print_info "Testing $total_ipv6 IPv6 peers..."
        local tested=0
        local active=0

        while IFS= read -r addr; do
            tested=$((tested + 1))
            echo -n "[$tested/$total_ipv6] Testing $addr... "

            local peer_data=$(jq --arg addr "$addr" '.[$addr]' "$new_ipv6")

            if test_peer_connectivity "$addr" 2; then
                echo -e "${GREEN}✓${NC}"
                active=$((active + 1))
                jq -s --arg addr "$addr" --argjson peer "$peer_data" \
                    '.[0] + {($addr): $peer}' "$active_ipv6" > "$active_ipv6.tmp"
                mv "$active_ipv6.tmp" "$active_ipv6"
            else
                echo -e "${RED}✗${NC}"
                jq -s --arg addr "$addr" --argjson peer "$peer_data" \
                    '.[0] + {($addr): $peer}' "$inactive_ipv6" > "$inactive_ipv6.tmp"
                mv "$inactive_ipv6.tmp" "$inactive_ipv6"
            fi
        done < <(jq -r 'keys[]' "$new_ipv6")

        print_success "IPv6: $active active out of $tested"
    fi
}

# Wizard helper: select and add peers
wizard_select_and_add() {
    local active_ipv4="$1"
    local active_ipv6="$2"
    local inactive_ipv4="$3"
    local inactive_ipv6="$4"
    local updates_ipv4="$5"
    local updates_ipv6="$6"
    local active_ipv4_count="$7"
    local active_ipv6_count="$8"
    local update_ipv4_count="$9"
    local update_ipv6_count="${10}"

    if [ "$active_ipv4_count" -eq 0 ] && [ "$active_ipv6_count" -eq 0 ]; then
        print_warning "No active peers found"
        return
    fi

    echo "What would you like to add?"
    echo "  A) All active peers (${active_ipv4_count} IPv4, ${active_ipv6_count} IPv6)"
    echo "  4) IPv4 active only ($active_ipv4_count peers)"
    echo "  6) IPv6 active only ($active_ipv6_count peers)"
    echo "  E) Experimental - Add ALL (including non-pingable)"
    echo "  C) Cancel"
    echo

    local selection
    while true; do
        read -p "Enter selection: " -r selection < /dev/tty < /dev/tty
        case "$selection" in
            [Aa])
                wizard_add_peers "$active_ipv4" "$active_ipv6" "$updates_ipv4" "$updates_ipv6" \
                                 "$active_ipv4_count" "$active_ipv6_count" "$update_ipv4_count" "$update_ipv6_count"
                return
                ;;
            4)
                wizard_add_peers "$active_ipv4" "$WORK_DIR/empty.json" "$updates_ipv4" "$WORK_DIR/empty.json" \
                                 "$active_ipv4_count" 0 "$update_ipv4_count" 0
                return
                ;;
            6)
                wizard_add_peers "$WORK_DIR/empty.json" "$active_ipv6" "$WORK_DIR/empty.json" "$updates_ipv6" \
                                 0 "$active_ipv6_count" 0 "$update_ipv6_count"
                return
                ;;
            [Ee])
                print_warning "EXPERIMENTAL: This will add peers that didn't respond to ping"
                if ask_yes_no "Are you sure?"; then
                    # Merge active + inactive
                    local all_ipv4="$WORK_DIR/all_ipv4.json"
                    local all_ipv6="$WORK_DIR/all_ipv6.json"
                    jq -s '.[0] * .[1]' "$active_ipv4" "$inactive_ipv4" > "$all_ipv4"
                    jq -s '.[0] * .[1]' "$active_ipv6" "$inactive_ipv6" > "$all_ipv6"
                    local all_ipv4_count=$(jq 'length' "$all_ipv4")
                    local all_ipv6_count=$(jq 'length' "$all_ipv6")
                    wizard_add_peers "$all_ipv4" "$all_ipv6" "$updates_ipv4" "$updates_ipv6" \
                                     "$all_ipv4_count" "$all_ipv6_count" "$update_ipv4_count" "$update_ipv6_count"
                fi
                return
                ;;
            [Cc])
                print_info "Cancelled"
                return
                ;;
            *)
                print_error "Invalid selection"
                ;;
        esac
    done
}

# Wizard helper: add peers to config
wizard_add_peers() {
    local peers_ipv4="$1"
    local peers_ipv6="$2"
    local updates_ipv4="$3"
    local updates_ipv6="$4"
    local count_ipv4="$5"
    local count_ipv6="$6"
    local update_ipv4_count="$7"
    local update_ipv6_count="$8"

    echo "{}" > "$WORK_DIR/empty.json"

    # Ask about removing unresponsive peers first
    print_subheader "Remove Unresponsive Peers"

    local peer_states="$WORK_DIR/peer_states.txt"
    get_current_peer_states "$ADMIN_IP" "$ADMIN_PORT" "$ADMIN_PASSWORD" "$peer_states"

    local unresponsive_count=$(grep -c "^UNRESPONSIVE|" "$peer_states" 2>/dev/null || echo 0)

    if [ "$unresponsive_count" -gt 0 ]; then
        print_warning "You have $unresponsive_count unresponsive peers in your config"
        if ask_yes_no "Remove unresponsive peers before adding new ones?"; then
            wizard_remove_unresponsive "$peer_states"
        fi
    fi

    # Backup config
    print_subheader "Creating Backup"
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    else
        print_error "Failed to create backup"
        return
    fi

    # Add peers
    print_subheader "Adding Peers to Config"
    echo
    print_info "Adding $count_ipv4 IPv4 peers and $count_ipv6 IPv6 peers to config..."
    echo

    local temp_config="$WORK_DIR/config.tmp"
    cp "$CJDNS_CONFIG" "$temp_config"

    local total_added=0

    if [ "$count_ipv4" -gt 0 ]; then
        echo -n "Adding IPv4 peers... "
        if add_peers_to_config "$temp_config" "$peers_ipv4" 0 "$temp_config.new"; then
            mv "$temp_config.new" "$temp_config"
            echo -e "${GREEN}✓${NC}"
            print_success "Added $count_ipv4 IPv4 peers to config"
            total_added=$((total_added + count_ipv4))
        else
            echo -e "${RED}✗${NC}"
            print_error "Failed to add IPv4 peers"
            echo
            print_info "Your config file was NOT modified (backup is safe at: $backup)"
            echo
            read -p "Press Enter to continue..."
            return
        fi
    fi

    if [ "$count_ipv6" -gt 0 ]; then
        echo -n "Adding IPv6 peers... "
        if add_peers_to_config "$temp_config" "$peers_ipv6" 1 "$temp_config.new"; then
            mv "$temp_config.new" "$temp_config"
            echo -e "${GREEN}✓${NC}"
            print_success "Added $count_ipv6 IPv6 peers to config"
            total_added=$((total_added + count_ipv6))
        else
            echo -e "${RED}✗${NC}"
            print_error "Failed to add IPv6 peers"
            echo
            print_info "Your config file was NOT modified (backup is safe at: $backup)"
            echo
            read -p "Press Enter to continue..."
            return
        fi
    fi

    # Ask about credential updates
    echo
    if [ "$update_ipv4_count" -gt 0 ] || [ "$update_ipv6_count" -gt 0 ]; then
        print_subheader "Credential Updates"
        print_info "You have $update_ipv4_count IPv4 and $update_ipv6_count IPv6 credential updates available"
        print_info "These are for peers ALREADY in your config with newer metadata"
        echo
        if ask_yes_no "Also apply credential updates while adding new peers?"; then
            if [ "$update_ipv4_count" -gt 0 ]; then
                echo -n "Applying IPv4 credential updates... "
                if apply_peer_updates "$temp_config" "$updates_ipv4" 0 "$temp_config.new"; then
                    mv "$temp_config.new" "$temp_config"
                    echo -e "${GREEN}✓${NC}"
                    print_success "Updated $update_ipv4_count IPv4 peer credentials"
                else
                    echo -e "${RED}✗${NC}"
                    print_warning "Failed to apply some IPv4 updates (continuing anyway)"
                fi
            fi

            if [ "$update_ipv6_count" -gt 0 ]; then
                echo -n "Applying IPv6 credential updates... "
                if apply_peer_updates "$temp_config" "$updates_ipv6" 1 "$temp_config.new"; then
                    mv "$temp_config.new" "$temp_config"
                    echo -e "${GREEN}✓${NC}"
                    print_success "Updated $update_ipv6_count IPv6 peer credentials"
                else
                    echo -e "${RED}✗${NC}"
                    print_warning "Failed to apply some IPv6 updates (continuing anyway)"
                fi
            fi
        else
            print_info "Skipping credential updates (only adding new peers)"
            # Zero out the counts so the summary is accurate
            update_ipv4_count=0
            update_ipv6_count=0
        fi
    fi

    # Validate and save
    echo
    echo -n "Validating new config file... "
    if validate_config "$temp_config"; then
        echo -e "${GREEN}✓${NC}"
        echo
        cp "$temp_config" "$CJDNS_CONFIG"
        echo
        echo "═══════════════════════════════════════════════════════════════"
        print_success "SUCCESS! Config updated successfully!"
        echo "═══════════════════════════════════════════════════════════════"
        echo
        echo "Summary of changes:"
        echo "  • Added $total_added new peers"
        echo "  • Updated $((update_ipv4_count + update_ipv6_count)) peer credentials"
        echo "  • Backup saved at: $backup"
        echo

        if ask_yes_no "Restart cjdns service now to apply changes?"; then
            restart_service
        else
            echo
            print_info "Remember to restart cjdns manually to apply these changes:"
            echo "  sudo systemctl restart ${CJDNS_SERVICE:-cjdns}"
        fi
    else
        echo -e "${RED}✗${NC}"
        echo
        print_error "Config validation FAILED - changes NOT applied"
        echo
        print_info "Your original config is safe and unchanged"
        print_info "Backup is available at: $backup"
        echo
        echo "This usually means:"
        echo "  • Invalid JSON was generated (please report this as a bug)"
        echo "  • Your config file has structural issues"
    fi
}

# Wizard helper: preview credential updates
wizard_preview_updates() {
    local updates_ipv4="$1"
    local updates_ipv6="$2"
    local config_file="$3"

    print_subheader "Credential Update Preview"
    echo
    print_info "Showing differences between current config and updated database info:"
    echo

    # Show IPv4 updates
    local ipv4_addrs=$(jq -r 'keys[]' "$updates_ipv4" 2>/dev/null)
    if [ -n "$ipv4_addrs" ]; then
        echo -e "${YELLOW}═══ IPv4 Updates ═══${NC}"
        echo
        local count=1
        while IFS= read -r addr; do
            [ -z "$addr" ] && continue

            echo -e "${BOLD}[$count] $addr${NC}"
            echo

            local current=$(jq --arg addr "$addr" '.interfaces.UDPInterface[0].connectTo[$addr]' "$config_file")
            local new=$(jq --arg addr "$addr" '.[$addr]' "$updates_ipv4")

            # Show all fields from both, highlighting differences
            local all_keys=$(echo "$current $new" | jq -s 'map(keys) | add | unique | .[]' -r)

            while IFS= read -r key; do
                [ -z "$key" ] && continue

                local current_val=$(echo "$current" | jq -r --arg k "$key" '.[$k] // "N/A"')
                local new_val=$(echo "$new" | jq -r --arg k "$key" '.[$k] // "N/A"')

                if [ "$current_val" != "$new_val" ]; then
                    echo -e "  ${RED}$key:${NC}"
                    echo -e "    ${DIM}Current:${NC} $current_val"
                    echo -e "    ${GREEN}New:${NC}     $new_val"
                else
                    echo -e "  ${DIM}$key: $current_val${NC}"
                fi
            done <<< "$all_keys"

            echo
            count=$((count + 1))
        done <<< "$ipv4_addrs"
    fi

    # Show IPv6 updates
    local ipv6_addrs=$(jq -r 'keys[]' "$updates_ipv6" 2>/dev/null)
    if [ -n "$ipv6_addrs" ]; then
        echo -e "${ORANGE}═══ IPv6 Updates ═══${NC}"
        echo
        local count=1
        while IFS= read -r addr; do
            [ -z "$addr" ] && continue

            echo -e "${BOLD}[$count] $addr${NC}"
            echo

            local current=$(jq --arg addr "$addr" '.interfaces.UDPInterface[1].connectTo[$addr]' "$config_file")
            local new=$(jq --arg addr "$addr" '.[$addr]' "$updates_ipv6")

            # Show all fields from both, highlighting differences
            local all_keys=$(echo "$current $new" | jq -s 'map(keys) | add | unique | .[]' -r)

            while IFS= read -r key; do
                [ -z "$key" ] && continue

                local current_val=$(echo "$current" | jq -r --arg k "$key" '.[$k] // "N/A"')
                local new_val=$(echo "$new" | jq -r --arg k "$key" '.[$k] // "N/A"')

                if [ "$current_val" != "$new_val" ]; then
                    echo -e "  ${RED}$key:${NC}"
                    echo -e "    ${DIM}Current:${NC} $current_val"
                    echo -e "    ${GREEN}New:${NC}     $new_val"
                else
                    echo -e "  ${DIM}$key: $current_val${NC}"
                fi
            done <<< "$all_keys"

            echo
            count=$((count + 1))
        done <<< "$ipv6_addrs"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Wizard helper: apply credential updates
wizard_apply_updates() {
    local updates_ipv4="$1"
    local updates_ipv6="$2"
    local update_ipv4_count="$3"
    local update_ipv6_count="$4"

    # Backup config
    print_subheader "Creating Backup"
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    else
        print_error "Failed to create backup"
        return
    fi

    local temp_config="$WORK_DIR/config.tmp"
    cp "$CJDNS_CONFIG" "$temp_config"

    if [ "$update_ipv4_count" -gt 0 ]; then
        if apply_peer_updates "$temp_config" "$updates_ipv4" 0 "$temp_config.new"; then
            mv "$temp_config.new" "$temp_config"
            print_success "Updated $update_ipv4_count IPv4 peers"
        fi
    fi

    if [ "$update_ipv6_count" -gt 0 ]; then
        if apply_peer_updates "$temp_config" "$updates_ipv6" 1 "$temp_config.new"; then
            mv "$temp_config.new" "$temp_config"
            print_success "Updated $update_ipv6_count IPv6 peers"
        fi
    fi

    if validate_config "$temp_config"; then
        cp "$temp_config" "$CJDNS_CONFIG"
        print_success "Config updated successfully!"

        if ask_yes_no "Restart cjdns now?"; then
            restart_service
        fi
    else
        print_error "Config validation failed"
    fi
}

# Wizard helper: remove unresponsive peers
wizard_remove_unresponsive() {
    local peer_states="$1"

    local unresponsive_ipv4="$WORK_DIR/unresponsive_ipv4.txt"
    local unresponsive_ipv6="$WORK_DIR/unresponsive_ipv6.txt"

    grep "^UNRESPONSIVE|" "$peer_states" | cut -d'|' -f2 | grep -v '^\[' > "$unresponsive_ipv4" 2>/dev/null || touch "$unresponsive_ipv4"
    grep "^UNRESPONSIVE|" "$peer_states" | cut -d'|' -f2 | grep '^\[' > "$unresponsive_ipv6" 2>/dev/null || touch "$unresponsive_ipv6"

    local count_ipv4=$(wc -l < "$unresponsive_ipv4")
    local count_ipv6=$(wc -l < "$unresponsive_ipv6")

    local temp_config="$WORK_DIR/config_remove.tmp"
    cp "$CJDNS_CONFIG" "$temp_config"

    if [ "$count_ipv4" -gt 0 ]; then
        mapfile -t dead_addrs < "$unresponsive_ipv4"
        remove_peers_from_config "$temp_config" 0 "$temp_config.new" "${dead_addrs[@]}"
        mv "$temp_config.new" "$temp_config"
    fi

    if [ "$count_ipv6" -gt 0 ]; then
        mapfile -t dead_addrs < "$unresponsive_ipv6"
        remove_peers_from_config "$temp_config" 1 "$temp_config.new" "${dead_addrs[@]}"
        mv "$temp_config.new" "$temp_config"
    fi

    if validate_config "$temp_config"; then
        cp "$temp_config" "$CJDNS_CONFIG"
        print_success "Removed $count_ipv4 IPv4 and $count_ipv6 IPv6 unresponsive peers"
    fi
}

# Discover & Preview Peers (read-only)
discover_preview() {
    clear
    print_ascii_header
    print_header "Discover & Preview Peers"

    print_info "Updating locally stored address list and analyzing available peers"
    echo

    # Update local address database
    print_subheader "Updating Local Address Database"
    echo -n "Fetching from peer sources... "
    local result=$(update_master_list 2>&1)
    local local_ipv4=$(echo "$result" | tail -1 | cut -d'|' -f1)
    local local_ipv6=$(echo "$result" | tail -1 | cut -d'|' -f2)
    print_success "Done"
    echo
    echo "  • Local Address Database: $local_ipv4 IPv4, $local_ipv6 IPv6 peers"

    # Get current config counts
    local config_ipv4=$(get_peer_count "$CJDNS_CONFIG" 0)
    local config_ipv6=$(get_peer_count "$CJDNS_CONFIG" 1)
    echo "  • CJDNS Config File: $config_ipv4 IPv4, $config_ipv6 IPv6 peers"
    echo

    # Filter for new peers
    print_subheader "Finding New Peers"
    local all_ipv4="$WORK_DIR/all_ipv4.json"
    local all_ipv6="$WORK_DIR/all_ipv6.json"
    local new_ipv4="$WORK_DIR/new_ipv4.json"
    local new_ipv6="$WORK_DIR/new_ipv6.json"
    local updates_ipv4="$WORK_DIR/updates_ipv4.json"
    local updates_ipv6="$WORK_DIR/updates_ipv6.json"

    get_master_peers "ipv4" > "$all_ipv4"
    get_master_peers "ipv6" > "$all_ipv6"

    local new_counts_ipv4=$(smart_duplicate_check "$all_ipv4" "$CJDNS_CONFIG" 0 "$new_ipv4" "$updates_ipv4" 0)
    local new_counts_ipv6=$(smart_duplicate_check "$all_ipv6" "$CJDNS_CONFIG" 1 "$new_ipv6" "$updates_ipv6" 0)

    local new_ipv4_count=$(echo "$new_counts_ipv4" | cut -d'|' -f1)
    local new_ipv6_count=$(echo "$new_counts_ipv6" | cut -d'|' -f1)

    print_success "New peers not in config: $new_ipv4_count IPv4, $new_ipv6_count IPv6"

    # Test connectivity if user wants
    if [ "$new_ipv4_count" -gt 0 ] || [ "$new_ipv6_count" -gt 0 ]; then
        echo
        if ask_yes_no "Test connectivity to new peers? (This may take a few minutes)"; then
            print_subheader "Testing Connectivity"

            local pingable_ipv4="$WORK_DIR/pingable_ipv4.json"
            local pingable_ipv6="$WORK_DIR/pingable_ipv6.json"
            echo "{}" > "$pingable_ipv4"
            echo "{}" > "$pingable_ipv6"

            local pingable_ipv4_count=0
            local pingable_ipv6_count=0

            # Test IPv4
            if [ "$new_ipv4_count" -gt 0 ]; then
                print_info "Testing $new_ipv4_count IPv4 peers..."
                local tested=0
                while IFS= read -r addr; do
                    tested=$((tested + 1))
                    echo -n "[$tested/$new_ipv4_count] $addr... "
                    if test_peer_connectivity "$addr" 2 >/dev/null 2>&1; then
                        echo -e "${GREEN}✓${NC}"
                        pingable_ipv4_count=$((pingable_ipv4_count + 1))
                        local peer_data=$(jq --arg addr "$addr" '.[$addr]' "$new_ipv4")
                        jq -s --arg addr "$addr" --argjson peer "$peer_data" '.[0] + {($addr): $peer}' "$pingable_ipv4" > "$pingable_ipv4.tmp"
                        mv "$pingable_ipv4.tmp" "$pingable_ipv4"
                    else
                        echo -e "${RED}✗${NC}"
                    fi
                done < <(jq -r 'keys[]' "$new_ipv4")
            fi

            # Test IPv6
            if [ "$new_ipv6_count" -gt 0 ]; then
                print_info "Testing $new_ipv6_count IPv6 peers..."
                local tested=0
                while IFS= read -r addr; do
                    tested=$((tested + 1))
                    echo -n "[$tested/$new_ipv6_count] $addr... "
                    if test_peer_connectivity "$addr" 2 >/dev/null 2>&1; then
                        echo -e "${GREEN}✓${NC}"
                        pingable_ipv6_count=$((pingable_ipv6_count + 1))
                        local peer_data=$(jq --arg addr "$addr" '.[$addr]' "$new_ipv6")
                        jq -s --arg addr "$addr" --argjson peer "$peer_data" '.[0] + {($addr): $peer}' "$pingable_ipv6" > "$pingable_ipv6.tmp"
                        mv "$pingable_ipv6.tmp" "$pingable_ipv6"
                    else
                        echo -e "${RED}✗${NC}"
                    fi
                done < <(jq -r 'keys[]' "$new_ipv6")
            fi

            echo
            print_success "Pingable peers not in config: $pingable_ipv4_count IPv4, $pingable_ipv6_count IPv6"

            # Show pingable peers details if requested
            if [ "$pingable_ipv4_count" -gt 0 ] || [ "$pingable_ipv6_count" -gt 0 ]; then
                echo
                if ask_yes_no "View all pingable peers?"; then
                    if [ "$pingable_ipv4_count" -gt 0 ]; then
                        print_subheader "Pingable IPv4 Peers"
                        show_peer_details "$pingable_ipv4" 99999
                    fi

                    if [ "$pingable_ipv6_count" -gt 0 ]; then
                        echo
                        print_subheader "Pingable IPv6 Peers"
                        show_peer_details "$pingable_ipv6" 99999
                    fi
                fi
            fi
        fi
    fi

    echo
    print_info "To add these peers, return to the main menu and select the Peer Adding Wizard"
    echo
    read -p "Press Enter to continue..."
}

# Add Single Peer
add_single_peer() {
    clear
    print_ascii_header
    print_header "Add Single Peer"

    print_info "Enter peer connection details"
    print_info "Only password and publicKey are required - cjdns doesn't use metadata fields"
    echo

    local address=$(ask_input "Peer address (IP:PORT or [IPv6]:PORT)")
    local password=$(ask_input "Password")
    local publicKey=$(ask_input "Public key")

    # Build minimal JSON - only password and publicKey
    # Metadata fields (peerName, contact, location, etc.) are not written to config
    local peer_json=$(jq -n \
        --arg pw "$password" \
        --arg pk "$publicKey" \
        '{password: $pw, publicKey: $pk}')

    # Show review
    echo
    print_subheader "Review Peer"
    echo "Address: $address"
    echo "$peer_json" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    echo

    if ! ask_yes_no "Add this peer to your config?"; then
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Determine interface (IPv4 or IPv6)
    local interface_index=0
    if [[ "$address" =~ ^\[ ]]; then
        interface_index=1
    fi

    # Create temp peer file
    local temp_peer="$WORK_DIR/single_peer.json"
    jq -n --arg addr "$address" --argjson peer "$peer_json" \
        '{($addr): $peer}' > "$temp_peer"

    # Backup and add
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    else
        print_error "Failed to create backup"
        return
    fi

    local temp_config="$WORK_DIR/config.tmp"
    if add_peers_to_config "$CJDNS_CONFIG" "$temp_peer" "$interface_index" "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            print_success "Peer added successfully!"

            if ask_yes_no "Restart cjdns now?"; then
                restart_service
            fi
        else
            print_error "Config validation failed"
        fi
    else
        print_error "Failed to add peer"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Remove Peers Menu
remove_peers_menu() {
    clear
    print_ascii_header
    print_header "Remove Peers from Config"

    print_warning "WARNING: This will permanently remove peers from your cjdns config file"
    echo

    # Get current peer states
    local peer_states="$WORK_DIR/peer_states.txt"
    get_current_peer_states "$ADMIN_IP" "$ADMIN_PORT" "$ADMIN_PASSWORD" "$peer_states"

    # Update database with current states
    while IFS='|' read -r state address; do
        update_peer_state "$address" "$state"
    done < "$peer_states"

    # Get all peers from BOTH interfaces in config
    print_info "Loading peers from config..."
    echo

    declare -a all_config_peers
    # Get IPv4 peers
    while IFS= read -r addr; do
        [ -n "$addr" ] && all_config_peers+=("$addr")
    done < <(jq -r '.interfaces.UDPInterface[0].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null)

    # Get IPv6 peers
    while IFS= read -r addr; do
        [ -n "$addr" ] && all_config_peers+=("$addr")
    done < <(jq -r '.interfaces.UDPInterface[1].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null)

    if [ ${#all_config_peers[@]} -eq 0 ]; then
        print_warning "No peers found in config"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Get quality data from database
    local all_peers=$(get_all_peers_by_quality)

    # Build arrays for display
    declare -a peer_addresses
    declare -a peer_displays
    local index=0

    print_subheader "All Peers in Config (sorted by quality)"
    echo "Est.=Established count, Unr.=Unresponsive count"
    echo

    # Display peers with quality data first (sorted by quality)
    while IFS='|' read -r address state quality est_count unr_count first_seen last_change consecutive; do
        [ -z "$address" ] && continue

        index=$((index + 1))
        peer_addresses+=("$address")

        local quality_display=$(printf "%.0f%%" "$quality")
        local time_in_state=$(time_since "$last_change")

        if [ "$state" = "ESTABLISHED" ]; then
            printf "%3d) ${GREEN}✓${NC} %-40s Q:%-5s Est:%-3d Unr:%-3d (Established %s)\n" \
                "$index" "$address" "$quality_display" "$est_count" "$unr_count" "$time_in_state"
        elif [ "$state" = "UNRESPONSIVE" ]; then
            printf "%3d) ${RED}✗${NC} %-40s Q:%-5s Est:%-3d Unr:%-3d (Unresponsive %s, checked %dx)\n" \
                "$index" "$address" "$quality_display" "$est_count" "$unr_count" "$time_in_state" "$consecutive"
        else
            printf "%3d) ${YELLOW}?${NC} %-40s Q:%-5s Est:%-3d Unr:%-3d (%s %s)\n" \
                "$index" "$address" "$quality_display" "$est_count" "$unr_count" "$state" "$time_in_state"
        fi

        peer_displays+=("$address ($state)")
    done <<< "$all_peers"

    # Display peers from config that aren't in database yet (not yet checked)
    for config_addr in "${all_config_peers[@]}"; do
        # Check if this address was already displayed
        local already_shown=false
        for shown_addr in "${peer_addresses[@]}"; do
            if [ "$config_addr" = "$shown_addr" ]; then
                already_shown=true
                break
            fi
        done

        if [ "$already_shown" = false ]; then
            index=$((index + 1))
            peer_addresses+=("$config_addr")
            printf "%3d) ${GRAY}○${NC} %-40s Q:%-5s Est:%-3d Unr:%-3d ${GRAY}(Awaiting first check)${NC}\n" \
                "$index" "$config_addr" "N/A" "0" "0"
            peer_displays+=("$config_addr (AWAITING CHECK)")
        fi
    done

    echo
    print_info "Enter peer numbers to remove (space or comma-separated, e.g., '1 3 5' or '1,3,5')"
    print_info "Or type 'all-unresponsive' to remove all unresponsive peers"
    print_info "Or press Enter to cancel"
    echo

    local selection
    read -p "Selection: " -r selection < /dev/tty

    if [ -z "$selection" ]; then
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Parse selection
    declare -a selected_addresses

    if [ "$selection" = "all-unresponsive" ]; then
        # Select all unresponsive
        while IFS='|' read -r address state quality est_count unr_count first_seen last_change consecutive; do
            [ -z "$address" ] && continue
            if [ "$state" = "UNRESPONSIVE" ]; then
                selected_addresses+=("$address")
            fi
        done <<< "$all_peers"

        if [ ${#selected_addresses[@]} -eq 0 ]; then
            print_warning "No unresponsive peers found"
            echo
            read -p "Press Enter to continue..."
            return
        fi

        print_warning "Selected ${#selected_addresses[@]} unresponsive peer(s) for removal"
    else
        # Parse numbers
        selection=$(echo "$selection" | tr ',' ' ')
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#peer_addresses[@]}" ]; then
                selected_addresses+=("${peer_addresses[$((num-1))]}")
            else
                print_error "Invalid selection: $num"
            fi
        done

        if [ ${#selected_addresses[@]} -eq 0 ]; then
            print_error "No valid peers selected"
            echo
            read -p "Press Enter to continue..."
            return
        fi
    fi

    # Show what will be removed
    echo
    print_warning "The following peers will be PERMANENTLY REMOVED from your config:"
    for addr in "${selected_addresses[@]}"; do
        echo "  - $addr"
    done

    echo
    if ! ask_yes_no "Are you SURE you want to remove these peers?"; then
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Backup
    echo
    if ! ask_yes_no "Create backup before removing?"; then
        print_warning "Proceeding without backup!"
    else
        local backup
        if backup=$(backup_config "$CJDNS_CONFIG"); then
            print_success "Backup created: $backup"
        else
            print_error "Failed to create backup"
            if ! ask_yes_no "Continue anyway?"; then
                return
            fi
        fi
    fi

    # Remove peers
    local temp_config="$WORK_DIR/config.tmp"

    # Try removing from both interfaces
    remove_peers_from_config "$CJDNS_CONFIG" 0 "$temp_config" "${selected_addresses[@]}"
    remove_peers_from_config "$temp_config" 1 "$temp_config.new" "${selected_addresses[@]}"
    mv "$temp_config.new" "$temp_config"

    # Validate
    if ! validate_config "$temp_config"; then
        print_error "Config validation failed after removal"
        print_error "Your config was NOT modified"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Save
    cp "$temp_config" "$CJDNS_CONFIG"
    print_success "Successfully removed ${#selected_addresses[@]} peer(s) from config!"

    # Restart
    echo
    if ask_yes_no "Restart cjdns service now to apply changes?"; then
        restart_service
    fi

    echo
    read -p "Press Enter to continue..."
}

# View Peer Status
view_peer_status() {
    clear
    print_ascii_header
    print_header "Current Peer Status"

    local peer_states="$WORK_DIR/peer_states.txt"
    get_current_peer_states "$ADMIN_IP" "$ADMIN_PORT" "$ADMIN_PASSWORD" "$peer_states"

    # Update database
    while IFS='|' read -r state address; do
        update_peer_state "$address" "$state"
    done < "$peer_states"

    local total=$(wc -l < "$peer_states")
    local established=$(grep -c "^ESTABLISHED|" "$peer_states" || echo 0)
    local unresponsive=$(grep -c "^UNRESPONSIVE|" "$peer_states" || echo 0)
    local other=$((total - established - unresponsive))

    echo "Total peers: $total"
    print_success "ESTABLISHED: $established"
    print_error "UNRESPONSIVE: $unresponsive"
    if [ "$other" -gt 0 ]; then
        print_warning "OTHER STATES: $other"
    fi
    echo

    if ask_yes_no "Show detailed list with quality scores and timestamps?"; then
        print_subheader "Peer Details"

        # Get all peers from config (IPv4 and IPv6)
        declare -a all_config_peers
        # IPv4 peers
        while IFS= read -r addr; do
            [ -n "$addr" ] && all_config_peers+=("$addr")
        done < <(jq -r '.interfaces.UDPInterface[0].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null)

        # IPv6 peers
        while IFS= read -r addr; do
            [ -n "$addr" ] && all_config_peers+=("$addr")
        done < <(jq -r '.interfaces.UDPInterface[1].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null)

        # Get all peers with full details from database
        local all_db_peers=$(get_all_peers_by_quality)

        # Create associative array for quick lookup
        declare -A db_peers
        while IFS='|' read -r address state quality est_count unr_count first_seen last_change consecutive; do
            [ -z "$address" ] && continue
            db_peers["$address"]="$state|$quality|$est_count|$unr_count|$last_change|$consecutive"
        done <<< "$all_db_peers"

        # Display each peer from config
        for config_addr in "${all_config_peers[@]}"; do
            if [ -n "${db_peers[$config_addr]:-}" ]; then
                # Peer is in database - show full info
                IFS='|' read -r state quality est_count unr_count last_change consecutive <<< "${db_peers[$config_addr]}"
                local quality_display=$(printf "%.0f%%" "$quality")
                local time_in_state=$(time_since "$last_change")

                if [ "$state" = "ESTABLISHED" ]; then
                    print_success "$state: $config_addr (Quality: $quality_display, Established $time_in_state)"
                elif [ "$state" = "UNRESPONSIVE" ]; then
                    print_error "$state: $config_addr (Quality: $quality_display, Unresponsive $time_in_state, Checked $consecutive times)"
                else
                    print_warning "$state: $config_addr (Quality: $quality_display, In state $time_in_state)"
                fi
            else
                # Peer not in database yet - show as awaiting check
                echo -e "${GRAY}○ AWAITING CHECK: $config_addr (Not yet tested - will be checked on next service restart)${NC}"
            fi
        done
    fi

    echo
    read -p "Press Enter to continue..."
}

# Configuration Settings Submenu
configuration_settings_menu() {
    while true; do
        clear
        print_ascii_header
        print_header "Configuration Settings"

        echo "Current Configuration:"
        echo "  Config File: $CJDNS_CONFIG"
        echo "  Service: ${CJDNS_SERVICE:-Disabled}"
        echo "  Backup Directory: $BACKUP_DIR"
        echo

        echo "1) Change Config File Location"
        echo "2) Change Service Name"
        echo "3) Change Backup Directory (with migration)"
        echo
        echo "0) Back to Maintenance Menu"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty < /dev/tty

        case "$choice" in
            1) change_config_location ;;
            2) change_service_name ;;
            3) change_backup_directory ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# Peer Sources Management Submenu
peer_sources_menu() {
    while true; do
        clear
        print_ascii_header
        print_header "Peer Sources Management"

        # Load and display sources
        echo "Current Peer Sources:"
        echo
        local sources_json=$(jq -c '.sources[]' "$PEER_SOURCES" 2>/dev/null)
        local count=0
        while IFS= read -r source; do
            [ -z "$source" ] && continue
            local name=$(echo "$source" | jq -r '.name')
            local enabled=$(echo "$source" | jq -r '.enabled')
            local type=$(echo "$source" | jq -r '.type')

            local status_icon="✓"
            local status_text="${GREEN}Enabled${NC}"
            if [ "$enabled" = "false" ]; then
                status_icon="✗"
                status_text="${RED}Disabled${NC}"
            fi

            echo -e "  $status_icon $name ($type) - $status_text"
            count=$((count + 1))
        done <<< "$sources_json"

        if [ $count -eq 0 ]; then
            echo "  No sources configured"
        fi
        echo

        echo "1) Enable/Disable a Source"
        echo "2) Add New Source"
        echo "3) Remove Source"
        echo "4) Reset Local Address Database"
        echo
        echo "0) Back to Maintenance Menu"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty < /dev/tty

        case "$choice" in
            1) toggle_peer_source_menu ;;
            2) add_peer_source_menu ;;
            3) remove_peer_source_menu ;;
            4) reset_master_list_menu ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# Database Management Submenu
database_management_menu() {
    while true; do
        clear
        print_ascii_header
        print_header "Database Management"

        echo "1) Backup Database"
        echo "2) Restore Database from Backup"
        echo "3) Reset Database (Clear all peer tracking data)"
        echo
        echo "0) Back to Maintenance Menu"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty < /dev/tty

        case "$choice" in
            1) database_backup_menu ;;
            2) database_restore_menu ;;
            3) reset_database_menu ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# File Management Submenu
file_management_menu() {
    while true; do
        clear
        print_ascii_header
        print_header "File Management"

        # Count files
        local backup_count=$(ls -1 "$BACKUP_DIR"/cjdroute_backup_*.conf 2>/dev/null | wc -l)
        local export_count=$(ls -1 "$BACKUP_DIR"/exported_peers/*.json 2>/dev/null | wc -l)

        echo "Current Files:"
        echo "  Config Backups: $backup_count"
        echo "  Exported Peer Files: $export_count"
        echo

        echo "1) Delete Old Config Backups (multi-select)"
        echo "2) Delete Exported Peer Files (multi-select)"
        echo "3) Import Peers from File"
        echo "4) Export Peers to File"
        echo "5) Backup Config File"
        echo "6) Restore Config from Backup"
        echo
        echo "0) Back to Maintenance Menu"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty < /dev/tty

        case "$choice" in
            1) interactive_file_deletion "backup" ;;
            2) interactive_file_deletion "export" ;;
            3) import_peers_menu ;;
            4) export_peers_menu ;;
            5) backup_config_menu ;;
            6) restore_config_menu ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# Maintenance Menu
maintenance_menu() {
    while true; do
        clear
        print_ascii_header
        print_header "Maintenance & Settings"

        echo "1) ⚙️  Configuration Settings"
        echo "2) 🌐 Peer Sources Management"
        echo "3) 💾 Database Management"
        echo "4) 📁 File Management"
        echo "5) 🔄 Restart cjdns Service"
        echo
        echo "0) Back to Main Menu"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty < /dev/tty

        case "$choice" in
            1) configuration_settings_menu ;;
            2) peer_sources_menu ;;
            3) database_management_menu ;;
            4) file_management_menu ;;
            5) restart_service ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# Show directories and config info
show_directories() {
    clear
    print_ascii_header
    print_header "Settings and Configuration"

    # Count various items
    local backup_count=$(ls -1 "$BACKUP_DIR"/cjdroute_backup_*.conf 2>/dev/null | wc -l)
    local export_count=$(ls -1 "$BACKUP_DIR"/exported_peers/*.json 2>/dev/null | wc -l)
    local counts=$(get_master_counts)
    local ipv4_count=$(echo "$counts" | cut -d'|' -f1)
    local ipv6_count=$(echo "$counts" | cut -d'|' -f2)
    local service_status="Disabled"
    if [ -n "$CJDNS_SERVICE" ]; then
        service_status="$CJDNS_SERVICE"
    fi

    # Display current settings
    print_subheader "Current Configuration"
    echo
    printf "%-25s %s\n" "CJDNS Config File:" "$CJDNS_CONFIG"
    printf "%-25s %s\n" "CJDNS Service:" "$service_status"
    printf "%-25s %s\n" "Backup Directory:" "$BACKUP_DIR"
    printf "%-25s %s\n" "Database File:" "$DB_FILE"
    printf "%-25s %s\n" "Local Address DB:" "$MASTER_LIST"
    printf "%-25s %s\n" "Peer Sources File:" "$PEER_SOURCES"
    echo

    print_subheader "Storage Statistics"
    echo
    printf "%-25s %d\n" "Config Backups:" "$backup_count"
    printf "%-25s %d\n" "Exported Peer Files:" "$export_count"
    printf "%-25s %d IPv4, %d IPv6\n" "Local Address DB:" "$ipv4_count" "$ipv6_count"
    echo

    # Show current config peer counts
    local config_ipv4=$(get_peer_count "$CJDNS_CONFIG" 0)
    local config_ipv6=$(get_peer_count "$CJDNS_CONFIG" 1)
    printf "%-25s %d IPv4, %d IPv6\n" "Peers in Config:" "$config_ipv4" "$config_ipv6"
    echo

    print_info "Settings management features:"
    echo "  - Config file location can be changed by re-initializing"
    echo "  - Backup directory changes: Not yet implemented"
    echo "  - Service management: Set during initialization"
    echo
    print_warning "To change critical settings, restart the application"

    echo
    read -p "Press Enter to continue..."
}

# Toggle peer source on/off (menu-based)
toggle_peer_source_menu() {
    clear
    print_ascii_header
    print_header "Enable/Disable Peer Source"

    # Load sources and build menu
    local sources_json=$(jq -c '.sources[]' "$PEER_SOURCES" 2>/dev/null)
    declare -a source_names
    declare -a source_statuses
    local count=1

    echo "Select source to toggle:"
    echo
    while IFS= read -r source; do
        [ -z "$source" ] && continue
        local name=$(echo "$source" | jq -r '.name')
        local enabled=$(echo "$source" | jq -r '.enabled')
        local status="Enabled"
        [ "$enabled" = "false" ] && status="Disabled"

        echo "  $count) $name [$status]"
        source_names+=("$name")
        source_statuses+=("$enabled")
        count=$((count + 1))
    done <<< "$sources_json"

    echo
    echo "  0) Cancel"
    echo

    local choice
    read -p "Enter choice: " choice < /dev/tty

    if [ "$choice" = "0" ] || [ "$choice" -lt 1 ] || [ "$choice" -ge $count ]; then
        return
    fi

    local idx=$((choice - 1))
    local selected_name="${source_names[$idx]}"
    local current_state="${source_statuses[$idx]}"
    local new_state="true"
    [ "$current_state" = "true" ] && new_state="false"

    jq ".sources |= map(if .name==\"$selected_name\" then .enabled=$new_state else . end)" "$PEER_SOURCES" > "$PEER_SOURCES.tmp"
    mv "$PEER_SOURCES.tmp" "$PEER_SOURCES"

    echo
    print_success "Toggled $selected_name to: $new_state"
    sleep 1
}

# Add new peer source (menu-based)
add_peer_source_menu() {
    clear
    print_ascii_header
    print_header "Add New Peer Source"
    echo

    # Get source name
    echo "Enter source name (e.g., 'my-peers'):"
    read -p "> " name < /dev/tty
    [ -z "$name" ] && return

    # Get source type
    echo
    echo "Select source type:"
    echo "  1) GitHub repository"
    echo "  2) Direct JSON URL"
    echo "  0) Cancel"
    echo
    read -p "Enter choice: " type_choice < /dev/tty

    local type
    case "$type_choice" in
        1) type="github" ;;
        2) type="json" ;;
        *) return ;;
    esac

    # Get URL
    echo
    if [ "$type" = "github" ]; then
        echo "Enter GitHub repository URL (e.g., https://github.com/user/repo.git):"
    else
        echo "Enter direct JSON URL:"
    fi
    read -p "> " url < /dev/tty
    [ -z "$url" ] && return

    # Add to sources
    jq ".sources += [{\"name\": \"$name\", \"type\": \"$type\", \"url\": \"$url\", \"enabled\": true}]" "$PEER_SOURCES" > "$PEER_SOURCES.tmp"
    mv "$PEER_SOURCES.tmp" "$PEER_SOURCES"

    echo
    print_success "Added source: $name"
    sleep 1
}

# Remove peer source (menu-based)
remove_peer_source_menu() {
    clear
    print_ascii_header
    print_header "Remove Peer Source"
    echo

    # Load sources and build menu
    local sources_json=$(jq -c '.sources[]' "$PEER_SOURCES" 2>/dev/null)
    declare -a source_names
    local count=1

    echo "Select source to REMOVE:"
    echo
    while IFS= read -r source; do
        [ -z "$source" ] && continue
        local name=$(echo "$source" | jq -r '.name')

        echo "  $count) $name"
        source_names+=("$name")
        count=$((count + 1))
    done <<< "$sources_json"

    echo
    echo "  0) Cancel"
    echo

    local choice
    read -p "Enter choice: " choice < /dev/tty

    if [ "$choice" = "0" ] || [ "$choice" -lt 1 ] || [ "$choice" -ge $count ]; then
        return
    fi

    local idx=$((choice - 1))
    local selected_name="${source_names[$idx]}"

    echo
    if ! ask_yes_no "Remove source '$selected_name'?"; then
        return
    fi

    jq ".sources |= map(select(.name!=\"$selected_name\"))" "$PEER_SOURCES" > "$PEER_SOURCES.tmp"
    mv "$PEER_SOURCES.tmp" "$PEER_SOURCES"

    echo
    print_success "Removed source: $selected_name"
    sleep 1
}

# Reset local address database
reset_master_list_menu() {
    clear
    print_ascii_header
    print_header "Reset Local Address Database"

    print_warning "This will delete the current database and re-download from all sources"
    echo

    if ! ask_yes_no "Are you sure you want to reset the local address database?"; then
        return
    fi

    echo
    print_working "Resetting local address database..."
    reset_master_list >/dev/null 2>&1

    local counts=$(get_master_counts)
    local ipv4_count=$(echo "$counts" | cut -d'|' -f1)
    local ipv6_count=$(echo "$counts" | cut -d'|' -f2)

    echo
    print_success "Local Address Database reset complete!"
    echo
    echo -e "  ${BOLD}Database Statistics:${NC}"
    echo -e "    • IPv4 Peers: ${GREEN}${BOLD}$ipv4_count${NC}"
    echo -e "    • IPv6 Peers: ${GREEN}${BOLD}$ipv6_count${NC}"

    echo
    read -p "Press Enter to continue..."
}

# Manage peer sources
manage_sources_menu() {
    clear
    print_ascii_header
    print_header "Manage Peer Sources"

    print_info "Current peer sources:"
    echo

    local sources=$(jq -r '.sources[] | "\(.name)|\(.type)|\(.url)|\(.enabled)"' "$PEER_SOURCES")

    local i=1
    while IFS='|' read -r name type url enabled; do
        local status="ENABLED"
        if [ "$enabled" = "false" ]; then
            status="DISABLED"
        fi
        printf "%d) [%s] %s (%s)\n" "$i" "$status" "$name" "$type"
        printf "   %s\n" "$url"
        echo
        i=$((i + 1))
    done <<< "$sources"

    print_info "Source management features:"
    echo "  - Toggle sources on/off"
    echo "  - Add custom sources"
    echo
    print_warning "Feature coming soon - sources are currently read-only"

    echo
    read -p "Press Enter to continue..."
}

# Reset database
# Database backup menu
database_backup_menu() {
    clear
    print_ascii_header
    print_header "Backup Database"

    print_info "Create a backup of the peer tracking database"
    echo

    if ! ask_yes_no "Create a backup of the database?"; then
        return
    fi

    local backup
    if backup=$(backup_database); then
        print_success "Database backup created successfully"
        echo
        echo "Backup location: $backup"
        echo "Backup size: $(ls -lh "$backup" | awk '{print $5}')"
    else
        print_error "Failed to create database backup"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Database restore menu
database_restore_menu() {
    clear
    print_ascii_header
    print_header "Restore Database from Backup"

    local backup_dir="$BACKUP_DIR/database_backups"
    echo "Available database backups in $backup_dir:"
    echo

    # Get backups sorted by modification time (newest first)
    local backups
    mapfile -t backups < <(find "$backup_dir" -name "peer_tracking_backup_*.db" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No database backups found"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Show backups with numbers (newest first)
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local timestamp=$(basename "$backup" | sed 's/peer_tracking_backup_\(.*\)\.db/\1/')
        local size=$(ls -lh "$backup" | awk '{print $5}')
        local date_formatted=$(format_timestamp $(stat -c %Y "$backup"))
        echo "  $((i+1))) $timestamp - $date_formatted ($size)"
    done

    echo
    echo "  0) Cancel"
    echo

    local choice
    while true; do
        read -p "Select backup to restore (0-${#backups[@]}): " choice < /dev/tty

        if [ "$choice" = "0" ]; then
            print_info "Cancelled"
            echo
            read -p "Press Enter to continue..."
            return
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
            break
        else
            print_error "Invalid selection"
        fi
    done

    local backup_file="${backups[$((choice-1))]}"
    echo
    print_warning "This will replace the current database with the backup"
    echo

    if ! ask_yes_no "Are you SURE you want to restore this backup?"; then
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    if restore_database "$backup_file"; then
        print_success "Database restored successfully"
    else
        print_error "Failed to restore database"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Reset database menu
reset_database_menu() {
    clear
    print_ascii_header
    print_header "Reset Database"

    print_warning "This will delete all peer quality tracking data"
    echo

    # Offer to backup first
    if ask_yes_no "Create a backup before resetting?"; then
        local backup
        if backup=$(backup_database); then
            print_success "Backup created: $backup"
        else
            print_warning "Backup failed, but continuing"
        fi
    fi

    echo
    if ! ask_yes_no "Are you sure you want to reset the database?"; then
        return
    fi

    if reset_database; then
        print_success "Database reset complete!"
    else
        print_error "Failed to reset database"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Import peers from file
import_peers_menu() {
    clear
    print_ascii_header
    print_header "Import Peers from File"

    print_info "Import peers from a JSON file"
    echo

    # Check for exported peer files
    local export_dir="$BACKUP_DIR/exported_peers"
    local exports
    mapfile -t exports < <(find "$export_dir" -name "*.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [ ${#exports[@]} -gt 0 ]; then
        echo "Available export files:"
        echo
        for i in "${!exports[@]}"; do
            local export_file="${exports[$i]}"
            local filename=$(basename "$export_file")
            local size=$(ls -lh "$export_file" | awk '{print $5}')
            echo "  $((i+1))) $filename ($size)"
        done
        echo
        echo "  0) Enter custom path"
        echo

        local choice
        while true; do
            read -p "Select file to import (0-${#exports[@]}, or 'q' to quit): " choice < /dev/tty

            if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
                return
            elif [[ "$choice" == "0" ]]; then
                break
            elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#exports[@]} ]; then
                local file_path="${exports[$((choice-1))]}"
                break
            else
                print_error "Invalid selection"
            fi
        done
    fi

    # Custom path entry
    if [ -z "$file_path" ] || [ "$choice" == "0" ]; then
        echo
        echo "Enter path to JSON file (example: $export_dir/ipv4_peers_*.json)"
        echo "or press Ctrl+C to cancel"
        echo
        read -p "File path: " -r file_path < /dev/tty

        if [ -z "$file_path" ]; then
            print_error "No file specified"
            echo
            read -p "Press Enter to continue..."
            return
        fi
    fi

    if [ ! -f "$file_path" ]; then
        print_error "File not found: $file_path"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    if ! jq empty "$file_path" 2>/dev/null; then
        print_error "Invalid JSON file"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    local peer_count=$(jq 'length' "$file_path")
    print_info "Found $peer_count peers in file"

    # Detect IPv4/IPv6
    local has_ipv4=$(jq -r 'keys[] | select(startswith("[") | not)' "$file_path" | head -1)
    local has_ipv6=$(jq -r 'keys[] | select(startswith("["))' "$file_path" | head -1)

    local interface_index=0
    if [ -n "$has_ipv6" ] && [ -z "$has_ipv4" ]; then
        interface_index=1
        print_info "Detected IPv6 peers"
    else
        print_info "Detected IPv4 peers"
    fi

    echo
    if ! ask_yes_no "Import these peers?"; then
        return
    fi

    # Smart duplicate check
    local new_peers="$WORK_DIR/import_new.json"
    local updates="$WORK_DIR/import_updates.json"

    local counts=$(smart_duplicate_check "$file_path" "$CJDNS_CONFIG" "$interface_index" "$new_peers" "$updates")
    local new_count=$(echo "$counts" | cut -d'|' -f1)
    local update_count=$(echo "$counts" | cut -d'|' -f2)

    echo
    print_info "Import summary: $new_count new, $update_count updates"

    if [ "$new_count" -eq 0 ] && [ "$update_count" -eq 0 ]; then
        print_warning "No peers to import"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Backup and add
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    else
        print_error "Failed to create backup"
        return
    fi

    local temp_config="$WORK_DIR/config.tmp"
    cp "$CJDNS_CONFIG" "$temp_config"

    if [ "$new_count" -gt 0 ]; then
        if add_peers_to_config "$temp_config" "$new_peers" "$interface_index" "$temp_config.new"; then
            mv "$temp_config.new" "$temp_config"
            print_success "Added $new_count new peers"
        fi
    fi

    if [ "$update_count" -gt 0 ]; then
        if apply_peer_updates "$temp_config" "$updates" "$interface_index" "$temp_config.new"; then
            mv "$temp_config.new" "$temp_config"
            print_success "Updated $update_count peers"
        fi
    fi

    if validate_config "$temp_config"; then
        cp "$temp_config" "$CJDNS_CONFIG"
        print_success "Import complete!"

        if ask_yes_no "Restart cjdns now?"; then
            restart_service
        fi
    else
        print_error "Config validation failed"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Export peers to file
export_peers_menu() {
    clear
    print_ascii_header
    print_header "Export Peers to File"

    print_info "Export all peers from your config to a JSON file"
    echo

    echo "Select interface to export:"
    echo "  4) IPv4 peers"
    echo "  6) IPv6 peers"
    echo "  B) Both (separate files)"
    echo "  0) Cancel and return to main menu"
    echo

    local selection
    read -p "Enter selection: " -r selection < /dev/tty

    # Handle exit
    if [[ "$selection" == "0" ]] || [[ "$selection" =~ ^[Qq]$ ]]; then
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    local export_dir="$BACKUP_DIR/exported_peers"
    mkdir -p "$export_dir"

    local timestamp=$(date +%Y%m%d_%H%M%S)

    case "$selection" in
        4)
            local output="$export_dir/ipv4_peers_$timestamp.json"
            jq '.interfaces.UDPInterface[0].connectTo // {}' "$CJDNS_CONFIG" > "$output"
            local count=$(jq 'length' "$output")
            print_success "Exported $count IPv4 peers to: $output"
            ;;
        6)
            local output="$export_dir/ipv6_peers_$timestamp.json"
            jq '.interfaces.UDPInterface[1].connectTo // {}' "$CJDNS_CONFIG" > "$output"
            local count=$(jq 'length' "$output")
            print_success "Exported $count IPv6 peers to: $output"
            ;;
        [Bb])
            local output_ipv4="$export_dir/ipv4_peers_$timestamp.json"
            local output_ipv6="$export_dir/ipv6_peers_$timestamp.json"
            jq '.interfaces.UDPInterface[0].connectTo // {}' "$CJDNS_CONFIG" > "$output_ipv4"
            jq '.interfaces.UDPInterface[1].connectTo // {}' "$CJDNS_CONFIG" > "$output_ipv6"
            local count_ipv4=$(jq 'length' "$output_ipv4")
            local count_ipv6=$(jq 'length' "$output_ipv6")
            print_success "Exported $count_ipv4 IPv4 peers to: $output_ipv4"
            print_success "Exported $count_ipv6 IPv6 peers to: $output_ipv6"
            ;;
        *)
            print_error "Invalid selection"
            ;;
    esac

    echo
    read -p "Press Enter to continue..."
}

# Backup config manually
backup_config_menu() {
    clear
    print_ascii_header
    print_header "Backup Config File"

    echo "Current config: $CJDNS_CONFIG"
    echo "Backup directory: $BACKUP_DIR"
    echo

    if ! ask_yes_no "Create a backup of your current config?"; then
        return
    fi

    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created successfully"
        echo
        echo "Backup location: $backup"
        echo "Backup size: $(ls -lh "$backup" | awk '{print $5}')"
    else
        print_error "Failed to create backup"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Restore config from backup
restore_config_menu() {
    clear
    print_ascii_header
    print_header "Restore Config from Backup"

    echo "Available backups in $BACKUP_DIR:"
    echo

    # Get backups sorted by modification time (newest first)
    local backups
    mapfile -t backups < <(find "$BACKUP_DIR" -name "cjdroute_backup_*.conf" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found in $BACKUP_DIR"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Show backups with numbers (newest first)
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local timestamp=$(basename "$backup" | sed 's/cjdroute_backup_\(.*\)\.conf/\1/')
        local size=$(ls -lh "$backup" | awk '{print $5}')
        local date_formatted=$(format_timestamp $(stat -c %Y "$backup"))
        echo "  $((i+1))) $timestamp - $date_formatted ($size)"
    done

    echo
    echo "  0) Cancel"
    echo

    local choice
    while true; do
        read -p "Select backup to restore (0-${#backups[@]}): " choice < /dev/tty

        if [ "$choice" = "0" ]; then
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
            break
        else
            print_error "Invalid selection"
        fi
    done

    local selected_backup="${backups[$((choice-1))]}"

    echo
    print_warning "This will replace your current config with:"
    echo "  $selected_backup"
    echo
    echo "Your current config will be backed up first as a safety measure."
    echo

    if ! ask_yes_no "Are you sure you want to restore this backup?"; then
        return
    fi

    if restore_config "$selected_backup" "$CJDNS_CONFIG"; then
        print_success "Config restored successfully"
        echo
        print_info "You should restart cjdns for changes to take effect"

        if ask_yes_no "Restart cjdns now?"; then
            restart_service
        fi
    else
        print_error "Failed to restore config"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Restart cjdns service
restart_service() {
    print_subheader "Restarting cjdns Service"

    if [ -z "$CJDNS_SERVICE" ]; then
        print_error "Service management unavailable"
        echo
        echo "Restart function is unavailable because no service was found during initialization."
        echo "Please restart cjdns manually using one of these methods:"
        echo "  - sudo systemctl restart cjdns.service"
        echo "  - sudo systemctl restart cjdroute"
        echo "  - Or restart using your system's init system"
        echo
        read -p "Press Enter to continue..."
        return 1
    fi

    echo "Restarting $CJDNS_SERVICE..."

    if systemctl restart "$CJDNS_SERVICE"; then
        print_success "Service restarted"

        # Poll for connection with 2s intervals, max 10s
        local attempts=0
        local max_attempts=5

        while [ $attempts -lt $max_attempts ]; do
            sleep 2
            if test_cjdnstool_connection "$ADMIN_IP" "$ADMIN_PORT" "$ADMIN_PASSWORD"; then
                print_success "cjdns is running and responding"
                echo
                read -p "Press Enter to continue..."
                return
            fi
            attempts=$((attempts + 1))
        done

        print_warning "Service restarted but not responding yet"
    else
        print_error "Failed to restart service"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Main program
main() {
    # Initialize
    initialize

    # Main loop
    while true; do
        show_menu

        local choice
        read -p "Enter choice: " choice < /dev/tty < /dev/tty < /dev/tty

        case "$choice" in
            1) peer_adding_wizard ;;
            2) discover_preview ;;
            3) guided_config_editor ;;
            4) interactive_peer_management ;;
            5) view_peer_status ;;
            6) maintenance_menu ;;
            0)
                clear
                print_ascii_header
                print_success "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Run main program
main
