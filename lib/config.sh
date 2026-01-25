#!/usr/bin/env bash
# Config Module - Safe manipulation of cjdns config files

# Default backup directory (persistent, not /tmp)
BACKUP_DIR="/etc/cjdns_backups"

# Create backup of config file
backup_config() {
    local config_file="$1"
    local backup_dir="${2:-$BACKUP_DIR}"

    # Validate config before backing it up
    if ! validate_config "$config_file"; then
        print_warning "Config file has validation issues - backup may not be restorable"
        if ! ask_yes_no "Create backup anyway?"; then
            return 1
        fi
    fi

    # Create backup directory if it doesn't exist
    if ! mkdir -p "$backup_dir" 2>/dev/null; then
        print_error "Cannot create backup directory: $backup_dir"
        return 1
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/cjdroute_backup_$timestamp.conf"

    if cp "$config_file" "$backup_file"; then
        echo "$backup_file"
        return 0
    else
        return 1
    fi
}

# List all backups in backup directory
list_backups() {
    local backup_dir="${1:-$BACKUP_DIR}"

    if [ ! -d "$backup_dir" ]; then
        return 1
    fi

    find "$backup_dir" -name "cjdroute_backup_*.conf" -type f 2>/dev/null | sort -r
}

# Restore config from backup
restore_config() {
    local backup_file="$1"
    local config_file="$2"

    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi

    # Validate backup before restoring
    if ! validate_config "$backup_file"; then
        print_error "Backup file is not a valid config"
        return 1
    fi

    # Create a backup of current config before restoring
    local safety_backup
    if safety_backup=$(backup_config "$config_file" "$BACKUP_DIR/safety"); then
        print_info "Created safety backup: $safety_backup"
    fi

    if cp "$backup_file" "$config_file"; then
        return 0
    else
        return 1
    fi
}

# Validate JSON config file
validate_config() {
    local config_file="$1"

    # First check if it's valid JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        print_error "Config is not valid JSON" >&2
        return 1
    fi

    # Check for required top-level fields
    local required_fields=("interfaces" "router" "security")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$config_file" &>/dev/null; then
            print_error "Config missing required field: .$field" >&2
            return 1
        fi
    done

    # Check for UDPInterface
    if ! jq -e '.interfaces.UDPInterface' "$config_file" &>/dev/null; then
        print_error "Config missing .interfaces.UDPInterface" >&2
        return 1
    fi

    # Check if UDPInterface is an array
    if ! jq -e '.interfaces.UDPInterface | type == "array"' "$config_file" &>/dev/null; then
        print_error ".interfaces.UDPInterface must be an array" >&2
        return 1
    fi

    # Check for admin section
    if ! jq -e '.admin.bind' "$config_file" &>/dev/null; then
        print_error "Config missing .admin.bind" >&2
        return 1
    fi

    # Validate with cjdroute if available (using auto-detected binary)
    if [ -n "${CJDROUTE_BIN:-}" ] && [ -x "$CJDROUTE_BIN" ]; then
        echo -n "  Running cjdroute --check validation... " >&2

        # Run validation and capture both stdout and stderr
        local check_output
        local check_result
        check_output=$("$CJDROUTE_BIN" --check < "$config_file" 2>&1)
        check_result=$?

        if [ $check_result -ne 0 ]; then
            echo -e "${RED}✗${NC}" >&2
            echo >&2
            print_error "═══════════════════════════════════════════════════════════════" >&2
            print_error "  CRITICAL: cjdroute --check FAILED - config will NOT work!" >&2
            print_error "═══════════════════════════════════════════════════════════════" >&2
            echo >&2
            print_info "Validation command: $CJDROUTE_BIN --check" >&2
            print_info "Exit code: $check_result" >&2
            echo >&2
            print_error "Error output from cjdroute:" >&2
            echo "───────────────────────────────────────────────────────────────" >&2
            echo "$check_output" | head -30 >&2
            echo "───────────────────────────────────────────────────────────────" >&2
            echo >&2
            print_info "Your original config is safe and unchanged" >&2
            print_info "The changes were NOT applied to prevent breaking your cjdns installation" >&2
            return 1
        else
            echo -e "${GREEN}✓${NC}" >&2
            print_info "  Config validated successfully with cjdroute" >&2
        fi
    else
        print_warning "cjdroute binary not available - skipping native validation" >&2
        print_warning "Config structure checks passed, but may fail at runtime!" >&2
        print_info "To enable full validation, ensure cjdroute is in PATH or service file" >&2
    fi

    return 0
}

