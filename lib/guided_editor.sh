#!/usr/bin/env bash
# Guided Config Editor - Compatible with gum v0.17.0 (no form command)

# Add a new peer with interactive editor
add_peer_guided() {
    clear
    print_ascii_header
    print_header "Add New Peer - Interactive Editor"
    echo

    # Step 1: Select peer type
    print_bold "Step 1: Select Peer Type"
    echo
    print_info "Use arrow keys to navigate, Enter to select"
    echo
    local peer_type
    peer_type=$(gum choose --height 6 "IPv4 Peer" "IPv6 Peer" "Cancel" 2>/dev/tty </dev/tty)
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

    # Initialize peer fields
    local ip_addr="" port="" password="" pubkey="" login=""
    declare -A custom_fields

    # Step 2: Interactive field editor
    while true; do
        clear
        print_ascii_header
        print_header "Add New Peer - Edit Fields"
        echo
        print_bold "Current Peer Configuration:"
        echo
        echo "┌────────────────────────────────────────────────────────────────┐"
        printf "│ %-15s %-46s │\n" "IP Address:" "${ip_addr:-<not set>}"
        printf "│ %-15s %-46s │\n" "Port:" "${port:-<not set>}"
        if [ -n "$password" ]; then
            printf "│ %-15s %-46s │\n" "Password:" "${password:0:40}..."
        else
            printf "│ %-15s %-46s │\n" "Password:" "<not set>"
        fi
        if [ -n "$pubkey" ]; then
            printf "│ %-15s %-46s │\n" "Public Key:" "${pubkey:0:40}..."
        else
            printf "│ %-15s %-46s │\n" "Public Key:" "<not set>"
        fi
        printf "│ %-15s %-46s │\n" "Login:" "${login:-<optional>}"

        set +u  # Temporarily disable for array check
        if [ ${#custom_fields[@]} -gt 0 ]; then
            echo "├────────────────────────────────────────────────────────────────┤"
            printf "│ %-62s │\n" "OPTIONAL FIELDS:"
            for field_name in "${!custom_fields[@]}"; do
                local val="${custom_fields[$field_name]}"
                printf "│ %-15s %-46s │\n" "$field_name:" "${val:0:46}"
            done
        fi
        set -u  # Re-enable
        echo "└────────────────────────────────────────────────────────────────┘"
        echo

        # Check if required fields are filled
        local can_save=false
        if [ -n "$ip_addr" ] && [ -n "$port" ] && [ -n "$password" ] && [ -n "$pubkey" ]; then
            can_save=true
        fi

        # Build menu options
        local -a menu_options=()
        menu_options+=("Edit IP Address")
        menu_options+=("Edit Port")
        menu_options+=("Edit Password")
        menu_options+=("Edit Public Key")
        menu_options+=("Edit Login (optional)")
        menu_options+=("Add/Edit Custom Field")

        if [ $can_save = true ]; then
            menu_options+=("✓ SAVE AND ADD PEER")
        else
            menu_options+=("✗ Save (missing required fields)")
        fi
        menu_options+=("Cancel")

        echo
        print_info "Select a field to edit, or Save when ready:"
        echo

        local choice
        choice=$(gum choose --height 12 "${menu_options[@]}" 2>/dev/tty </dev/tty)

        case "$choice" in
            "Edit IP Address")
                echo
                if [ "$peer_type" = "IPv4 Peer" ]; then
                    ip_addr=$(gum input --placeholder "Example: 192.168.1.1" --value "$ip_addr" --width 60 2>/dev/tty </dev/tty)
                else
                    ip_addr=$(gum input --placeholder "Example: 2001:db8::1 (no brackets)" --value "$ip_addr" --width 60 2>/dev/tty </dev/tty)
                fi
                ;;
            "Edit Port")
                echo
                port=$(gum input --placeholder "Example: 51820" --value "$port" --width 60 2>/dev/tty </dev/tty)
                ;;
            "Edit Password")
                echo
                password=$(gum input --placeholder "Peer password" --value "$password" --width 60 2>/dev/tty </dev/tty)
                ;;
            "Edit Public Key")
                echo
                pubkey=$(gum input --placeholder "Peer public key (ends with .k)" --value "$pubkey" --width 60 2>/dev/tty </dev/tty)
                ;;
            "Edit Login (optional)")
                echo
                login=$(gum input --placeholder "Login name (optional)" --value "$login" --width 60 2>/dev/tty </dev/tty)
                ;;
            "Add/Edit Custom Field")
                echo
                local field_name
                field_name=$(gum input --placeholder "Field name (e.g., peerName, contact, gpg, location)" --width 60 2>/dev/tty </dev/tty)
                if [ -n "$field_name" ]; then
                    echo
                    local field_value
                    field_value=$(gum input --placeholder "Value for $field_name" --value "${custom_fields[$field_name]}" --width 60 2>/dev/tty </dev/tty)
                    if [ -n "$field_value" ]; then
                        custom_fields["$field_name"]="$field_value"
                    fi
                fi
                ;;
            "✓ SAVE AND ADD PEER")
                break
                ;;
            "✗ Save (missing required fields)")
                echo
                print_error "Cannot save - missing required fields:"
                [ -z "$ip_addr" ] && echo "  • IP Address"
                [ -z "$port" ] && echo "  • Port"
                [ -z "$password" ] && echo "  • Password"
                [ -z "$pubkey" ] && echo "  • Public Key"
                echo
                read -p "Press Enter to continue editing..."
                ;;
            "Cancel"|"")
                print_info "Cancelled"
                echo
                read -p "Press Enter to continue..."
                return
                ;;
        esac
    done

    # Wrap IPv6 in brackets if needed
    if [ "$peer_type" = "IPv6 Peer" ] && [[ ! "$ip_addr" =~ ^\[ ]]; then
        ip_addr="[$ip_addr]"
    fi

    # Build full address
    local full_address="${ip_addr}:${port}"

    # Step 3: Preview and confirm
    clear
    print_ascii_header
    print_header "Add New Peer - Review"
    echo
    print_bold "Review and Confirm"
    echo

    echo "You are about to add this peer:"
    echo
    echo "┌─────────────────────────────────────────────────────────────────────────┐"
    printf "│ %-15s %-55s │\n" "Address:" "$full_address"
    printf "│ %-15s %-55s │\n" "Password:" "$password"
    printf "│ %-15s %-55s │\n" "Public Key:" "$pubkey"
    if [ -n "$login" ]; then
        printf "│ %-15s %-55s │\n" "Login:" "$login"
    fi
    for field_name in "${!custom_fields[@]}"; do
        printf "│ %-15s %-55s │\n" "$field_name:" "${custom_fields[$field_name]}"
    done
    echo "└─────────────────────────────────────────────────────────────────────────┘"
    echo

    if ! gum confirm "Add this peer to your config?" 2>/dev/tty </dev/tty; then
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

    # Build JSON object properly
    local peer_json
    peer_json=$(jq -n \
        --arg pw "$password" \
        --arg pk "$pubkey" \
        '{password: $pw, publicKey: $pk}')

    if [ -n "$login" ]; then
        peer_json=$(echo "$peer_json" | jq --arg l "$login" '. + {login: $l}')
    fi

    for field_name in "${!custom_fields[@]}"; do
        peer_json=$(echo "$peer_json" | jq --arg fn "$field_name" --arg fv "${custom_fields[$field_name]}" '. + {($fn): $fv}')
    done

    # Add to config using jq
    echo
    print_working "Adding peer to config..."

    local temp_config="$WORK_DIR/cjdns_add_peer.json"
    if jq --arg addr "$full_address" --argjson peer "$peer_json" --argjson idx "$interface_index" \
        '.interfaces.UDPInterface[$idx].connectTo[$addr] = $peer' \
        "$CJDNS_CONFIG" > "$temp_config"; then

        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Peer added successfully!"

            # Ask about restart
            echo
            if gum confirm "Restart cjdns service now?" 2>/dev/tty </dev/tty; then
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

# Edit an existing peer
edit_peer_guided() {
    clear
    print_ascii_header
    print_header "Edit Existing Peer"
    echo

    # Get all peers from both interfaces
    declare -a all_peers
    declare -a peer_ifaces
    local index=0

    # Get IPv4 peers
    while IFS= read -r addr; do
        if [ -n "$addr" ]; then
            all_peers+=("$addr (IPv4)")
            peer_ifaces+=("0")
            index=$((index + 1))
        fi
    done < <(jq -r '.interfaces.UDPInterface[0].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null)

    # Get IPv6 peers
    while IFS= read -r addr; do
        if [ -n "$addr" ]; then
            all_peers+=("$addr (IPv6)")
            peer_ifaces+=("1")
            index=$((index + 1))
        fi
    done < <(jq -r '.interfaces.UDPInterface[1].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null)

    if [ ${#all_peers[@]} -eq 0 ]; then
        print_warning "No peers found in config"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    print_success "Found ${#all_peers[@]} peers in config"
    echo
    print_info "Select a peer to edit:"
    echo

    local selected
    selected=$(gum choose --height 20 "${all_peers[@]}" "Cancel" 2>/dev/tty </dev/tty)

    if [ -z "$selected" ] || [ "$selected" = "Cancel" ]; then
        return
    fi

    # Extract address and interface index
    local selected_idx=-1
    for i in "${!all_peers[@]}"; do
        if [ "${all_peers[$i]}" = "$selected" ]; then
            selected_idx=$i
            break
        fi
    done

    local interface_index="${peer_ifaces[$selected_idx]}"
    local peer_addr=$(echo "$selected" | sed 's/ (.*)$//')

    # Get current peer data
    local peer_data
    peer_data=$(jq --arg addr "$peer_addr" --argjson idx "$interface_index" \
        '.interfaces.UDPInterface[$idx].connectTo[$addr]' "$CJDNS_CONFIG")

    # Extract all current values
    local password=$(echo "$peer_data" | jq -r '.password // ""')
    local pubkey=$(echo "$peer_data" | jq -r '.publicKey // ""')
    local login=$(echo "$peer_data" | jq -r '.login // ""')

    # Extract all other fields into custom_fields
    declare -A custom_fields
    while IFS='|' read -r key value; do
        if [ "$key" != "password" ] && [ "$key" != "publicKey" ] && [ "$key" != "login" ] && [ -n "$key" ]; then
            custom_fields["$key"]="$value"
        fi
    done < <(echo "$peer_data" | jq -r 'to_entries[] | "\(.key)|\(.value)"')

    # Interactive edit loop
    while true; do
        clear
        print_ascii_header
        print_header "Edit Peer: $peer_addr"
        echo
        print_bold "Current Configuration:"
        echo
        echo "┌────────────────────────────────────────────────────────────────┐"
        printf "│ %-15s %-46s │\n" "Address:" "$peer_addr"
        if [ -n "$password" ]; then
            printf "│ %-15s %-46s │\n" "Password:" "${password:0:40}..."
        else
            printf "│ %-15s %-46s │\n" "Password:" "<not set>"
        fi
        if [ -n "$pubkey" ]; then
            printf "│ %-15s %-46s │\n" "Public Key:" "${pubkey:0:40}..."
        else
            printf "│ %-15s %-46s │\n" "Public Key:" "<not set>"
        fi
        printf "│ %-15s %-46s │\n" "Login:" "${login:-<not set>}"

        set +u  # Temporarily disable for array check
        if [ ${#custom_fields[@]} -gt 0 ]; then
            echo "├────────────────────────────────────────────────────────────────┤"
            printf "│ %-62s │\n" "OPTIONAL FIELDS:"
            for field_name in "${!custom_fields[@]}"; do
                local val="${custom_fields[$field_name]}"
                printf "│ %-15s %-46s │\n" "$field_name:" "${val:0:46}"
            done
        fi
        set -u  # Re-enable
        echo "└────────────────────────────────────────────────────────────────┘"
        echo

        # Check if required fields are filled
        local can_save=false
        if [ -n "$password" ] && [ -n "$pubkey" ]; then
            can_save=true
        fi

        # Build menu options
        local -a menu_options=()
        menu_options+=("Edit Password")
        menu_options+=("Edit Public Key")
        menu_options+=("Edit Login")
        menu_options+=("Add/Edit Custom Field")
        menu_options+=("Remove Custom Field")

        if [ $can_save = true ]; then
            menu_options+=("✓ SAVE CHANGES")
        else
            menu_options+=("✗ Save (missing required fields)")
        fi
        menu_options+=("Cancel")

        echo
        print_info "Select a field to edit, or Save when ready:"
        echo

        local choice
        choice=$(gum choose --height 12 "${menu_options[@]}" 2>/dev/tty </dev/tty)

        case "$choice" in
            "Edit Password")
                echo
                password=$(gum input --placeholder "Peer password" --value "$password" --width 60 2>/dev/tty </dev/tty)
                ;;
            "Edit Public Key")
                echo
                pubkey=$(gum input --placeholder "Peer public key (ends with .k)" --value "$pubkey" --width 60 2>/dev/tty </dev/tty)
                ;;
            "Edit Login")
                echo
                login=$(gum input --placeholder "Login name (optional)" --value "$login" --width 60 2>/dev/tty </dev/tty)
                ;;
            "Add/Edit Custom Field")
                echo
                local field_name
                field_name=$(gum input --placeholder "Field name (e.g., peerName, contact, gpg, location)" --width 60 2>/dev/tty </dev/tty)
                if [ -n "$field_name" ]; then
                    echo
                    local field_value
                    field_value=$(gum input --placeholder "Value for $field_name" --value "${custom_fields[$field_name]}" --width 60 2>/dev/tty </dev/tty)
                    if [ -n "$field_value" ]; then
                        custom_fields["$field_name"]="$field_value"
                    fi
                fi
                ;;
            "Remove Custom Field")
                set +u  # Temporarily disable for array check
                if [ ${#custom_fields[@]} -eq 0 ]; then
                    set -u  # Re-enable
                    echo
                    print_warning "No custom fields to remove"
                    sleep 1
                else
                    set -u  # Re-enable
                    echo
                    local -a field_list=()
                    for fn in "${!custom_fields[@]}"; do
                        field_list+=("$fn")
                    done
                    local to_remove
                    to_remove=$(gum choose --height 10 "${field_list[@]}" "Cancel" 2>/dev/tty </dev/tty)
                    if [ -n "$to_remove" ] && [ "$to_remove" != "Cancel" ]; then
                        unset custom_fields["$to_remove"]
                    fi
                fi
                ;;
            "✓ SAVE CHANGES")
                break
                ;;
            "✗ Save (missing required fields)")
                echo
                print_error "Cannot save - missing required fields:"
                [ -z "$password" ] && echo "  • Password"
                [ -z "$pubkey" ] && echo "  • Public Key"
                echo
                read -p "Press Enter to continue editing..."
                ;;
            "Cancel"|"")
                print_info "Cancelled"
                echo
                read -p "Press Enter to continue..."
                return
                ;;
        esac
    done

    # Build new peer JSON
    local new_peer_json
    new_peer_json=$(jq -n \
        --arg pw "$password" \
        --arg pk "$pubkey" \
        '{password: $pw, publicKey: $pk}')

    [ -n "$login" ] && new_peer_json=$(echo "$new_peer_json" | jq --arg v "$login" '. + {login: $v}')

    for field_name in "${!custom_fields[@]}"; do
        new_peer_json=$(echo "$new_peer_json" | jq --arg fn "$field_name" --arg fv "${custom_fields[$field_name]}" '. + {($fn): $fv}')
    done

    # Preview changes
    clear
    print_ascii_header
    print_header "Review Changes"
    echo
    print_bold "Peer: $peer_addr"
    echo

    echo "Updated peer configuration:"
    echo "$new_peer_json" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    echo

    if ! gum confirm "Save these changes?" 2>/dev/tty </dev/tty; then
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

    # Update config
    echo
    print_working "Updating peer in config..."

    local temp_config="$WORK_DIR/cjdns_edit_peer.json"
    if jq --arg addr "$peer_addr" --argjson peer "$new_peer_json" --argjson idx "$interface_index" \
        '.interfaces.UDPInterface[$idx].connectTo[$addr] = $peer' \
        "$CJDNS_CONFIG" > "$temp_config"; then

        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Peer updated successfully!"

            echo
            if gum confirm "Restart cjdns service now?" 2>/dev/tty </dev/tty; then
                restart_service
            fi
        else
            print_error "Generated config is invalid - not saving"
        fi
    else
        print_error "Failed to update peer"
    fi

    echo
    read -p "Press Enter to continue..."
}

# View all peers
view_all_peers() {
    clear
    print_ascii_header
    print_header "View All Peers"
    echo

    local ipv4_count=0
    print_bold "IPv4 Peers"
    echo

    while IFS= read -r peer_entry; do
        [ -z "$peer_entry" ] && continue
        ipv4_count=$((ipv4_count + 1))

        local address=$(echo "$peer_entry" | jq -r '.key')
        echo "Peer #$ipv4_count: $address"
        echo "$peer_entry" | jq -r '.value | to_entries | .[] | "  \(.key): \(.value)"'
        echo
    done < <(jq -c '.interfaces.UDPInterface[0].connectTo // {} | to_entries | .[]' "$CJDNS_CONFIG" 2>/dev/null)

    if [ $ipv4_count -eq 0 ]; then
        echo "  No IPv4 peers configured"
        echo
    fi

    local ipv6_count=0
    print_bold "IPv6 Peers"
    echo

    while IFS= read -r peer_entry; do
        [ -z "$peer_entry" ] && continue
        ipv6_count=$((ipv6_count + 1))

        local address=$(echo "$peer_entry" | jq -r '.key')
        echo "Peer #$ipv6_count: $address"
        echo "$peer_entry" | jq -r '.value | to_entries | .[] | "  \(.key): \(.value)"'
        echo
    done < <(jq -c '.interfaces.UDPInterface[1].connectTo // {} | to_entries | .[]' "$CJDNS_CONFIG" 2>/dev/null)

    if [ $ipv6_count -eq 0 ]; then
        echo "  No IPv6 peers configured"
        echo
    fi

    echo "Total: $ipv4_count IPv4 peers, $ipv6_count IPv6 peers"
    echo
    read -p "Press Enter to continue..."
}

# Configure public peering
configure_public_peering() {
    clear
    print_ascii_header
    print_header "Configure Public Peering"
    echo

    # Check current state
    local current_id
    current_id=$(jq -r '.router.publicPeer.id // ""' "$CJDNS_CONFIG" 2>/dev/null)

    if [ -n "$current_id" ]; then
        print_success "Public peering is currently ENABLED"
        echo "  Node ID: $current_id"
        echo
        print_info "Use arrow keys to navigate, Enter to select"
        echo

        local action
        if action=$(gum choose --height 6 "Change Node Name" "Disable Public Peering" "Cancel" 2>/dev/tty </dev/tty); then
            :
        else
            return
        fi

        case "$action" in
            "Change Node Name")
                echo
                local new_name
                new_name=$(gum input --placeholder "Enter new node name (e.g., YourNodeName)" --value "${current_id#PUB_}" --width 60 2>/dev/tty </dev/tty)
                if [ -z "$new_name" ]; then
                    print_info "Cancelled"
                    sleep 1
                    return
                fi

                # Create backup
                echo
                print_working "Creating automatic backup..."
                local backup
                if backup=$(backup_config "$CJDNS_CONFIG"); then
                    print_success "Backup created: $backup"
                else
                    print_warning "Backup failed"
                    if ! gum confirm "Continue without backup?" 2>/dev/tty </dev/tty; then
                        return
                    fi
                fi

                # Update config
                local temp_config="$WORK_DIR/config_public_peer.json"
                if jq --arg id "PUB_$new_name" '.router.publicPeer.id = $id' "$CJDNS_CONFIG" > "$temp_config"; then
                    if validate_config "$temp_config"; then
                        cp "$temp_config" "$CJDNS_CONFIG"
                        echo
                        print_success "Public peer node name updated to: PUB_$new_name"
                        prompt_restart_with_journal
                    else
                        print_error "Config validation failed - changes not applied"
                    fi
                else
                    print_error "Failed to update config"
                fi
                ;;
            "Disable Public Peering")
                echo
                if ! gum confirm "Are you sure you want to disable public peering?" 2>/dev/tty </dev/tty; then
                    print_info "Cancelled"
                    sleep 1
                    return
                fi

                # Create backup
                echo
                print_working "Creating automatic backup..."
                local backup
                if backup=$(backup_config "$CJDNS_CONFIG"); then
                    print_success "Backup created: $backup"
                else
                    print_warning "Backup failed"
                    if ! gum confirm "Continue without backup?" 2>/dev/tty </dev/tty; then
                        return
                    fi
                fi

                # Update config - set publicPeer to empty object
                local temp_config="$WORK_DIR/config_public_peer.json"
                if jq '.router.publicPeer = {}' "$CJDNS_CONFIG" > "$temp_config"; then
                    if validate_config "$temp_config"; then
                        cp "$temp_config" "$CJDNS_CONFIG"
                        echo
                        print_success "Public peering disabled"
                        prompt_restart_with_journal
                    else
                        print_error "Config validation failed - changes not applied"
                    fi
                else
                    print_error "Failed to update config"
                fi
                ;;
            "Cancel"|"")
                return
                ;;
        esac
    else
        print_info "Public peering is currently DISABLED"
        echo
        echo "Enabling public peering allows other nodes on the network to"
        echo "automatically discover and connect to your node."
        echo
        print_info "Use arrow keys to navigate, Enter to select"
        echo

        local action
        if action=$(gum choose --height 6 "Enable Public Peering" "Cancel" 2>/dev/tty </dev/tty); then
            :
        else
            return
        fi

        case "$action" in
            "Enable Public Peering")
                echo
                print_info "Enter a name for your node (will be prefixed with PUB_)"
                local node_name
                node_name=$(gum input --placeholder "Enter node name (e.g., YourNodeName)" --width 60 2>/dev/tty </dev/tty)
                if [ -z "$node_name" ]; then
                    print_info "Cancelled"
                    sleep 1
                    return
                fi

                # Confirm
                echo
                print_bold "Your public peer ID will be: PUB_$node_name"
                echo
                if ! gum confirm "Enable public peering with this name?" 2>/dev/tty </dev/tty; then
                    print_info "Cancelled"
                    sleep 1
                    return
                fi

                # Create backup
                echo
                print_working "Creating automatic backup..."
                local backup
                if backup=$(backup_config "$CJDNS_CONFIG"); then
                    print_success "Backup created: $backup"
                else
                    print_warning "Backup failed"
                    if ! gum confirm "Continue without backup?" 2>/dev/tty </dev/tty; then
                        return
                    fi
                fi

                # Update config
                local temp_config="$WORK_DIR/config_public_peer.json"
                if jq --arg id "PUB_$node_name" '.router.publicPeer = {id: $id}' "$CJDNS_CONFIG" > "$temp_config"; then
                    if validate_config "$temp_config"; then
                        cp "$temp_config" "$CJDNS_CONFIG"
                        echo
                        print_success "Public peering enabled!"
                        echo "  Node ID: PUB_$node_name"
                        prompt_restart_with_journal
                    else
                        print_error "Config validation failed - changes not applied"
                    fi
                else
                    print_error "Failed to update config"
                fi
                ;;
            "Cancel"|"")
                return
                ;;
        esac
    fi

    echo
    read -p "Press Enter to continue..."
}

