#!/usr/bin/env bash
# Peers Module - Discovery, parsing, and testing of CJDNS peers

# Discover peers from GitHub repositories
discover_peers_from_github() {
    local temp_dir="$1"
    local output_ipv4="$2"
    local output_ipv6="$3"

    local repos=(
        "https://github.com/hyperboria/peers.git"
        "https://github.com/yangm97/peers.git"
        "https://github.com/cwinfo/hyperboria-peers.git"
    )

    echo "{}" > "$output_ipv4"
    echo "{}" > "$output_ipv6"

    local total_ipv4=0
    local total_ipv6=0

    for repo_url in "${repos[@]}"; do
        local repo_name=$(basename "$repo_url" .git)
        local repo_dir="$temp_dir/$repo_name"

        print_info "Fetching $repo_name..."

        if ! timeout 30 git clone --depth 1 --quiet "$repo_url" "$repo_dir" 2>/dev/null; then
            print_warning "Failed to clone $repo_url (repo may be down or unreachable)"
            continue
        fi

        cd "$repo_dir" || continue

        # Find all .k files
        local k_files
        k_files=$(find . -name "*.k" -type f 2>/dev/null)

        if [ -z "$k_files" ]; then
            print_warning "No peer files found in $repo_name"
            continue
        fi

        local file_count=$(echo "$k_files" | wc -l)
        print_success "Found $file_count peer files in $repo_name"

        local repo_ipv4=0
        local repo_ipv6=0

        # Process each .k file
        while IFS= read -r peer_file; do
            [ -z "$peer_file" ] && continue

            # Validate JSON
            if ! jq empty "$peer_file" 2>/dev/null; then
                continue
            fi

            # Extract IPv4 peers (addresses without brackets)
            local ipv4_data
            ipv4_data=$(jq 'to_entries | map(select(.key | startswith("[") | not)) | from_entries' "$peer_file" 2>/dev/null)

            if [ -n "$ipv4_data" ] && [ "$ipv4_data" != "{}" ]; then
                # Merge into output
                jq -s '.[0] * .[1]' "$output_ipv4" <(echo "$ipv4_data") > "$output_ipv4.tmp"
                mv "$output_ipv4.tmp" "$output_ipv4"
                repo_ipv4=$((repo_ipv4 + $(echo "$ipv4_data" | jq 'length')))
            fi

            # Extract IPv6 peers (addresses with brackets)
            local ipv6_data
            ipv6_data=$(jq 'to_entries | map(select(.key | startswith("["))) | from_entries' "$peer_file" 2>/dev/null)

            if [ -n "$ipv6_data" ] && [ "$ipv6_data" != "{}" ]; then
                # Merge into output
                jq -s '.[0] * .[1]' "$output_ipv6" <(echo "$ipv6_data") > "$output_ipv6.tmp"
                mv "$output_ipv6.tmp" "$output_ipv6"
                repo_ipv6=$((repo_ipv6 + $(echo "$ipv6_data" | jq 'length')))
            fi

        done <<< "$k_files"

        print_success "Extracted $repo_ipv4 IPv4 and $repo_ipv6 IPv6 peers from $repo_name"

        total_ipv4=$((total_ipv4 + repo_ipv4))
        total_ipv6=$((total_ipv6 + repo_ipv6))

        cd "$temp_dir" || return 1
    done

    echo "$total_ipv4|$total_ipv6"
    return 0
}

