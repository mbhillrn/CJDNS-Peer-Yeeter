#!/usr/bin/env bash
# Editor Module - Interactive config editing

# Detect available editor
get_editor() {
    if command -v micro &>/dev/null; then
        echo "micro"
    elif command -v nano &>/dev/null; then
        echo "nano"
    elif command -v vim &>/dev/null; then
        echo "vim"
    else
        echo "vi"
    fi
}

# Edit admin section
edit_admin_section() {
    local config="$1"
    local temp_section="$WORK_DIR/edit_admin.json"
    local temp_config="$WORK_DIR/config_new.json"

    # Extract admin section
    jq '.admin' "$config" > "$temp_section"

    print_info "Editing admin section..."
    echo "Current values:"
    cat "$temp_section"
    echo
    print_info "Press Enter to open editor..."
    read -r

    # Open in editor
    local editor=$(get_editor)
    $editor "$temp_section"

    # Validate JSON
    if ! jq empty "$temp_section" 2>/dev/null; then
        print_error "Invalid JSON in edited section"
        return 1
    fi

    # Merge back
    jq --slurpfile admin "$temp_section" '.admin = $admin[0]' "$config" > "$temp_config"

    if validate_config "$temp_config"; then
        print_success "Admin section updated"
        return 0
    else
        print_error "Config validation failed"
        return 1
    fi
}

# Edit authorized passwords
edit_authorized_passwords() {
    local config="$1"
    local temp_section="$WORK_DIR/edit_authpw.json"
    local temp_config="$WORK_DIR/config_new.json"

    # Extract authorizedPasswords
    jq '.authorizedPasswords' "$config" > "$temp_section"

    print_info "Editing authorized passwords..."
    echo "Current values:"
    cat "$temp_section"
    echo
    print_info "Press Enter to open editor..."
    read -r

    local editor=$(get_editor)
    $editor "$temp_section"

    if ! jq empty "$temp_section" 2>/dev/null; then
        print_error "Invalid JSON in edited section"
        return 1
    fi

    # Normalize authorizedPasswords to ONLY {password, user} format
    # If entry has "login" but no "user", use login value as user (backwards compat)
    # Entries without password or user/login are invalid and will be skipped
    local normalized=$(jq '[.[] | select(.password != null and (.user != null or .login != null)) | {password: .password, user: (.user // .login)}]' "$temp_section")

    jq --argjson authpw "$normalized" '.authorizedPasswords = $authpw' "$config" > "$temp_config"

    if validate_config "$temp_config"; then
        print_success "Authorized passwords updated"
        return 0
    else
        print_error "Config validation failed"
        return 1
    fi
}

# Edit IPv4 peers (UDPInterface[0].connectTo)
edit_ipv4_peers() {
    local config="$1"
    local temp_section="$WORK_DIR/edit_ipv4.json"
    local temp_config="$WORK_DIR/config_new.json"

    # Extract IPv4 peers
    jq '.interfaces.UDPInterface[0].connectTo // {}' "$config" > "$temp_section"

    print_info "Editing IPv4 peers..."
    echo "Found $(jq 'length' "$temp_section") IPv4 peers"
    echo
    print_info "Press Enter to open editor..."
    read -r

    local editor=$(get_editor)
    $editor "$temp_section"

    if ! jq empty "$temp_section" 2>/dev/null; then
        print_error "Invalid JSON in edited section"
        return 1
    fi

    # Normalize peers to only password and publicKey (strip metadata)
    local normalized=$(jq 'to_entries | map({key: .key, value: {password: .value.password, publicKey: .value.publicKey}}) | from_entries' "$temp_section")

    # Merge back
    jq --argjson peers "$normalized" '
        if .interfaces.UDPInterface[0] then
            .interfaces.UDPInterface[0].connectTo = $peers
        else
            .interfaces.UDPInterface[0] = {"connectTo": $peers}
        end
    ' "$config" > "$temp_config"

    if validate_config "$temp_config"; then
        print_success "IPv4 peers updated"
        return 0
    else
        print_error "Config validation failed"
        return 1
    fi
}