# Prompt for restart and show journal output
prompt_restart_with_journal() {
    echo
    if [ -z "$CJDNS_SERVICE" ]; then
        print_warning "Service management unavailable - restart manually if needed"
        return
    fi

    if gum confirm "Restart cjdns service now?" 2>/dev/tty </dev/tty; then
        print_subheader "Restarting cjdns Service"
        echo "Restarting $CJDNS_SERVICE..."

        if systemctl restart "$CJDNS_SERVICE"; then
            print_success "Service restart command sent"

            # Wait for service to fully start before showing journal
            sleep 6

            # Show journal output regardless of status
            echo
            print_subheader "Service Journal (last 10 lines)"
            echo "─────────────────────────────────────────────────────────────────"
            journalctl -u "$CJDNS_SERVICE" -b --no-pager -n 10 2>/dev/null || echo "Unable to read journal"
            echo "─────────────────────────────────────────────────────────────────"

            # Check if cjdns is responding
            echo
            local attempts=0
            local max_attempts=3
            while [ $attempts -lt $max_attempts ]; do
                sleep 2
                if test_cjdnstool_connection "$ADMIN_IP" "$ADMIN_PORT" "$ADMIN_PASSWORD" 2>/dev/null; then
                    print_success "cjdns is running and responding"
                    return
                fi
                attempts=$((attempts + 1))
            done

            print_warning "Service restarted but not responding yet"
            print_info "Check the journal output above for any errors"
        else
            print_error "Failed to restart service"
            echo
            print_subheader "Service Journal (last 10 lines)"
            echo "─────────────────────────────────────────────────────────────────"
            journalctl -u "$CJDNS_SERVICE" -b --no-pager -n 10 2>/dev/null || echo "Unable to read journal"
            echo "─────────────────────────────────────────────────────────────────"
        fi
    fi
}