# Try to fetch peers from kaotisk-hund/python-cjdns-peering-tools
discover_peers_from_kaotisk() {
    local output_ipv4="$1"
    local output_ipv6="$2"

    local url="https://raw.githubusercontent.com/kaotisk-hund/python-cjdns-peering-tools/master/peers.json"

    print_info "Fetching peers from kaotisk-hund..."

    local temp_file=$(mktemp)
    if ! wget -q -T 15 -O "$temp_file" "$url" 2>/dev/null; then
        print_warning "Failed to fetch from kaotisk-hund (source may be down)"
        rm -f "$temp_file"
        return 1
    fi

    # Validate JSON
    if ! jq empty "$temp_file" 2>/dev/null; then
        print_warning "Invalid JSON from kaotisk-hund source"
        rm -f "$temp_file"
        return 1
    fi

    # Split into IPv4 and IPv6
    local ipv4_data ipv6_data
    ipv4_data=$(jq 'to_entries | map(select(.key | startswith("[") | not)) | from_entries' "$temp_file" 2>/dev/null)
    ipv6_data=$(jq 'to_entries | map(select(.key | startswith("["))) | from_entries' "$temp_file" 2>/dev/null)

    # Merge into existing outputs
    if [ -n "$ipv4_data" ] && [ "$ipv4_data" != "{}" ]; then
        jq -s '.[0] * .[1]' "$output_ipv4" <(echo "$ipv4_data") > "$output_ipv4.tmp"
        mv "$output_ipv4.tmp" "$output_ipv4"
    fi

    if [ -n "$ipv6_data" ] && [ "$ipv6_data" != "{}" ]; then
        jq -s '.[0] * .[1]' "$output_ipv6" <(echo "$ipv6_data") > "$output_ipv6.tmp"
        mv "$output_ipv6.tmp" "$output_ipv6"
    fi

    local count_ipv4=$(echo "$ipv4_data" | jq 'length')
    local count_ipv6=$(echo "$ipv6_data" | jq 'length')

    print_success "Extracted $count_ipv4 IPv4 and $count_ipv6 IPv6 peers from kaotisk-hund"

    rm -f "$temp_file"
    return 0
}

# Test peer connectivity via ping
test_peer_connectivity() {
    local address="$1"
    local timeout="${2:-2}"

    # Determine if IPv4 or IPv6
    if [[ "$address" =~ ^\[.*\]: ]]; then
        # IPv6 - extract address without brackets and port
        local ip=$(echo "$address" | sed 's/^\[\(.*\)\]:.*$/\1/')
        ping -6 -c 1 -W "$timeout" "$ip" &>/dev/null
    else
        # IPv4 - extract IP without port
        local ip="${address%%:*}"
        ping -c 1 -W "$timeout" "$ip" &>/dev/null
    fi

    return $?
}

