#!/usr/bin/env bash
# Guided Config Editor - Interactive form-based peer editor

# Add a new peer with interactive form editor
add_peer_guided() {
    clear
    print_ascii_header
    print_header "Add New Peer - Interactive Form Editor"
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
    local ip_example
    if [ "$peer_type" = "IPv4 Peer" ]; then
        interface_index=0
        ip_example="192.168.1.1"
    else
        interface_index=1
        ip_example="2001:db8::1"
    fi

    # Step 2: Required fields using gum form
    clear
    print_ascii_header
    print_header "Add New Peer - Required Fields"
    echo
    print_bold "Step 2: Enter Peer Information"
    echo
    print_info "Fill in all required fields. Use Tab to move between fields, Enter to submit."
    echo

    # Create temporary file for form data
    local form_file="$WORK_DIR/peer_form_$$.txt"

    # Use gum form to get required fields all at once
    gum form \
        --title="Peer Information (Required Fields)" \
        "IP Address" "$ip_example" \
        "Port" "51820" \
        "Password" "" \
        "Public Key" "" \
        "Login (optional)" "" \
        2>/dev/tty </dev/tty > "$form_file"

    local form_exit=$?
    if [ $form_exit -ne 0 ] || [ ! -s "$form_file" ]; then
        rm -f "$form_file"
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Parse form results
    local ip_addr port password pubkey login
    {
        read -r ip_addr
        read -r port
        read -r password
        read -r pubkey
        read -r login
    } < "$form_file"
    rm -f "$form_file"

    # Validate required fields
    if [ -z "$ip_addr" ] || [ -z "$port" ] || [ -z "$password" ] || [ -z "$pubkey" ]; then
        print_error "Missing required fields (IP, Port, Password, or Public Key)"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Wrap IPv6 in brackets if needed
    if [ "$peer_type" = "IPv6 Peer" ] && [[ ! "$ip_addr" =~ ^\[ ]]; then
        ip_addr="[$ip_addr]"
    fi

    # Build full address
    local full_address="${ip_addr}:${port}"

    # Step 3: Optional fields using gum form
    clear
    print_ascii_header
    print_header "Add New Peer - Optional Fields"
    echo
    print_bold "Step 3: Additional Optional Fields"
    echo
    print_info "Add optional metadata fields (peerName, contact, location, gpg, etc.)"
    print_info "Leave blank to skip. Use Tab to move between fields, Enter to submit."
    echo

    declare -A custom_fields

    if gum confirm "Add optional metadata fields (peerName, contact, location, gpg)?" 2>/dev/tty </dev/tty; then
        local opt_form="$WORK_DIR/peer_opt_$$.txt"

        gum form \
            --title="Optional Metadata Fields" \
            "Peer Name" "" \
            "Contact" "" \
            "Location" "" \
            "GPG" "" \
            2>/dev/tty </dev/tty > "$opt_form"

        if [ -s "$opt_form" ]; then
            local peerName contact location gpg
            {
                read -r peerName
                read -r contact
                read -r location
                read -r gpg
            } < "$opt_form"

            [ -n "$peerName" ] && custom_fields["peerName"]="$peerName"
            [ -n "$contact" ] && custom_fields["contact"]="$contact"
            [ -n "$location" ] && custom_fields["location"]="$location"
            [ -n "$gpg" ] && custom_fields["gpg"]="$gpg"
        fi
        rm -f "$opt_form"
    fi

    # Step 4: Custom additional fields
    while true; do
        clear
        print_ascii_header
        print_header "Add New Peer - Custom Fields"
        echo
        print_bold "Step 4: Add Custom Fields"
        echo

        echo "Current peer configuration:"
        echo "  Address:    $full_address"
        echo "  Password:   ${password:0:20}..."
        echo "  Public Key: ${pubkey:0:20}..."
        [ -n "$login" ] && echo "  Login:      $login"

        # Show existing custom fields
        if [ ${#custom_fields[@]} -gt 0 ]; then
            echo
            echo "Optional fields added:"
            for field_name in "${!custom_fields[@]}"; do
                echo "  $field_name: ${custom_fields[$field_name]}"
            done
        fi

        echo
        if ! gum confirm "Add another custom field?" 2>/dev/tty </dev/tty; then
            break
        fi

        # Get custom field using form
        local custom_form="$WORK_DIR/peer_custom_$$.txt"
        gum form \
            --title="Add Custom Field" \
            "Field Name" "" \
            "Field Value" "" \
            2>/dev/tty </dev/tty > "$custom_form"

        if [ -s "$custom_form" ]; then
            local field_name field_value
            {
                read -r field_name
                read -r field_value
            } < "$custom_form"

            if [ -n "$field_name" ] && [ -n "$field_value" ]; then
                custom_fields["$field_name"]="$field_value"
            fi
        fi
        rm -f "$custom_form"
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

    # Extract current values
    local password=$(echo "$peer_data" | jq -r '.password // ""')
    local pubkey=$(echo "$peer_data" | jq -r '.publicKey // ""')
    local login=$(echo "$peer_data" | jq -r '.login // ""')
    local peerName=$(echo "$peer_data" | jq -r '.peerName // ""')
    local contact=$(echo "$peer_data" | jq -r '.contact // ""')
    local location=$(echo "$peer_data" | jq -r '.location // ""')
    local gpg=$(echo "$peer_data" | jq -r '.gpg // ""')

    # Show edit form
    clear
    print_ascii_header
    print_header "Edit Peer: $peer_addr"
    echo
    print_info "Modify the fields below. Use Tab to navigate, Enter to save."
    echo

    local form_file="$WORK_DIR/edit_peer_$$.txt"

    gum form \
        --title="Edit Peer Information" \
        "Password" "$password" \
        "Public Key" "$pubkey" \
        "Login" "$login" \
        "Peer Name" "$peerName" \
        "Contact" "$contact" \
        "Location" "$location" \
        "GPG" "$gpg" \
        2>/dev/tty </dev/tty > "$form_file"

    if [ ! -s "$form_file" ]; then
        rm -f "$form_file"
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Parse form results
    local new_password new_pubkey new_login new_peerName new_contact new_location new_gpg
    {
        read -r new_password
        read -r new_pubkey
        read -r new_login
        read -r new_peerName
        read -r new_contact
        read -r new_location
        read -r new_gpg
    } < "$form_file"
    rm -f "$form_file"

    # Validate required fields
    if [ -z "$new_password" ] || [ -z "$new_pubkey" ]; then
        print_error "Password and Public Key are required"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Build new peer JSON
    local new_peer_json
    new_peer_json=$(jq -n \
        --arg pw "$new_password" \
        --arg pk "$new_pubkey" \
        '{password: $pw, publicKey: $pk}')

    [ -n "$new_login" ] && new_peer_json=$(echo "$new_peer_json" | jq --arg v "$new_login" '. + {login: $v}')
    [ -n "$new_peerName" ] && new_peer_json=$(echo "$new_peer_json" | jq --arg v "$new_peerName" '. + {peerName: $v}')
    [ -n "$new_contact" ] && new_peer_json=$(echo "$new_peer_json" | jq --arg v "$new_contact" '. + {contact: $v}')
    [ -n "$new_location" ] && new_peer_json=$(echo "$new_peer_json" | jq --arg v "$new_location" '. + {location: $v}')
    [ -n "$new_gpg" ] && new_peer_json=$(echo "$new_peer_json" | jq --arg v "$new_gpg" '. + {gpg: $v}')

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
        read -p "Enter choice: " choice

        case "$choice" in
            1) add_peer_guided ;;
            2) edit_peer_guided ;;
            3) view_all_peers ;;
            0) return ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}