# ============================================================================
# AUTHORIZED PASSWORDS MANAGEMENT
# ============================================================================

# Manage authorized passwords (credentials for incoming connections)
manage_authorized_passwords() {
    while true; do
        clear
        print_ascii_header
        print_header "Authorized Passwords Management"
        echo
        print_info "These credentials allow OTHER nodes to connect TO you."
        echo

        # Get current authorized passwords
        local passwords_json
        passwords_json=$(jq -c '.authorizedPasswords // []' "$CJDNS_CONFIG" 2>/dev/null)
        local count
        count=$(echo "$passwords_json" | jq 'length')

        if [ "$count" -gt 0 ]; then
            print_bold "Current Authorized Passwords ($count entries):"
            echo
            echo "┌────────────────────────────────────────────────────────────────────────────┐"
            local idx=0
            while IFS= read -r entry; do
                [ -z "$entry" ] && continue
                local user=$(echo "$entry" | jq -r '.user // "unnamed"')
                local pass=$(echo "$entry" | jq -r '.password // ""')
                local display_pass="${pass:0:25}..."
                printf "│ %-3s %-20s %-48s │\n" "$((idx+1))." "User: $user" "Pass: $display_pass"
                idx=$((idx+1))
            done < <(echo "$passwords_json" | jq -c '.[]')
            echo "└────────────────────────────────────────────────────────────────────────────┘"
        else
            print_warning "No authorized passwords configured"
        fi
        echo

        echo "Options:"
        echo
        echo "1) ➕ Add New Authorized Password"
        echo "2) ✏️  Edit Existing Password"
        echo "3) 🗑️  Remove Password"
        echo "4) 🎲 Generate Random Password"
        echo
        echo "0) Back"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty

        case "$choice" in
            1) add_authorized_password ;;
            2) edit_authorized_password ;;
            3) remove_authorized_password ;;
            4) generate_authorized_password ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# Add a new authorized password