# Get current peer states from cjdns
# Output format: STATE|ADDRESS|SOURCE where SOURCE is "config" or "dns"
get_current_peer_states() {
    local admin_ip="$1"
    local admin_port="$2"
    local admin_password="$3"
    local output_file="$4"

    > "$output_file"

    # Get all config addresses for matching (handles IPv6 format differences)
    local config_addrs_file="$WORK_DIR/config_addrs.txt"
    {
        jq -r '.interfaces.UDPInterface[0].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null
        jq -r '.interfaces.UDPInterface[1].connectTo // {} | keys[]' "$CJDNS_CONFIG" 2>/dev/null
    } > "$config_addrs_file"

    local page=0
    while true; do
        local result
        result=$(cjdnstool -a "$admin_ip" -p "$admin_port" -P "$admin_password" cexec InterfaceController_peerStats --page=$page 2>/dev/null)

        if [ -z "$result" ]; then
            break
        fi

        # Extract peer addresses and states, matching to config format
        while IFS='|' read -r state lladdr; do
            [ -z "$lladdr" ] && continue

            # Try to find matching config address (handles IPv6 leading zero differences)
            local matched_addr="$lladdr"
            local in_config="dns"  # Default to DNS-discovered

            if [[ "$lladdr" =~ ^\[ ]]; then
                # IPv6 - normalize and compare
                local normalized_lladdr=$(normalize_ipv6_address "$lladdr")
                while IFS= read -r config_addr; do
                    [ -z "$config_addr" ] && continue
                    local normalized_config=$(normalize_ipv6_address "$config_addr")
                    if [ "$normalized_lladdr" = "$normalized_config" ]; then
                        matched_addr="$config_addr"
                        in_config="config"
                        break
                    fi
                done < "$config_addrs_file"
            else
                # IPv4 - direct comparison
                if grep -Fxq "$lladdr" "$config_addrs_file" 2>/dev/null; then
                    in_config="config"
                fi
            fi

            echo "$state|$matched_addr|$in_config"
        done < <(echo "$result" | jq -r '.peers[]? | "\(.state)|\(.lladdr)"' 2>/dev/null) >> "$output_file"

        # Check if we got any peers on this page
        local peer_count
        peer_count=$(echo "$result" | jq '.peers | length' 2>/dev/null || echo 0)

        if [ "$peer_count" -eq 0 ]; then
            break
        fi

        page=$((page + 1))
    done

    return 0
}

# Filter peer states to only include peers from config (not DNS-discovered)
filter_config_peers() {
    local peer_states="$1"
    local output_file="$2"

    grep "|config$" "$peer_states" 2>/dev/null | sed 's/|config$//' > "$output_file" || touch "$output_file"
}

# Count unresponsive peers that are actually in config (not DNS-discovered)
count_unresponsive_config_peers() {
    local peer_states="$1"
    grep "^UNRESPONSIVE|.*|config$" "$peer_states" 2>/dev/null | wc -l | tr -d ' '
}

# Filter out peers already in config
filter_new_peers() {
    local all_peers_file="$1"
    local config_file="$2"
    local interface_index="$3"
    local output_file="$4"

    # Extract existing peers from config
    local existing=$(mktemp)
    jq -r ".interfaces.UDPInterface[$interface_index].connectTo // {} | keys[]" "$config_file" 2>/dev/null > "$existing" || touch "$existing"

    # Filter out existing peers
    local all_addrs=$(jq -r 'keys[]' "$all_peers_file" 2>/dev/null)

    echo "{" > "$output_file"
    local first=true

    while IFS= read -r addr; do
        [ -z "$addr" ] && continue

        if ! grep -Fxq "$addr" "$existing"; then
            # This is a new peer
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$output_file"
            fi

            local peer_data=$(jq -r --arg addr "$addr" '{($addr): .[$addr]}' "$all_peers_file")
            echo -n "$peer_data" | jq -r 'to_entries[] | "  \"\(.key)\": \(.value)"' >> "$output_file"
        fi
    done <<< "$all_addrs"

    echo "" >> "$output_file"
    echo "}" >> "$output_file"

    rm -f "$existing"

    # Return count of new peers
    jq 'length' "$output_file"
}

# Smart duplicate detection - detects address matches with different credentials
# Returns: filtered peers JSON + updates JSON (if user approves updates)
# Parameter 6 (optional): interactive mode (1=interactive/ask user, 0=non-interactive/silent)
smart_duplicate_check() {
    local new_peers_file="$1"
    local config_file="$2"
    local interface_index="$3"
    local output_new="$4"
    local output_updates="$5"
    local interactive="${6:-1}"  # Default to interactive mode

    # Extract existing peers from config
    local existing_peers=$(mktemp)
    jq -r ".interfaces.UDPInterface[$interface_index].connectTo // {}" "$config_file" > "$existing_peers"

    echo "{}" > "$output_new"
    echo "{}" > "$output_updates"

    local new_addrs=$(jq -r 'keys[]' "$new_peers_file" 2>/dev/null)

    while IFS= read -r addr; do
        [ -z "$addr" ] && continue

        # Check if address exists in config
        local exists=$(jq -e --arg addr "$addr" 'has($addr)' "$existing_peers" 2>/dev/null)

        if [ "$exists" = "true" ]; then
            # Address exists - compare ONLY password and publicKey (required fields)
            # Metadata changes (contact, peerName, etc.) don't matter since we don't write them to config
            local config_peer=$(jq --arg addr "$addr" '.[$addr]' "$existing_peers")
            local new_peer=$(jq --arg addr "$addr" '.[$addr]' "$new_peers_file")

            # Extract only password and publicKey for comparison
            local config_password=$(echo "$config_peer" | jq -r '.password // ""')
            local config_publicKey=$(echo "$config_peer" | jq -r '.publicKey // ""')
            local new_password=$(echo "$new_peer" | jq -r '.password // ""')
            local new_publicKey=$(echo "$new_peer" | jq -r '.publicKey // ""')

            # Only consider it a credential update if password OR publicKey changed
            if [ "$config_password" != "$new_password" ] || [ "$config_publicKey" != "$new_publicKey" ]; then
                # Actual credentials differ (not just metadata)
                if [ "$interactive" -eq 1 ]; then
                    # Interactive mode - show comparison and ask
                    print_warning "Duplicate address found with different credentials: $addr" >&2
                    echo >&2
                    echo "Current configuration:" >&2
                    echo "  password: $config_password" >&2
                    echo "  publicKey: $config_publicKey" >&2
                    echo >&2
                    echo "New peer data:" >&2
                    echo "  password: $new_password" >&2
                    echo "  publicKey: $new_publicKey" >&2
                    echo >&2

                    if ask_yes_no "Update this peer with new credentials?"; then
                        # Add to updates JSON
                        jq -s --arg addr "$addr" --argjson peer "$new_peer" \
                            '.[0] + {($addr): $peer}' "$output_updates" > "$output_updates.tmp"
                        mv "$output_updates.tmp" "$output_updates"
                        print_success "Will update peer: $addr" >&2
                    else
                        print_info "Keeping existing configuration for: $addr" >&2
                    fi
                else
                    # Non-interactive mode - silently add to updates (user can decide later)
                    jq -s --arg addr "$addr" --argjson peer "$new_peer" \
                        '.[0] + {($addr): $peer}' "$output_updates" > "$output_updates.tmp"
                    mv "$output_updates.tmp" "$output_updates"
                fi
            else
                # Same credentials (password + publicKey match)
                # Ignore metadata differences - they don't matter for config
                :
            fi
        else
            # New peer - add to output
            local peer_data=$(jq --arg addr "$addr" '.[$addr]' "$new_peers_file")
            jq -s --arg addr "$addr" --argjson peer "$peer_data" \
                '.[0] + {($addr): $peer}' "$output_new" > "$output_new.tmp"
            mv "$output_new.tmp" "$output_new"
        fi

    done <<< "$new_addrs"

    rm -f "$existing_peers"

    # Return counts
    local new_count=$(jq 'length' "$output_new")
    local update_count=$(jq 'length' "$output_updates")
    echo "$new_count|$update_count"
}

# Apply peer updates to config (writes ONLY required fields: password and publicKey)
apply_peer_updates() {
    local config_file="$1"
    local updates_json="$2"
    local interface_index="$3"
    local temp_config="$4"

    cp "$config_file" "$temp_config"

    local update_addrs=$(jq -r 'keys[]' "$updates_json" 2>/dev/null)

    while IFS= read -r addr; do
        [ -z "$addr" ] && continue

        local peer_data=$(jq --arg addr "$addr" '.[$addr]' "$updates_json")

        # Update the peer in config - ONLY password and publicKey (required fields)
        # Strip metadata to keep config minimal and avoid validation issues
        jq --arg addr "$addr" --argjson peer "$peer_data" --argjson idx "$interface_index" \
            '.interfaces.UDPInterface[$idx].connectTo[$addr] = {
                password: $peer.password,
                publicKey: $peer.publicKey
            }' \
            "$temp_config" > "$temp_config.tmp"
        mv "$temp_config.tmp" "$temp_config"

    done <<< "$update_addrs"

    return 0
}
