#!/usr/bin/env bash
# Guided Config Editor - User-friendly gum-based JSON editing
# This module provides step-by-step guided workflows for editing cjdns config

# Add a new peer with guided prompts
add_peer_guided() {
    clear
    print_ascii_header
    print_header "Add New Peer"
    echo

    # Step 1: Select peer type
    print_bold "Step 1: Select Peer Type"
    echo
    local peer_type
    peer_type=$(gum choose --height 6 "IPv4 Peer" "IPv6 Peer" "Cancel" </dev/tty >/dev/tty 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ] || [ -z "$peer_type" ] || [ "$peer_type" = "Cancel" ]; then
        return
    fi

    local interface_index
    if [ "$peer_type" = "IPv4 Peer" ]; then
        interface_index=0
    else
        interface_index=1
    fi

    # Step 2: Required fields
    clear
    print_ascii_header
    print_header "Add New Peer - Required Information"
    echo
    print_bold "Step 2: Enter Required Fields"
    echo

    # Get IP address
    echo "IP Address:"
    local ip_addr
    if [ "$peer_type" = "IPv4 Peer" ]; then
        ip_addr=$(gum input --placeholder "Example: 192.168.1.1" --width 60) </dev/tty >/dev/tty
    else
        ip_addr=$(gum input --placeholder "Example: 2001:db8::1 (without brackets)" --width 60) </dev/tty >/dev/tty
    fi
    [ -z "$ip_addr" ] && return

    # Wrap IPv6 in brackets
    if [ "$peer_type" = "IPv6 Peer" ]; then
        ip_addr="[$ip_addr]"
    fi

    # Get port
    echo
    echo "Port:"
    local port
    port=$(gum input --placeholder "Example: 51820" --width 60) </dev/tty >/dev/tty
    [ -z "$port" ] && return

    # Build full address
    local full_address="${ip_addr}:${port}"

    # Get password
    echo
    echo "Password:"
    local password
    password=$(gum input --placeholder "Example: jkq88yt0r236c02..." --width 60) </dev/tty >/dev/tty
    [ -z "$password" ] && return

    # Get public key
    echo
    echo "Public Key:"
    local pubkey
    pubkey=$(gum input --placeholder "Example: qb2knvkp2frp7vul...r0.k" --width 60) </dev/tty >/dev/tty
    [ -z "$pubkey" ] && return

    # Step 3: Common optional field (login)
    clear
    print_ascii_header
    print_header "Add New Peer - Optional Fields"
    echo
    print_bold "Step 3: Common Optional Field"
    echo

    echo "Login (commonly used, but optional):"
    echo "Press Enter to skip, or enter a login name"
    local login
    login=$(gum input --placeholder "Example: default-login" --width 60) </dev/tty >/dev/tty

    # Step 4: Custom fields loop
    declare -A custom_fields

    while true; do
        clear
        print_ascii_header
        print_header "Add New Peer - Custom Fields"
        echo
        print_bold "Step 4: Add Custom Fields (Optional)"
        echo

        echo "Current peer configuration:"
        echo "  Address:    $full_address"
        echo "  Password:   ${password:0:20}..."
        echo "  Public Key: ${pubkey:0:20}..."
        if [ -n "$login" ]; then
            echo "  Login:      $login"
        fi

        # Show existing custom fields
        if [ ${#custom_fields[@]} -gt 0 ]; then
            echo
            echo "Custom fields added:"
            for field_name in "${!custom_fields[@]}"; do
                echo "  $field_name: ${custom_fields[$field_name]}"
            done
        fi

        echo
        if ! gum confirm "Add another custom field?" </dev/tty >/dev/tty; then
            break
        fi

        # Get field name
        echo
        echo "Field name (e.g., peerName, contact, gpg, location):"
        local field_name
        field_name=$(gum input --placeholder "Enter field name" --width 60) </dev/tty >/dev/tty
        [ -z "$field_name" ] && continue

        # Get field value
        echo
        echo "Value for '$field_name':"
        local field_value
        field_value=$(gum input --placeholder "Enter value" --width 60) </dev/tty >/dev/tty
        [ -z "$field_value" ] && continue

        # Store custom field
        custom_fields["$field_name"]="$field_value"
    done

    # Step 5: Preview and confirm
    clear
    print_ascii_header
    print_header "Add New Peer - Review"
    echo
    print_bold "Step 5: Review and Confirm"
    echo

    echo "You are about to add this peer:"
    echo
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│ Address:    $full_address"
    echo "│ Password:   $password"
    echo "│ Public Key: $pubkey"
    if [ -n "$login" ]; then
        echo "│ Login:      $login"
    fi
    for field_name in "${!custom_fields[@]}"; do
        printf "│ %-11s %s\n" "$field_name:" "${custom_fields[$field_name]}"
    done
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo

    if ! gum confirm "Add this peer to your config?" </dev/tty >/dev/tty; then
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Create backup
    echo
    print_working "Creating automatic backup..."
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    else
        print_warning "Backup failed, but continuing"
    fi

    # Build JSON object
    local peer_json='{'
    peer_json+="\"password\":\"$password\","
    peer_json+="\"publicKey\":\"$pubkey\""

    if [ -n "$login" ]; then
        peer_json+=",\"login\":\"$login\""
    fi

    for field_name in "${!custom_fields[@]}"; do
        peer_json+=",\"$field_name\":\"${custom_fields[$field_name]}\""
    done

    peer_json+='}'

    # Add to config using jq
    echo
    print_working "Adding peer to config..."

    local temp_config="/tmp/cjdns_add_peer_$$.json"
    if jq ".interfaces.UDPInterface[$interface_index].connectTo[\"$full_address\"] = $peer_json" "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            mv "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Peer added successfully!"

            # Ask about restart
            echo
            if gum confirm "Restart cjdns service now?" </dev/tty >/dev/tty; then
                restart_service
            fi
        else
            print_error "Generated config is invalid - not saving"
            rm -f "$temp_config"
        fi
    else
        print_error "Failed to add peer"
        rm -f "$temp_config"
    fi

    echo
    read -p "Press Enter to continue..."
}

# View all peers (read-only)
view_all_peers() {
    clear
    print_ascii_header
    print_header "View All Peers"
    echo

    # Get IPv4 peers
    local ipv4_peers=$(jq -r '.interfaces.UDPInterface[0].connectTo // {} | to_entries | .[] | "\(.key)|\(.value.login // "no-login")|\(.value.publicKey)"' "$CJDNS_CONFIG" 2>/dev/null)
    local ipv4_count=$(echo "$ipv4_peers" | grep -c "^" || echo 0)

    # Get IPv6 peers
    local ipv6_peers=$(jq -r '.interfaces.UDPInterface[1].connectTo // {} | to_entries | .[] | "\(.key)|\(.value.login // "no-login")|\(.value.publicKey)"' "$CJDNS_CONFIG" 2>/dev/null)
    local ipv6_count=$(echo "$ipv6_peers" | grep -c "^" || echo 0)

    print_bold "IPv4 Peers ($ipv4_count total)"
    echo
    if [ $ipv4_count -gt 0 ]; then
        while IFS='|' read -r address login pubkey; do
            [ -z "$address" ] && continue
            echo "  Address:    $address"
            echo "  Login:      $login"
            echo "  Public Key: ${pubkey:0:40}..."
            echo
        done <<< "$ipv4_peers"
    else
        echo "  No IPv4 peers configured"
        echo
    fi

    print_bold "IPv6 Peers ($ipv6_count total)"
    echo
    if [ $ipv6_count -gt 0 ]; then
        while IFS='|' read -r address login pubkey; do
            [ -z "$address" ] && continue
            echo "  Address:    $address"
            echo "  Login:      $login"
            echo "  Public Key: ${pubkey:0:40}..."
            echo
        done <<< "$ipv6_peers"
    else
        echo "  No IPv6 peers configured"
        echo
    fi

    read -p "Press Enter to continue..."
}

# Main guided config editor menu
guided_config_editor() {
    while true; do
        clear
        print_ascii_header
        print_header "Guided Config Editor"
        echo

        echo "What would you like to do?"
        echo
        echo "1) ➕ Add New Peer"
        echo "2) 👁️  View All Peers"
        echo "3) 🗑️  Remove Peers (coming soon)"
        echo "4) ✏️  Edit Existing Peer (coming soon)"
        echo "5) 🔐 Manage Authorized Passwords (coming soon)"
        echo
        echo "0) Back to Main Menu"
        echo

        local choice
        read -p "Enter choice: " choice

        case "$choice" in
            1) add_peer_guided ;;
            2) view_all_peers ;;
            3) print_warning "Coming soon!"; sleep 1 ;;
            4) print_warning "Coming soon!"; sleep 1 ;;
            5) print_warning "Coming soon!"; sleep 1 ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}