add_authorized_password() {
    clear
    print_ascii_header
    print_header "Add New Authorized Password"
    echo

    print_info "Enter credentials for a new incoming connection"
    echo

    local user pass

    echo
    print_bold "User/Login name (identifies the peer):"
    user=$(gum input --placeholder "e.g., my-friend-node" --width 60 2>/dev/tty </dev/tty)
    if [ -z "$user" ]; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    echo
    print_bold "Password (shared secret for authentication):"
    pass=$(gum input --placeholder "Enter password or leave blank to generate" --width 60 2>/dev/tty </dev/tty)

    # Generate random password if not provided
    if [ -z "$pass" ]; then
        pass=$(head -c 48 /dev/urandom | base64 | tr -dc 'a-z0-9-' | head -c 28)
        print_info "Generated password: $pass"
    fi

    echo
    echo "┌────────────────────────────────────────────────────────────────┐"
    printf "│ %-15s %-46s │\n" "User:" "$user"
    printf "│ %-15s %-46s │\n" "Password:" "$pass"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo

    if ! gum confirm "Add this authorized password?" 2>/dev/tty </dev/tty; then
        print_info "Cancelled"
        sleep 1
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

    # Add to config
    print_working "Adding authorized password..."
    local temp_config="$WORK_DIR/cjdns_add_auth.json"
    local new_entry
    new_entry=$(jq -n --arg u "$user" --arg p "$pass" '{password: $p, user: $u}')

    if jq --argjson entry "$new_entry" '.authorizedPasswords += [$entry]' "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Authorized password added successfully!"
            echo
            print_info "Share these credentials with peers who want to connect to you:"
            echo
            echo "  User: $user"
            echo "  Password: $pass"
            echo "  Public Key: $(jq -r '.publicKey' "$CJDNS_CONFIG")"
            prompt_restart_with_journal
        else
            print_error "Config validation failed - changes not applied"
        fi
    else
        print_error "Failed to add authorized password"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Edit an existing authorized password
edit_authorized_password() {
    clear
    print_ascii_header
    print_header "Edit Authorized Password"
    echo

    # Get current passwords
    local passwords_json
    passwords_json=$(jq -c '.authorizedPasswords // []' "$CJDNS_CONFIG" 2>/dev/null)
    local count
    count=$(echo "$passwords_json" | jq 'length')

    if [ "$count" -eq 0 ]; then
        print_warning "No authorized passwords to edit"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Build selection list
    local -a options=()
    local idx=0
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        local user=$(echo "$entry" | jq -r '.user // "unnamed"')
        options+=("$((idx+1)). $user")
        idx=$((idx+1))
    done < <(echo "$passwords_json" | jq -c '.[]')
    options+=("Cancel")

    print_info "Select a password entry to edit:"
    echo

    local selected
    selected=$(gum choose --height 15 "${options[@]}" 2>/dev/tty </dev/tty)

    if [ -z "$selected" ] || [ "$selected" = "Cancel" ]; then
        return
    fi

    # Extract index
    local selected_idx
    selected_idx=$(echo "$selected" | grep -o '^[0-9]*' | head -1)
    selected_idx=$((selected_idx - 1))

    # Get current values
    local current_user current_pass
    current_user=$(echo "$passwords_json" | jq -r ".[$selected_idx].user // \"\"")
    current_pass=$(echo "$passwords_json" | jq -r ".[$selected_idx].password // \"\"")

    echo
    print_bold "Current values:"
    echo "  User: $current_user"
    echo "  Password: $current_pass"
    echo

    print_bold "Enter new values (leave blank to keep current):"
    echo

    local new_user new_pass
    new_user=$(gum input --placeholder "User (current: $current_user)" --value "$current_user" --width 60 2>/dev/tty </dev/tty)
    [ -z "$new_user" ] && new_user="$current_user"

    echo
    new_pass=$(gum input --placeholder "Password (leave blank to keep current)" --width 60 2>/dev/tty </dev/tty)
    [ -z "$new_pass" ] && new_pass="$current_pass"

    if [ "$new_user" = "$current_user" ] && [ "$new_pass" = "$current_pass" ]; then
        print_info "No changes made"
        sleep 1
        return
    fi

    echo
    if ! gum confirm "Save changes?" 2>/dev/tty </dev/tty; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Create backup
    echo
    print_working "Creating automatic backup..."
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    fi

    # Update config
    print_working "Updating authorized password..."
    local temp_config="$WORK_DIR/cjdns_edit_auth.json"

    if jq --argjson idx "$selected_idx" --arg u "$new_user" --arg p "$new_pass" \
        '.authorizedPasswords[$idx] = {password: $p, user: $u}' "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Authorized password updated!"
            print_warning "Peers using the old credentials will need to be updated!"
            prompt_restart_with_journal
        else
            print_error "Config validation failed - changes not applied"
        fi
    else
        print_error "Failed to update authorized password"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Remove an authorized password
remove_authorized_password() {
    clear
    print_ascii_header
    print_header "Remove Authorized Password"
    echo

    # Get current passwords
    local passwords_json
    passwords_json=$(jq -c '.authorizedPasswords // []' "$CJDNS_CONFIG" 2>/dev/null)
    local count
    count=$(echo "$passwords_json" | jq 'length')

    if [ "$count" -eq 0 ]; then
        print_warning "No authorized passwords to remove"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    if [ "$count" -eq 1 ]; then
        print_error "Cannot remove the last authorized password!"
        print_info "You must have at least one authorized password configured."
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Build selection list
    local -a options=()
    local idx=0
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        local user=$(echo "$entry" | jq -r '.user // "unnamed"')
        options+=("$((idx+1)). $user")
        idx=$((idx+1))
    done < <(echo "$passwords_json" | jq -c '.[]')
    options+=("Cancel")

    print_info "Select a password entry to REMOVE:"
    echo

    local selected
    selected=$(gum choose --height 15 "${options[@]}" 2>/dev/tty </dev/tty)

    if [ -z "$selected" ] || [ "$selected" = "Cancel" ]; then
        return
    fi

    # Extract index
    local selected_idx
    selected_idx=$(echo "$selected" | grep -o '^[0-9]*' | head -1)
    selected_idx=$((selected_idx - 1))

    local user_to_remove
    user_to_remove=$(echo "$passwords_json" | jq -r ".[$selected_idx].user // \"unnamed\"")

    echo
    print_warning "You are about to remove the password for user: $user_to_remove"
    print_warning "Any peers using these credentials will lose connection!"
    echo

    if ! gum confirm "Are you sure you want to remove this password?" 2>/dev/tty </dev/tty; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Create backup
    echo
    print_working "Creating automatic backup..."
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    fi

    # Update config
    print_working "Removing authorized password..."
    local temp_config="$WORK_DIR/cjdns_remove_auth.json"

    if jq --argjson idx "$selected_idx" 'del(.authorizedPasswords[$idx])' "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Authorized password removed!"
            prompt_restart_with_journal
        else
            print_error "Config validation failed - changes not applied"
        fi
    else
        print_error "Failed to remove authorized password"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Generate a new random authorized password
generate_authorized_password() {
    clear
    print_ascii_header
    print_header "Generate Random Password"
    echo

    print_info "This will create a new authorized password with a random secure password."
    echo

    local user
    print_bold "Enter a user/login name for the new peer:"
    user=$(gum input --placeholder "e.g., new-peer-node" --width 60 2>/dev/tty </dev/tty)

    if [ -z "$user" ]; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Generate secure random password
    local pass
    pass=$(head -c 48 /dev/urandom | base64 | tr -dc 'a-z0-9-' | head -c 28)

    echo
    echo "┌────────────────────────────────────────────────────────────────┐"
    printf "│ %-15s %-46s │\n" "User:" "$user"
    printf "│ %-15s %-46s │\n" "Password:" "$pass"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo

    if ! gum confirm "Add this authorized password?" 2>/dev/tty </dev/tty; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Create backup
    echo
    print_working "Creating automatic backup..."
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    fi

    # Add to config
    print_working "Adding authorized password..."
    local temp_config="$WORK_DIR/cjdns_gen_auth.json"
    local new_entry
    new_entry=$(jq -n --arg u "$user" --arg p "$pass" '{password: $p, user: $u}')

    if jq --argjson entry "$new_entry" '.authorizedPasswords += [$entry]' "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Authorized password added!"
            echo
            print_info "Share these credentials with the peer who wants to connect to you:"
            echo
            echo "  User: $user"
            echo "  Password: $pass"
            echo "  Public Key: $(jq -r '.publicKey' "$CJDNS_CONFIG")"
            prompt_restart_with_journal
        else
            print_error "Config validation failed - changes not applied"
        fi
    else
        print_error "Failed to add authorized password"
    fi

    echo
    read -p "Press Enter to continue..."
}

# ============================================================================
# ADMIN SETTINGS
# ============================================================================

# Edit admin settings (bind address and password)
edit_admin_settings() {
    clear
    print_ascii_header
    print_header "Admin Settings"
    echo

    # Get current values
    local current_bind current_pass
    current_bind=$(jq -r '.admin.bind // "127.0.0.1:11234"' "$CJDNS_CONFIG")
    current_pass=$(jq -r '.admin.password // "NONE"' "$CJDNS_CONFIG")

    print_info "The admin interface is used by cjdnstool and this Peer Yeeter to"
    print_info "communicate with the running cjdns daemon."
    echo

    print_bold "Current Settings:"
    echo
    echo "┌────────────────────────────────────────────────────────────────┐"
    printf "│ %-15s %-46s │\n" "Bind Address:" "$current_bind"
    printf "│ %-15s %-46s │\n" "Password:" "$current_pass"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo

    echo
    echo -e "${YELLOW}${BOLD}⚠  WARNING ⚠${NC}"
    echo -e "${YELLOW}If you change these settings, the Peer Yeeter will need to be${NC}"
    echo -e "${YELLOW}RESTARTED after cjdns restarts to reconnect with new credentials.${NC}"
    echo

    echo "Options:"
    echo
    echo "1) ✏️  Edit Bind Address"
    echo "2) 🔐 Edit Admin Password"
    echo
    echo "0) Back"
    echo

    local choice
    read -p "Enter choice: " choice < /dev/tty

    case "$choice" in
        1|2) ;;
        0) return ;;
        *) print_error "Invalid choice"; sleep 1; return ;;
    esac

    local new_bind="$current_bind"
    local new_pass="$current_pass"

    if [ "$choice" = "1" ]; then
        echo
        print_bold "Enter new bind address (IP:PORT):"
        print_info "Use 127.0.0.1 for local-only access, 0.0.0.0 for network access"
        new_bind=$(gum input --placeholder "e.g., 127.0.0.1:11234" --value "$current_bind" --width 60 2>/dev/tty </dev/tty)
        [ -z "$new_bind" ] && new_bind="$current_bind"
    fi

    if [ "$choice" = "2" ]; then
        echo
        print_bold "Enter new admin password:"
        print_info "Use 'NONE' for no password (local access only recommended)"
        new_pass=$(gum input --placeholder "Password or NONE" --value "$current_pass" --width 60 2>/dev/tty </dev/tty)
        [ -z "$new_pass" ] && new_pass="$current_pass"
    fi

    if [ "$new_bind" = "$current_bind" ] && [ "$new_pass" = "$current_pass" ]; then
        print_info "No changes made"
        sleep 1
        return
    fi

    echo
    echo "┌────────────────────────────────────────────────────────────────┐"
    printf "│ %-15s %-46s │\n" "New Bind:" "$new_bind"
    printf "│ %-15s %-46s │\n" "New Password:" "$new_pass"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo

    echo
    echo -e "${RED}${BOLD}⚠  IMPORTANT ⚠${NC}"
    echo -e "${YELLOW}After applying these changes and restarting cjdns:${NC}"
    echo -e "${YELLOW}  1. You MUST restart the Peer Yeeter${NC}"
    echo -e "${YELLOW}  2. cjdnstool commands will need the new credentials${NC}"
    echo

    if ! gum confirm "Apply these changes?" 2>/dev/tty </dev/tty; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Create backup
    echo
    print_working "Creating automatic backup..."
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    fi

    # Update config
    print_working "Updating admin settings..."
    local temp_config="$WORK_DIR/cjdns_admin.json"

    if jq --arg bind "$new_bind" --arg pass "$new_pass" \
        '.admin.bind = $bind | .admin.password = $pass' "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Admin settings updated!"
            echo
            print_warning "Remember: Restart Peer Yeeter after cjdns restarts!"
            prompt_restart_with_journal
        else
            print_error "Config validation failed - changes not applied"
        fi
    else
        print_error "Failed to update admin settings"
    fi

    echo
    read -p "Press Enter to continue..."
}

