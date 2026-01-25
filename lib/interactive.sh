#!/usr/bin/env bash
# Interactive Module - Gum-based interactive menus

# Interactive Peer Management (combines Remove + Status with gum)
interactive_peer_management() {
    clear
    print_ascii_header
    print_header "View Status & Remove Peers"

    print_bold "Loading peer data from config and cjdns..."
    echo

    # Get current peer states
    local peer_states="$WORK_DIR/peer_states.txt"
    get_current_peer_states "$ADMIN_IP" "$ADMIN_PORT" "$ADMIN_PASSWORD" "$peer_states"

    # Update database with current states
    while IFS='|' read -r state address; do
        update_peer_state "$address" "$state"
    done < "$peer_states"

    # Get all peers from config
    declare -a all_config_peers
    # IPv4 peers
    while IFS= read -r addr; do
        [ -n "$addr" ] && all_config_peers+=("$addr")
    done < <(jq -r '.interfaces.UDPInterface[0].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null)

    # IPv6 peers
    while IFS= read -r addr; do
        [ -n "$addr" ] && all_config_peers+=("$addr")
    done < <(jq -r '.interfaces.UDPInterface[1].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null)

    if [ ${#all_config_peers[@]} -eq 0 ]; then
        print_warning "No peers found in config"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Build arrays for gum display
    declare -a peer_options
    declare -a peer_addresses
    declare -a unresponsive_indices  # Track which indices are unresponsive
    local all_peers=$(get_all_peers_by_quality)

    # Add peers from database (with quality info)
    local idx=0
    while IFS='|' read -r address state quality est_count unr_count first_seen last_change consecutive; do
        [ -z "$address" ] && continue

        local quality_display=$(printf "%.0f%%" "$quality")
        local time_in_state=$(time_since "$last_change")
        local status_icon

        if [ "$state" = "ESTABLISHED" ]; then
            status_icon="✓"
            peer_options+=("$status_icon $address | Q:$quality_display Est:$est_count Unr:$unr_count | Established $time_in_state")
        elif [ "$state" = "UNRESPONSIVE" ]; then
            status_icon="✗"
            peer_options+=("$status_icon $address | Q:$quality_display Est:$est_count Unr:$unr_count | Unresponsive $time_in_state (${consecutive}x)")
            unresponsive_indices+=("$idx")
        else
            status_icon="?"
            peer_options+=("$status_icon $address | Q:$quality_display Est:$est_count Unr:$unr_count | $state $time_in_state")
        fi

        peer_addresses+=("$address")
        idx=$((idx + 1))
    done <<< "$all_peers"

    # Add peers from config not yet in database
    for config_addr in "${all_config_peers[@]}"; do
        local already_added=false
        local normalized_config=$(normalize_ipv6_address "$config_addr")
        for addr in "${peer_addresses[@]}"; do
            local normalized_addr=$(normalize_ipv6_address "$addr")
            if [ "$normalized_config" = "$normalized_addr" ]; then
                already_added=true
                break
            fi
        done

        if [ "$already_added" = false ]; then
            peer_options+=("○ $config_addr | Awaiting first check")
            peer_addresses+=("$config_addr")
        fi
    done

    # Check if we have any options
    if [ ${#peer_options[@]} -eq 0 ]; then
        print_error "No peers found to display"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Calculate height - show all peers plus some padding (max 50 to avoid terminal issues)
    local gum_height=${#peer_options[@]}
    [ $gum_height -gt 50 ] && gum_height=50
    [ $gum_height -lt 10 ] && gum_height=10

    # Use gum to select peers
    print_success "Found ${#peer_addresses[@]} peers in config (${#unresponsive_indices[@]} unresponsive)"
    echo

    local selected=""
    local gum_exit=0
    local preselect_unresponsive=false

    # If there are unresponsive peers, offer to pre-select them
    if [ ${#unresponsive_indices[@]} -gt 0 ]; then
        print_info "Pre-select all ${#unresponsive_indices[@]} unresponsive peers? (you can deselect any to keep)"
        if gum confirm "Pre-select unresponsive?" </dev/tty 2>/dev/tty; then
            preselect_unresponsive=true
        fi
        echo
    fi

    while true; do
        print_info "Use SPACE to select/deselect peers, then ENTER to confirm"
        print_info "Press ESC to cancel and return to menu"
        echo

        # Build gum command with optional pre-selection
        if [ "$preselect_unresponsive" = true ]; then
            # Build comma-separated list of unresponsive peer options for --selected
            local preselected=""
            for i in "${unresponsive_indices[@]}"; do
                [ -n "$preselected" ] && preselected="$preselected,"
                preselected="$preselected${peer_options[$i]}"
            done
            if selected=$(gum choose --no-limit --height "$gum_height" --selected "$preselected" "${peer_options[@]}" </dev/tty 2>/dev/tty); then
                gum_exit=0
            else
                gum_exit=$?
            fi
            # Only pre-select on first loop iteration
            preselect_unresponsive=false
        else
            if selected=$(gum choose --no-limit --height "$gum_height" "${peer_options[@]}" </dev/tty 2>/dev/tty); then
                gum_exit=0
            else
                gum_exit=$?
            fi
        fi

        # ESC pressed - return to menu
        if [ $gum_exit -ne 0 ]; then
            print_info "Cancelled - returning to menu"
            echo
            read -p "Press Enter to continue..."
            return
        fi

        # Check if anything was selected
        if [ -z "$selected" ]; then
            echo
            print_warning "No peers selected!"
            print_info "Use SPACE to select peers first, then press ENTER"
            echo
            read -p "Press Enter to try again..."
            clear
            print_ascii_header
            print_header "View Status & Remove Peers"
            echo
            print_success "Found ${#peer_addresses[@]} peers in config (${#unresponsive_indices[@]} unresponsive)"
            echo
            continue
        fi

        # Something was selected, break out of loop
        break
    done

    # Parse selected peers
    declare -a selected_addresses
    while IFS= read -r line; do
        # Extract address from the display string (between icon and first |)
        local addr=$(echo "$line" | sed -E 's/^[✓✗?○] ([^ ]+) \|.*/\1/')
        selected_addresses+=("$addr")
    done <<< "$selected"

    # Check if any peers were selected
    local num_selected=${#selected_addresses[@]}
    if [ ${num_selected:-0} -eq 0 ]; then
        echo
        print_error "No peers matched selection"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Show confirmation
    echo
    print_warning "The following ${#selected_addresses[@]} peer(s) will be PERMANENTLY REMOVED:"
    for addr in "${selected_addresses[@]}"; do
        echo "  - $addr"
    done

    echo
    if ! gum confirm "Are you SURE you want to remove these peers?" </dev/tty >/dev/tty; then
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Auto-backup before removal
    echo
    print_working "Creating automatic backup before removal..."
    local backup
    if backup=$(backup_config "$CJDNS_CONFIG"); then
        print_success "Backup created: $backup"
    else
        print_error "Failed to create backup"
        if ! gum confirm "Continue without backup?" </dev/tty >/dev/tty; then
            return
        fi
    fi

    # Remove peers from config
    echo
    print_working "Removing peers from config..."

    local temp_config="$WORK_DIR/config.tmp"
    cp "$CJDNS_CONFIG" "$temp_config"

    # Count removals by interface
    local ipv4_removed=0
    local ipv6_removed=0

    for addr in "${selected_addresses[@]}"; do
        # Determine if IPv4 or IPv6
        if [[ "$addr" =~ ^\[ ]]; then
            # IPv6
            jq --arg addr "$addr" 'del(.interfaces.UDPInterface[1].connectTo[$addr])' "$temp_config" > "$temp_config.tmp"
            mv "$temp_config.tmp" "$temp_config"
            ipv6_removed=$((ipv6_removed + 1))
        else
            # IPv4
            jq --arg addr "$addr" 'del(.interfaces.UDPInterface[0].connectTo[$addr])' "$temp_config" > "$temp_config.tmp"
            mv "$temp_config.tmp" "$temp_config"
            ipv4_removed=$((ipv4_removed + 1))
        fi

        # Remove from database
        sqlite3 "$DB_FILE" "DELETE FROM peers WHERE address='$addr';"
    done

    # Validate temp config
    if validate_config "$temp_config"; then
        cp "$temp_config" "$CJDNS_CONFIG"
        echo
        print_success "Removed $ipv4_removed IPv4 and $ipv6_removed IPv6 peer(s)"

        echo
        if gum confirm "Restart cjdns service now?" </dev/tty >/dev/tty; then
            restart_service
        fi
    else
        print_error "Config validation failed - changes not applied"
    fi

    echo
    read -p "Press Enter to continue..."
}

# Interactive file deletion (backups, exports, databases)
interactive_file_deletion() {
    local file_type="$1"  # "backup", "export", or "database"
    local title
    local file_pattern
    local search_dir

    case "$file_type" in
        backup)
            title="Delete Config Backups"
            file_pattern="cjdroute_backup_*.conf"
            search_dir="$BACKUP_DIR"
            ;;
        export)
            title="Delete Exported Peer Files"
            file_pattern="*.json"
            search_dir="$BACKUP_DIR/exported_peers"
            ;;
        database)
            title="Manage Database Backups"
            file_pattern="peer_tracking_backup_*.db"
            search_dir="$BACKUP_DIR/database_backups"
            ;;
        *)
            print_error "Invalid file type: $file_type"
            return 1
            ;;
    esac

    clear
    print_ascii_header
    print_header "$title"

    # Find files
    local files
    mapfile -t files < <(find "$search_dir" -name "$file_pattern" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [ ${#files[@]} -eq 0 ]; then
        print_warning "No $file_type files found in $search_dir"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Build options for gum
    declare -a file_options
    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        local size=$(ls -lh "$file" | awk '{print $5}')
        local date=$(stat -c %y "$file" | cut -d' ' -f1)
        file_options+=("$filename | $size | $date")
    done

    print_success "Found ${#files[@]} file(s)"
    echo
    print_info "Use arrow keys to navigate, Space to select/deselect, Enter to confirm"
    print_info "Press ESC to cancel"
    echo

    local selected=""
    local gum_exit=0
    # Handle ESC/cancellation gracefully
    if selected=$(gum choose --no-limit --height 20 "${file_options[@]}" </dev/tty >/dev/tty 2>&1); then
        gum_exit=0
    else
        gum_exit=$?
    fi

    # Check if user cancelled (ESC key) or no selection
    if [ $gum_exit -ne 0 ] || [ -z "$selected" ]; then
        print_info "Cancelled or no files selected"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Parse selected files
    declare -a selected_files
    while IFS= read -r line; do
        local filename=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')
        for file in "${files[@]}"; do
            if [[ "$(basename "$file")" == "$filename" ]]; then
                selected_files+=("$file")
                break
            fi
        done
    done <<< "$selected"

    # Check if any files were matched
    local num_files=${#selected_files[@]}
    if [ ${num_files:-0} -eq 0 ]; then
        echo
        print_error "No files matched selection"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Confirm deletion
    echo
    print_warning "The following ${#selected_files[@]} file(s) will be PERMANENTLY DELETED:"
    for file in "${selected_files[@]}"; do
        echo "  - $(basename "$file") ($(ls -lh "$file" | awk '{print $5}'))"
    done

    echo
    if ! gum confirm "Are you SURE you want to delete these files?" </dev/tty >/dev/tty; then
        print_info "Cancelled"
        echo
        read -p "Press Enter to continue..."
        return
    fi

    # Delete files
    echo
    print_working "Deleting files..."
    local deleted=0
    for file in "${selected_files[@]}"; do
        if rm -f "$file" 2>/dev/null; then
            deleted=$((deleted + 1))
        else
            print_warning "Failed to delete: $(basename "$file")"
        fi
    done

    echo
    print_success "Deleted $deleted file(s)"
    echo
    read -p "Press Enter to continue..."
}

# Interactive settings editor
interactive_settings_editor() {
    while true; do
        clear
        print_ascii_header
        print_header "Settings Editor"

        echo "Current Settings:"
        echo "  • Config File: $CJDNS_CONFIG"
        echo "  • Service: ${CJDNS_SERVICE:-Disabled}"
        echo "  • Backup Directory: $BACKUP_DIR"
        echo
        print_info "Use arrow keys to navigate, Enter to select, ESC to cancel"
        echo

        local choice
        choice=$(gum choose --height 10 \
            "Change Config File Location" \
            "Change Service Name" \
            "Change Backup Directory (with migration)" \
            "Back to Main Menu" 2>&1)
        local gum_exit=$?

        # Check if user cancelled (ESC key)
        if [ $gum_exit -ne 0 ] || [ -z "$choice" ]; then
            return
        fi

        case "$choice" in
            "Change Config File Location")
                change_config_location
                ;;
            "Change Service Name")
                change_service_name
                ;;
            "Change Backup Directory (with migration)")
                change_backup_directory
                ;;
            "Back to Main Menu")
                return
                ;;
        esac
    done
}

# Change config file location
change_config_location() {
    clear
    print_ascii_header
    print_subheader "Change Config File Location"

    echo "Current config: $CJDNS_CONFIG"
    echo

    # Show available configs
    local configs
    mapfile -t configs < <(list_cjdns_configs)

    if [ ${#configs[@]} -gt 0 ]; then
        print_info "Found these config files:"
        for cfg in "${configs[@]}"; do
            echo "  - $cfg"
        done
        echo
    fi

    local new_config
    new_config=$(gum input --placeholder "Enter new config file path (or press Ctrl+C to cancel)" --width 80) </dev/tty >/dev/tty

    if [ -z "$new_config" ]; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    if [ ! -f "$new_config" ]; then
        print_error "File not found: $new_config"
        sleep 2
        return
    fi

    if ! validate_config "$new_config"; then
        print_error "Invalid config file"
        sleep 2
        return
    fi

    CJDNS_CONFIG="$new_config"
    print_success "Config file updated to: $CJDNS_CONFIG"
    echo
    print_info "Note: This change only affects the current session"
    print_info "The tool will use auto-detection on next run"
    sleep 3
}

# Change service name
change_service_name() {
    clear
    print_ascii_header
    print_subheader "Change Service Name"

    echo "Current service: ${CJDNS_SERVICE:-Not set}"
    echo

    local new_service
    new_service=$(gum input --placeholder "Enter service name (e.g., cjdns.service) or press Ctrl+C to cancel" --width 80) </dev/tty >/dev/tty

    if [ -z "$new_service" ]; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Validate service exists
    if systemctl list-unit-files "$new_service" &>/dev/null; then
        CJDNS_SERVICE="$new_service"
        print_success "Service name updated to: $CJDNS_SERVICE"
    else
        print_warning "Service '$new_service' not found on system"
        echo
        if gum confirm "Set it anyway? (service management may not work)" </dev/tty >/dev/tty; then
            CJDNS_SERVICE="$new_service"
            print_success "Service name updated (unvalidated)"
        else
            print_info "Cancelled"
        fi
    fi
    sleep 2
}

# Change backup directory with migration
change_backup_directory() {
    clear
    print_ascii_header
    print_subheader "Change Backup Directory"

    echo "Current directory: $BACKUP_DIR"
    echo

    print_warning "This will move ALL files to the new location:"
    echo "  • Config backups"
    echo "  • Exported peer files"
    echo "  • Database files"
    echo "  • Peer source lists"
    echo

    local new_dir
    new_dir=$(gum input --placeholder "Enter new backup directory path (or press Ctrl+C to cancel)" --width 80) </dev/tty >/dev/tty

    if [ -z "$new_dir" ]; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    if [ "$new_dir" = "$BACKUP_DIR" ]; then
        print_warning "Same as current directory"
        sleep 2
        return
    fi

    # Confirm migration
    echo
    if ! gum confirm "Migrate all files from $BACKUP_DIR to $new_dir?" </dev/tty >/dev/tty; then
        print_info "Cancelled"
        sleep 1
        return
    fi

    # Create new directory
    if ! mkdir -p "$new_dir" 2>/dev/null; then
        print_error "Failed to create directory: $new_dir"
        sleep 2
        return
    fi

    # Move files
    echo
    print_working "Migrating files..."

    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        if rsync -a "$BACKUP_DIR/" "$new_dir/" 2>/dev/null; then
            print_complete "Files migrated successfully" "success"

            # Update directory variable
            BACKUP_DIR="$new_dir"

            # Offer to remove old directory
            echo
            if gum confirm "Remove old backup directory?" </dev/tty >/dev/tty; then
                rm -rf "${BACKUP_DIR%/}"
                print_success "Old directory removed"
            fi
        else
            print_complete "Migration failed" "failed"
            sleep 2
            return
        fi
    else
        BACKUP_DIR="$new_dir"
        print_info "No existing files to migrate"
    fi

    echo
    print_success "Backup directory updated to: $BACKUP_DIR"
    print_info "Note: This change only affects the current session"
    sleep 3
}

# Interactive peer sources management
interactive_peer_sources() {
    while true; do
        clear
        print_ascii_header
        print_header "Peer Sources Management"

        # Load sources
        local sources_json=$(jq -c '.sources[]' "$PEER_SOURCES" 2>/dev/null)

        declare -a source_options
        declare -a source_data
        local index=0

        while IFS= read -r source; do
            [ -z "$source" ] && continue
            local name=$(echo "$source" | jq -r '.name')
            local enabled=$(echo "$source" | jq -r '.enabled')
            local type=$(echo "$source" | jq -r '.type')
            local url=$(echo "$source" | jq -r '.url')

            local status_icon="✓"
            [ "$enabled" = "false" ] && status_icon="✗"

            source_options+=("$status_icon $name ($type)")
            source_data+=("$source")
            index=$((index + 1))
        done <<< "$sources_json"

        print_info "Current peer sources (${#source_options[@]} total):"
        echo

        # Show current sources
        if [ ${#source_options[@]} -gt 0 ]; then
            for opt in "${source_options[@]}"; do
                echo "  $opt"
            done
        else
            print_warning "No peer sources configured yet"
        fi
        echo
        print_info "Use arrow keys to navigate, Enter to select, ESC to cancel"
        echo

        local action
        action=$(gum choose --height 10 \
            "Toggle Source On/Off" \
            "Add New Source" \
            "Remove Source" \
            "Back to Main Menu" 2>&1)
        local gum_exit=$?

        # Check if user cancelled (ESC key)
        if [ $gum_exit -ne 0 ] || [ -z "$action" ]; then
            return
        fi

        case "$action" in
            "Toggle Source On/Off")
                toggle_peer_source "${source_options[@]}"
                ;;
            "Add New Source")
                add_peer_source
                ;;
            "Remove Source")
                remove_peer_source "${source_options[@]}"
                ;;
            "Back to Main Menu")
                return
                ;;
        esac
    done
}

# Toggle peer source on/off
toggle_peer_source() {
    local sources=("$@")

    if [ ${#sources[@]} -eq 0 ]; then
        print_warning "No sources available"
        sleep 2
        return
    fi

    clear
    print_ascii_header
    print_subheader "Toggle Source On/Off"
    echo
    print_info "Use arrow keys to navigate, Enter to select, ESC to cancel"
    echo

    local selected
    selected=$(gum choose --height 15 "${sources[@]}" </dev/tty >/dev/tty 2>&1)
    local gum_exit=$?

    if [ $gum_exit -ne 0 ] || [ -z "$selected" ]; then
        return
    fi

    # Extract source name
    local name=$(echo "$selected" | sed -E 's/^[✓✗] ([^ ]+) .*/\1/')

    # Toggle in JSON
    local current_state=$(jq -r ".sources[] | select(.name==\"$name\") | .enabled" "$PEER_SOURCES")
    local new_state="true"
    [ "$current_state" = "true" ] && new_state="false"

    jq ".sources |= map(if .name==\"$name\" then .enabled=$new_state else . end)" "$PEER_SOURCES" > "$PEER_SOURCES.tmp"
    mv "$PEER_SOURCES.tmp" "$PEER_SOURCES"

    echo
    print_success "Toggled $name to: $new_state"
    sleep 1
}

# Add peer source
add_peer_source() {
    clear
    print_ascii_header
    print_subheader "Add New Peer Source"
    echo
    print_info "Press Ctrl+C to cancel at any time"
    echo

    local name
    name=$(gum input --placeholder "Source name (e.g., my-peers)" --width 80) </dev/tty >/dev/tty
    [ -z "$name" ] && return

    echo
    print_info "Use arrow keys to navigate, Enter to select, ESC to cancel"
    echo

    local type
    type=$(gum choose --height 6 "github" "json" </dev/tty >/dev/tty 2>&1)
    local gum_exit=$?
    [ $gum_exit -ne 0 ] || [ -z "$type" ] && return

    echo
    local url
    if [ "$type" = "github" ]; then
        url=$(gum input --placeholder "GitHub repo URL (e.g., https://github.com/user/repo.git)" --width 80) </dev/tty >/dev/tty
    else
        url=$(gum input --placeholder "JSON file URL" --width 80) </dev/tty >/dev/tty
    fi
    [ -z "$url" ] && return

    # Add to sources
    jq ".sources += [{\"name\": \"$name\", \"type\": \"$type\", \"url\": \"$url\", \"enabled\": true}]" "$PEER_SOURCES" > "$PEER_SOURCES.tmp"
    mv "$PEER_SOURCES.tmp" "$PEER_SOURCES"

    echo
    print_success "Added source: $name"
    sleep 1
}

# Remove peer source
remove_peer_source() {
    local sources=("$@")

    if [ ${#sources[@]} -eq 0 ]; then
        print_warning "No sources available"
        sleep 2
        return
    fi

    clear
    print_ascii_header
    print_subheader "Remove Peer Source"
    echo
    print_warning "WARNING: This will permanently remove the source from your configuration"
    echo
    print_info "Use arrow keys to navigate, Enter to select, ESC to cancel"
    echo

    local selected
    selected=$(gum choose --height 15 "${sources[@]}" </dev/tty >/dev/tty 2>&1)
    local gum_exit=$?

    if [ $gum_exit -ne 0 ] || [ -z "$selected" ]; then
        return
    fi

    local name=$(echo "$selected" | sed -E 's/^[✓✗] ([^ ]+) .*/\1/')

    echo
    if gum confirm "Remove source: $name?" </dev/tty >/dev/tty; then
        jq ".sources |= map(select(.name!=\"$name\"))" "$PEER_SOURCES" > "$PEER_SOURCES.tmp"
        mv "$PEER_SOURCES.tmp" "$PEER_SOURCES"
        echo
        print_success "Removed source: $name"
        sleep 1
    fi
}
