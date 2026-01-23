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
        echo "2) ✏️  Edit Existing Peer"
        echo "3) 👁️  View All Peers"
        echo
        echo "0) Back to Main Menu"
        echo

        local choice
        read -p "Enter choice: " choice < /dev/tty

        case "$choice" in
            1) add_peer_guided ;;
            2) edit_peer_guided ;;
            3) view_all_peers ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}