# Add peers to config file (writes ONLY required fields: password and publicKey)
add_peers_to_config() {
    local config_file="$1"
    local peers_json="$2"
    local interface_index="$3"
    local temp_config="$4"

    # Check if the interface exists
    if ! jq -e --argjson idx "$interface_index" '.interfaces.UDPInterface[$idx]' "$config_file" &>/dev/null; then
        print_error "Interface $interface_index does not exist in config" >&2
        return 1
    fi

    # First, ensure the interface has a connectTo field
    # If it doesn't exist, create it as an empty object
    jq --argjson idx "$interface_index" '
        if .interfaces.UDPInterface[$idx].connectTo == null then
            .interfaces.UDPInterface[$idx].connectTo = {}
        else
            .
        end
    ' "$config_file" > "$temp_config.tmp"

    # Strip peers to only password and publicKey, then merge into the interface
    # CJDNS only requires these two fields - extra metadata is unnecessary and can cause issues
    jq --slurpfile new_peers "$peers_json" --argjson idx "$interface_index" '
        .interfaces.UDPInterface[$idx].connectTo += (
            $new_peers[0] |
            to_entries |
            map({
                key: .key,
                value: {
                    password: .value.password,
                    publicKey: .value.publicKey
                }
            }) |
            from_entries
        )
    ' "$temp_config.tmp" > "$temp_config"

    rm -f "$temp_config.tmp"

    return $?
}

# Get peer count from config
get_peer_count() {
    local config_file="$1"
    local interface_index="$2"

    # Return 0 if connectTo doesn't exist or is null
    jq --argjson idx "$interface_index" \
        '.interfaces.UDPInterface[$idx].connectTo // {} | length' \
        "$config_file" 2>/dev/null || echo 0
}

# Remove peers from config by address
remove_peers_from_config() {
    local config_file="$1"
    local interface_index="$2"
    local temp_config="$3"
    shift 3
    local addresses=("$@")

    cp "$config_file" "$temp_config"

    for addr in "${addresses[@]}"; do
        jq --arg addr "$addr" \
            "del(.interfaces.UDPInterface[$interface_index].connectTo[\$addr])" \
            "$temp_config" > "$temp_config.tmp"
        mv "$temp_config.tmp" "$temp_config"
    done

    return 0
}

# Extract peers from config by state (requires cjdnstool connection)
get_peers_by_state() {
    local peer_states_file="$1"
    local state="$2"
    local output_file="$3"

    grep "^$state|" "$peer_states_file" | cut -d'|' -f2 > "$output_file"

    return 0
}

# Show peer details from JSON file
show_peer_details() {
    local peers_json="$1"
    local max_count="${2:-5}"

    local total=$(jq 'length' "$peers_json")

    if [ "$total" -eq 0 ]; then
        echo "No peers found"
        return
    fi

    # Smart display message
    if [ "$max_count" -ge "$total" ]; then
        echo "Found $total peers:"
    else
        echo "Showing first $max_count of $total peers:"
    fi
    echo

    jq -r --argjson max "$max_count" '
        to_entries[:$max][] |
        "Address:    \(.key)",
        "PublicKey:  \(.value.publicKey)",
        "Password:   \(.value.password)",
        (if .value.peerName then "PeerName:   \(.value.peerName)" else empty end),
        (if .value.contact then "Contact:    \(.value.contact)" else empty end),
        (if .value.login then "Login:      \(.value.login)" else empty end),
        (if .value.location then "Location:   \(.value.location)" else empty end),
        (if .value.gpg then "GPG:        \(.value.gpg)" else empty end),
        ""
    ' "$peers_json"

    if [ "$total" -gt "$max_count" ]; then
        echo "... and $((total - max_count)) more peers"
    fi
}