# ============================================================================
# IDENTITY MANAGEMENT (privateKey, publicKey, ipv6)
# ============================================================================

# Regenerate node identity
regenerate_identity() {
    clear
    print_ascii_header
    print_header "Regenerate Node Identity"
    echo

    # Get current identity
    local current_privkey current_pubkey current_ipv6
    current_privkey=$(jq -r '.privateKey // ""' "$CJDNS_CONFIG")
    current_pubkey=$(jq -r '.publicKey // ""' "$CJDNS_CONFIG")
    current_ipv6=$(jq -r '.ipv6 // ""' "$CJDNS_CONFIG")

    print_bold "Current Identity:"
    echo
    echo "┌──────────────────────────────────────────────────────────────────────────────┐"
    printf "│ %-12s %-64s │\n" "Private Key:" "${current_privkey:0:40}..."
    printf "│ %-12s %-64s │\n" "Public Key:" "$current_pubkey"
    printf "│ %-12s %-64s │\n" "IPv6:" "$current_ipv6"
    echo "└──────────────────────────────────────────────────────────────────────────────┘"
    echo
    echo
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║                           ⚠⚠⚠  DANGER ZONE  ⚠⚠⚠                              ║${NC}"
    echo -e "${RED}${BOLD}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}${BOLD}║  This operation will PERMANENTLY change your node's identity!                ║${NC}"
    echo -e "${RED}${BOLD}║                                                                              ║${NC}"
    echo -e "${RED}${BOLD}║  CONSEQUENCES:                                                               ║${NC}"
    echo -e "${RED}${BOLD}║                                                                              ║${NC}"
    echo -e "${RED}${BOLD}║  • Your FC address will CHANGE                                               ║${NC}"
    printf "${RED}${BOLD}║    Currently: %-63s║${NC}\n" "$current_ipv6"
    echo -e "${RED}${BOLD}║                                                                              ║${NC}"
    echo -e "${RED}${BOLD}║  • ALL peers who connect TO you will need your NEW credentials               ║${NC}"
    echo -e "${RED}${BOLD}║    (new publicKey)                                                            ║${NC}"
    echo -e "${RED}${BOLD}║                                                                              ║${NC}"
    echo -e "${RED}${BOLD}║  • If you advertise your FC address ANYWHERE, it must be updated:            ║${NC}"
    echo -e "${RED}${BOLD}║    - Bitcoin Core config (bitcoin.conf) - needs update AND restart           ║${NC}"
    echo -e "${RED}${BOLD}║    - Any DNS records pointing to your FC address                             ║${NC}"
    echo -e "${RED}${BOLD}║    - Any services bound to your current FC address                           ║${NC}"
    echo -e "${RED}${BOLD}║    - Any firewall rules referencing your FC address                          ║${NC}"
    echo -e "${RED}${BOLD}║    - Any documentation or shared credentials                                 ║${NC}"
    echo -e "${RED}${BOLD}║                                                                              ║${NC}"
    echo -e "${RED}${BOLD}║  THIS IS NOT FOR THE FAINT OF HEART!                                         ║${NC}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo

    print_warning "Type 'I UNDERSTAND' to proceed, or anything else to cancel:"
    echo
    local confirmation
    read -p "> " confirmation < /dev/tty

    if [ "$confirmation" != "I UNDERSTAND" ]; then
        print_info "Cancelled - identity not changed"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    echo
    print_working "Generating new identity using cjdroute --genconf..."

    # Generate new config to temp file
    local tmp_genconf="/tmp/cjdroute.new.$(date +%Y%m%d_%H%M%S).conf"
    if ! cjdroute --genconf > "$tmp_genconf" 2>/dev/null; then
        print_error "Failed to run cjdroute --genconf"
        rm -f "$tmp_genconf"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Extract new identity values (they have comments, so we need to strip those)
    # The genconf output has JSON with // comments, use a simple grep/sed approach
    local new_privkey new_pubkey new_ipv6

    # Parse the JSON with comments - extract the values
    new_privkey=$(grep '"privateKey"' "$tmp_genconf" | head -1 | sed 's/.*"privateKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    new_pubkey=$(grep '"publicKey"' "$tmp_genconf" | head -1 | sed 's/.*"publicKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    new_ipv6=$(grep '"ipv6"' "$tmp_genconf" | head -1 | sed 's/.*"ipv6"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    rm -f "$tmp_genconf"

    if [ -z "$new_privkey" ] || [ -z "$new_pubkey" ] || [ -z "$new_ipv6" ]; then
        print_error "Failed to parse new identity from cjdroute --genconf"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    echo
    print_success "New identity generated!"
    echo
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    printf "│ %-12s %-63s │\n" "Private Key:" "${new_privkey:0:40}..."
    printf "│ %-12s %-63s │\n" "Public Key:" "$new_pubkey"
    printf "│ %-12s %-63s │\n" "New IPv6:" "$new_ipv6"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo
    echo
    echo -e "${YELLOW}${BOLD}Identity Change Summary:${NC}"
    echo -e "${YELLOW}  Old IPv6: $current_ipv6${NC}"
    echo -e "${YELLOW}  New IPv6: $new_ipv6${NC}"
    echo
    echo -e "${RED}${BOLD}⚠  FINAL WARNING ⚠${NC}"
    echo -e "${RED}This change is IRREVERSIBLE without restoring from backup!${NC}"
    echo

    if ! gum confirm "Apply this new identity? (CANNOT BE UNDONE)" 2>/dev/tty </dev/tty; then
        print_info "Cancelled - identity not changed"
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
        echo
        print_info "IMPORTANT: Save this backup path to restore if needed:"
        echo "  $backup"
    else
        print_error "Backup FAILED!"
        if ! gum confirm "Continue WITHOUT backup? (VERY RISKY)" 2>/dev/tty </dev/tty; then
            print_info "Cancelled"
            echo
            read -p "Press Enter to continue..."
            return
        fi
    fi

    # Update config
    echo
    print_working "Updating node identity..."
    local temp_config="$WORK_DIR/cjdns_identity.json"

    if jq --arg pk "$new_privkey" --arg pubk "$new_pubkey" --arg ip "$new_ipv6" \
        '.privateKey = $pk | .publicKey = $pubk | .ipv6 = $ip' "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "Node identity updated!"
            echo
            echo -e "${YELLOW}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${YELLOW}${BOLD}  📋 NEXT STEPS - PLEASE READ CAREFULLY:${NC}"
            echo -e "${YELLOW}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
            echo
            echo "  1. Restart cjdns service"
            echo
            echo "  2. Update ALL peers who connect TO you with your new publicKey:"
            echo -e "     ${GREEN}$new_pubkey${NC}"
            echo
            echo "  3. Update Bitcoin Core (if using cjdns):"
            echo "     - Edit bitcoin.conf and update any FC addresses"
            echo -e "     - Your new FC address: ${GREEN}$new_ipv6${NC}"
            echo "     - Restart bitcoind"
            echo
            echo "  4. Update any other services using your old FC address"
            echo
            echo -e "${YELLOW}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
            prompt_restart_with_journal
        else
            print_error "Config validation failed - changes not applied"
        fi
    else
        print_error "Failed to update identity"
    fi

    echo
    read -p "Press Enter to continue..."
}

# ============================================================================
# INTERFACE BIND ADDRESSES
# ============================================================================

# Edit interface bind addresses
edit_interface_binds() {
    while true; do
        clear
        print_ascii_header
        print_header "Interface Bind Addresses"
        echo

        print_info "Configure which addresses/ports cjdns listens on for peer connections."
        echo

        # Get current binds
        local ipv4_bind ipv6_bind
        ipv4_bind=$(jq -r '.interfaces.UDPInterface[0].bind // "0.0.0.0:random"' "$CJDNS_CONFIG")
        ipv6_bind=$(jq -r '.interfaces.UDPInterface[1].bind // "[::]:random"' "$CJDNS_CONFIG")

        # Get beacon settings
        local ipv4_beacon ipv6_beacon
        ipv4_beacon=$(jq -r '.interfaces.UDPInterface[0].beacon // 0' "$CJDNS_CONFIG")
        ipv6_beacon=$(jq -r '.interfaces.UDPInterface[1].beacon // 0' "$CJDNS_CONFIG")

        local ipv4_beacon_port ipv6_beacon_port
        ipv4_beacon_port=$(jq -r '.interfaces.UDPInterface[0].beaconPort // 0' "$CJDNS_CONFIG")
        ipv6_beacon_port=$(jq -r '.interfaces.UDPInterface[1].beaconPort // 0' "$CJDNS_CONFIG")

        # Count peers in each interface
        local ipv4_peers ipv6_peers
        ipv4_peers=$(jq '.interfaces.UDPInterface[0].connectTo // {} | length' "$CJDNS_CONFIG")
        ipv6_peers=$(jq '.interfaces.UDPInterface[1].connectTo // {} | length' "$CJDNS_CONFIG")

        print_bold "Current Interface Configuration:"
        echo
        echo "┌─────────────────────────────────────────────────────────────────────────────┐"
        echo -e "│ ${CYAN}${BOLD}📡 IPv4 Interface (UDPInterface[0])${NC}                                       │"
        printf "│   %-15s %-57s │\n" "Bind:" "$ipv4_bind"
        printf "│   %-15s %-57s │\n" "Beacon:" "$ipv4_beacon (0=off, 1=listen, 2=broadcast)"
        printf "│   %-15s %-57s │\n" "Beacon Port:" "$ipv4_beacon_port"
        printf "│   %-15s %-57s │\n" "Peers:" "$ipv4_peers configured"
        echo "├─────────────────────────────────────────────────────────────────────────────┤"
        echo -e "│ ${ORANGE}${BOLD}📡 IPv6 Interface (UDPInterface[1])${NC}                                       │"
        printf "│   %-15s %-57s │\n" "Bind:" "$ipv6_bind"
        printf "│   %-15s %-57s │\n" "Beacon:" "${ipv6_beacon:-0} (0=off, 1=listen, 2=broadcast)"
        printf "│   %-15s %-57s │\n" "Beacon Port:" "${ipv6_beacon_port:-0}"
        printf "│   %-15s %-57s │\n" "Peers:" "$ipv6_peers configured"
        echo "└─────────────────────────────────────────────────────────────────────────────┘"
        echo

        echo "Options:"
        echo
        echo "1) 🌐 Edit IPv4 Bind Address"
        echo "2) 🌐 Edit IPv6 Bind Address"
        echo "3) 📢 Edit IPv4 Beacon Settings"
        echo "4) 📢 Edit IPv6 Beacon Settings"
        echo
        echo "0) Back"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty

        case "$choice" in
            1) edit_bind_address 0 "IPv4" "$ipv4_bind" ;;
            2) edit_bind_address 1 "IPv6" "$ipv6_bind" ;;
            3) edit_beacon_settings 0 "IPv4" "$ipv4_beacon" "$ipv4_beacon_port" ;;
            4) edit_beacon_settings 1 "IPv6" "$ipv6_beacon" "$ipv6_beacon_port" ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# Edit a specific bind address