# Edit IPv6 peers (UDPInterface[1].connectTo)
edit_ipv6_peers() {
    local config="$1"
    local temp_section="$WORK_DIR/edit_ipv6.json"
    local temp_config="$WORK_DIR/config_new.json"

    # Check if IPv6 interface exists
    local has_ipv6=$(jq '.interfaces.UDPInterface[1] // null' "$config")

    if [ "$has_ipv6" = "null" ]; then
        print_warning "No IPv6 interface found in config"
        if ! ask_yes_no "Create IPv6 interface?"; then
            return 1
        fi
        echo '{}' > "$temp_section"
    else
        jq '.interfaces.UDPInterface[1].connectTo // {}' "$config" > "$temp_section"
    fi

    print_info "Editing IPv6 peers..."
    echo "Found $(jq 'length' "$temp_section") IPv6 peers"
    echo
    print_info "Press Enter to open editor..."
    read -r

    local editor=$(get_editor)
    $editor "$temp_section"

    if ! jq empty "$temp_section" 2>/dev/null; then
        print_error "Invalid JSON in edited section"
        return 1
    fi

    # Normalize peers to only password and publicKey (strip metadata)
    local normalized=$(jq 'to_entries | map({key: .key, value: {password: .value.password, publicKey: .value.publicKey}}) | from_entries' "$temp_section")

    # Merge back
    if [ "$has_ipv6" = "null" ]; then
        # Create new IPv6 interface with IPv6 bind address prompt
        print_info "Creating new IPv6 interface"
        local ipv6_bind=$(ask_input "Enter IPv6 bind address (e.g., [::]:PORT or [2001:db8::1]:PORT)")

        jq --argjson peers "$normalized" --arg bind "$ipv6_bind" '
            .interfaces.UDPInterface[1] = {
                "bind": $bind,
                "connectTo": $peers
            }
        ' "$config" > "$temp_config"
    else
        jq --argjson peers "$normalized" '
            .interfaces.UDPInterface[1].connectTo = $peers
        ' "$config" > "$temp_config"
    fi

    if validate_config "$temp_config"; then
        print_success "IPv6 peers updated"
        return 0
    else
        print_error "Config validation failed"
        return 1
    fi
}

# Edit IPv4 interface settings (bind, beacon, etc)
edit_ipv4_interface() {
    local config="$1"
    local temp_section="$WORK_DIR/edit_ipv4_iface.json"
    local temp_config="$WORK_DIR/config_new.json"

    # Extract IPv4 interface (without connectTo)
    jq '.interfaces.UDPInterface[0] | del(.connectTo)' "$config" > "$temp_section"

    print_info "Editing IPv4 interface settings (bind, beacon, etc)..."
    echo "Current values:"
    cat "$temp_section"
    echo
    print_warning "Do NOT edit 'connectTo' here - use 'Edit IPv4 Peers' instead"
    print_info "Press Enter to open editor..."
    read -r

    local editor=$(get_editor)
    $editor "$temp_section"

    if ! jq empty "$temp_section" 2>/dev/null; then
        print_error "Invalid JSON in edited section"
        return 1
    fi

    # Merge back (preserve connectTo)
    jq --slurpfile iface "$temp_section" '
        .interfaces.UDPInterface[0] = ($iface[0] + {"connectTo": .interfaces.UDPInterface[0].connectTo})
    ' "$config" > "$temp_config"

    if validate_config "$temp_config"; then
        print_success "IPv4 interface settings updated"
        return 0
    else
        print_error "Config validation failed"
        return 1
    fi
}

# Edit IPv6 interface settings
edit_ipv6_interface() {
    local config="$1"
    local temp_section="$WORK_DIR/edit_ipv6_iface.json"
    local temp_config="$WORK_DIR/config_new.json"

    local has_ipv6=$(jq '.interfaces.UDPInterface[1] // null' "$config")

    if [ "$has_ipv6" = "null" ]; then
        print_error "No IPv6 interface found. Create one via 'Edit IPv6 Peers' first."
        return 1
    fi

    # Extract IPv6 interface (without connectTo)
    jq '.interfaces.UDPInterface[1] | del(.connectTo)' "$config" > "$temp_section"

    print_info "Editing IPv6 interface settings..."
    echo "Current values:"
    cat "$temp_section"
    echo
    print_warning "Do NOT edit 'connectTo' here - use 'Edit IPv6 Peers' instead"
    print_info "Press Enter to open editor..."
    read -r

    local editor=$(get_editor)
    $editor "$temp_section"

    if ! jq empty "$temp_section" 2>/dev/null; then
        print_error "Invalid JSON in edited section"
        return 1
    fi

    # Merge back (preserve connectTo)
    jq --slurpfile iface "$temp_section" '
        .interfaces.UDPInterface[1] = ($iface[0] + {"connectTo": .interfaces.UDPInterface[1].connectTo})
    ' "$config" > "$temp_config"

    if validate_config "$temp_config"; then
        print_success "IPv6 interface settings updated"
        return 0
    else
        print_error "Config validation failed"
        return 1
    fi
}