edit_bind_address() {
    local interface_idx="$1"
    local label="$2"
    local current_bind="$3"

    clear
    print_ascii_header
    print_header "Edit $label Bind Address"
    echo

    print_bold "Current bind: $current_bind"
    echo

    if [ "$interface_idx" = "0" ]; then
        print_info "Format: IP:PORT  (e.g., 0.0.0.0:51820)"
        print_info "Use 0.0.0.0 to listen on all IPv4 interfaces"
    else
        print_info "Format: [IPv6]:PORT  (e.g., [::]:51820 or [2001:db8::1]:51820)"
        print_info "Use [::] to listen on all IPv6 interfaces"
    fi
    echo

    local new_bind
    new_bind=$(gum input --placeholder "Enter new bind address" --value "$current_bind" --width 60 2>/dev/tty </dev/tty)

    if [ -z "$new_bind" ] || [ "$new_bind" = "$current_bind" ]; then
        print_info "No changes made"
        sleep 1
        return
    fi

    echo
    print_warning "Changing the bind address may affect peer connectivity!"
    print_warning "Peers connecting to your old address:port will fail."
    echo

    if ! gum confirm "Apply this change?" 2>/dev/tty </dev/tty; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Create backup
    echo
    print_working "Creating automatic backup..."
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    fi

    # Update config
    print_working "Updating bind address..."
    local temp_config="$WORK_DIR/cjdns_bind.json"

    if jq --argjson idx "$interface_idx" --arg bind "$new_bind" \
        '.interfaces.UDPInterface[$idx].bind = $bind' "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "$label bind address updated to: $new_bind"
            prompt_restart_with_journal
        else
            print_error "Config validation failed - changes not applied"
        fi
    else
        print_error "Failed to update bind address"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Edit beacon settings for an interface
edit_beacon_settings() {
    local interface_idx="$1"
    local label="$2"
    local current_beacon="$3"
    local current_port="$4"

    clear
    print_ascii_header
    print_header "Edit $label Beacon Settings"
    echo

    print_info "Beacons allow automatic peer discovery on local networks."
    echo

    print_bold "Current settings:"
    echo "  Beacon mode: $current_beacon"
    echo "  Beacon port: $current_port"
    echo

    print_bold "Beacon modes:"
    echo "  0 = Disabled (no beacons)"
    echo "  1 = Listen only (accept beacons from others)"
    echo "  2 = Broadcast (send and accept beacons)"
    echo

    local new_beacon
    new_beacon=$(gum choose --height 6 "0 - Disabled" "1 - Listen only" "2 - Broadcast" "Cancel" 2>/dev/tty </dev/tty)

    if [ -z "$new_beacon" ] || [ "$new_beacon" = "Cancel" ]; then
        return
    fi

    new_beacon=$(echo "$new_beacon" | cut -d' ' -f1)

    local new_port="$current_port"
    if [ "$new_beacon" != "0" ]; then
        echo
        print_bold "Beacon port (default 64512):"
        new_port=$(gum input --placeholder "Beacon port (e.g., 64512)" --value "$current_port" --width 60 2>/dev/tty </dev/tty)
        [ -z "$new_port" ] && new_port="$current_port"
    fi

    if [ "$new_beacon" = "$current_beacon" ] && [ "$new_port" = "$current_port" ]; then
        print_info "No changes made"
        sleep 1
        return
    fi

    echo
    if ! gum confirm "Apply beacon settings?" 2>/dev/tty </dev/tty; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Create backup
    echo
    print_working "Creating automatic backup..."
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    fi

    # Update config
    print_working "Updating beacon settings..."
    local temp_config="$WORK_DIR/cjdns_beacon.json"

    if jq --argjson idx "$interface_idx" --argjson beacon "$new_beacon" --argjson port "$new_port" \
        '.interfaces.UDPInterface[$idx].beacon = $beacon | .interfaces.UDPInterface[$idx].beaconPort = $port' \
        "$CJDNS_CONFIG" > "$temp_config"; then
        if validate_config "$temp_config"; then
            cp "$temp_config" "$CJDNS_CONFIG"
            echo
            print_success "$label beacon settings updated!"
            prompt_restart_with_journal
        else
            print_error "Config validation failed - changes not applied"
        fi
    else
        print_error "Failed to update beacon settings"
    fi

    echo
    read -p "Press Enter to continue..."
}

# ============================================================================
# MAIN GUIDED CONFIG EDITOR MENU
# ============================================================================

# Main guided config editor menu
guided_config_editor() {
    while true; do
        clear
        print_ascii_header
        print_header "Guided Config Editor"
        echo

        echo "What would you like to do?"
        echo
        echo -e "${CYAN}${BOLD}Peer Management:${NC}"
        echo "1) ➕ Add New Peer"
        echo "2) ✏️  Edit Existing Peer"
        echo "3) 👁️  View All Peers"
        echo "4) 🌐 Configure Public Peering"
        echo
        echo -e "${CYAN}${BOLD}Credentials & Security:${NC}"
        echo "5) 🔑 Authorized Passwords (incoming connections)"
        echo "6) ⚙️  Admin Settings (cjdnstool connection)"
        echo -e "7) ${RED}☠️  Regenerate Identity (DANGER)${NC}"
        echo
        echo -e "${CYAN}${BOLD}Network Settings:${NC}"
        echo "8) 🔌 Interface Bind Addresses"
        echo
        echo "0) Back to Main Menu"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty

        case "$choice" in
            1) add_peer_guided ;;
            2) edit_peer_guided ;;
            3) view_all_peers ;;
            4) configure_public_peering ;;
            5) manage_authorized_passwords ;;
            6) edit_admin_settings ;;
            7) regenerate_identity ;;
            8) edit_interface_binds ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}