# Edit router section (seeds, tunnels, etc)
edit_router_section() {
    local config="$1"
    local temp_section="$WORK_DIR/edit_router.json"
    local temp_config="$WORK_DIR/config_new.json"

    jq '.router // {}' "$config" > "$temp_section"

    print_info "Editing router section (DNS seeds, tunnels, etc)..."
    echo "Current values:"
    cat "$temp_section"
    echo
    print_info "Press Enter to open editor..."
    read -r

    local editor=$(get_editor)
    $editor "$temp_section"

    if ! jq empty "$temp_section" 2>/dev/null; then
        print_error "Invalid JSON in edited section"
        return 1
    fi

    jq --slurpfile router "$temp_section" '.router = $router[0]' "$config" > "$temp_config"

    if validate_config "$temp_config"; then
        print_success "Router section updated"
        return 0
    else
        print_error "Config validation failed"
        return 1
    fi
}

# Main config editor menu
config_editor_menu() {
    while true; do
        clear
        print_ascii_header
        print_header "Config File Editor"

        echo "Config: $CJDNS_CONFIG"
        echo "Editor: $(get_editor)"
        echo
        echo "What would you like to edit?"
        echo
        echo "1) Admin Section (bind IP, password)"
        echo "2) Authorized Passwords"
        echo "3) IPv4 Peers (connectTo)"
        echo "4) IPv6 Peers (connectTo)"
        echo "5) IPv4 Interface Settings (bind, beacon, beaconDevices)"
        echo "6) IPv6 Interface Settings (bind, beacon)"
        echo "7) Router Section (DNS seeds, tunnels, publicPeer)"
        echo "8) Full Config (edit entire file - ADVANCED)"

        # Show fx option if available
        if command -v fx &>/dev/null; then
            echo "9) Interactive JSON Editor (fx) - RECOMMENDED"
        fi

        echo
        echo "C) Cleanup/Normalize Config (remove extra metadata)"
        echo "0) Back to Main Menu"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty

        case "$choice" in
            1|2|3|4|5|6|7)
                local temp_config="$WORK_DIR/config_new.json"

                case "$choice" in
                    1) edit_admin_section "$CJDNS_CONFIG" ;;
                    2) edit_authorized_passwords "$CJDNS_CONFIG" ;;
                    3) edit_ipv4_peers "$CJDNS_CONFIG" ;;
                    4) edit_ipv6_peers "$CJDNS_CONFIG" ;;
                    5) edit_ipv4_interface "$CJDNS_CONFIG" ;;
                    6) edit_ipv6_interface "$CJDNS_CONFIG" ;;
                    7) edit_router_section "$CJDNS_CONFIG" ;;
                esac

                if [ $? -eq 0 ]; then
                    if [ -f "$temp_config" ]; then
                        echo
                        if ask_yes_no "Save changes to config file?"; then
                            # Create backup now, after confirming save
                            echo
                            if ask_yes_no "Create backup before saving?"; then
                                local backup
                                if backup=$(backup_config "$CJDNS_CONFIG"); then
                                    print_success "Backup created: $backup"
                                else
                                    print_warning "Backup failed, but continuing with save"
                                fi
                            fi

                            cp "$temp_config" "$CJDNS_CONFIG"
                            print_success "Config file updated!"

                            if ask_yes_no "Restart cjdns service now?"; then
                                restart_service
                            fi
                        else
                            print_info "Changes discarded"
                        fi
                    fi
                fi

                echo
                read -p "Press Enter to continue..."
                ;;
            8)
                print_warning "ADVANCED: Editing entire config file"
                print_warning "Make sure you know what you're doing!"
                echo
                if ! ask_yes_no "Continue?"; then
                    continue
                fi

                # Create backup before full config edit for safety
                local backup
                echo
                if ask_yes_no "Create backup before editing?"; then
                    if backup=$(backup_config "$CJDNS_CONFIG"); then
                        print_success "Backup created: $backup"
                    else
                        print_error "Backup failed"
                        if ! ask_yes_no "Continue without backup?"; then
                            continue
                        fi
                    fi
                fi

                local editor=$(get_editor)
                $editor "$CJDNS_CONFIG"

                if validate_config "$CJDNS_CONFIG"; then
                    print_success "Config file is valid"
                    if ask_yes_no "Restart cjdns service now?"; then
                        restart_service
                    fi
                else
                    print_error "Config file is INVALID!"
                    if ask_yes_no "Restore from backup?"; then
                        cp "$backup" "$CJDNS_CONFIG"
                        print_success "Config restored from backup"
                    fi
                fi

                echo
                read -p "Press Enter to continue..."
                ;;
            9)
                if ! command -v fx &>/dev/null; then
                    print_error "fx is not installed"
                    echo
                    echo "Install fx with: sudo snap install fx"
                    echo "Or during initialization, select yes when prompted"
                    sleep 2
                    continue
                fi

                clear
                print_ascii_header
                print_bold "Interactive JSON Editor (fx)"
                echo
                echo "Navigation Tips:"
                echo "  • Arrow keys to navigate, Enter to expand/collapse"
                echo "  • Press 'q' to quit and save changes"
                echo "  • Press '?' for help"
                echo

                # Auto-create backup
                echo "Creating automatic backup..."
                local backup
                if backup=$(backup_config "$CJDNS_CONFIG"); then
                    print_success "Backup created: $backup"
                else
                    print_warning "Backup failed, but continuing"
                fi

                echo
                echo "Opening fx editor..."
                sleep 1

                # Open fx with piping to avoid filename parsing issues
                # Create temp file for editing
                local temp_fx="/tmp/cjdns_fx_edit_$$.json"
                cat "$CJDNS_CONFIG" | fx > "$temp_fx"

                # If fx succeeded and file was modified, update config
                if [ -s "$temp_fx" ]; then
                    mv "$temp_fx" "$CJDNS_CONFIG"
                else
                    rm -f "$temp_fx"
                    print_warning "No changes made or fx cancelled"
                fi

                # Validate after editing
                if validate_config "$CJDNS_CONFIG"; then
                    print_success "Config file is valid"
                    echo
                    if ask_yes_no "Restart cjdns service now?"; then
                        restart_service
                    fi
                else
                    print_error "Config file is INVALID!"
                    echo
                    if [ -n "$backup" ] && ask_yes_no "Restore from backup?"; then
                        cp "$backup" "$CJDNS_CONFIG"
                        print_success "Config restored from backup"
                    fi
                fi

                echo
                read -p "Press Enter to continue..."
                ;;
            [Cc])
                clear
                print_ascii_header
                print_header "Cleanup/Normalize Config"
                echo

                print_info "This will normalize your config to minimal required fields:"
                echo "  • connectTo entries: Only password and publicKey"
                echo "  • authorizedPasswords: Only password and user"
                echo
                print_info "Benefits:"
                echo "  • Smaller config file"
                echo "  • More reliable validation"
                echo "  • Prevents false 'credential update' detections"
                echo "  • Matches actual cjdns requirements"
                echo
                print_warning "Fields that will be removed: peerName, contact, location, login, gpg"
                print_info "These fields don't affect connectivity - only metadata"
                echo

                if ! ask_yes_no "Normalize config now?"; then
                    print_info "Cancelled"
                    echo
                    read -p "Press Enter to continue..."
                    continue
                fi

                echo

                # Call the normalize_config function from peeryeeter.sh
                if normalize_config "$CJDNS_CONFIG"; then
                    echo
                    if ask_yes_no "Restart cjdns service now to ensure changes work?"; then
                        restart_service
                    fi
                else
                    print_error "Normalization failed - see errors above"
                fi

                echo
                read -p "Press Enter to continue..."
                ;;
            0)
                return
                ;;
            *)
                print_error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}
