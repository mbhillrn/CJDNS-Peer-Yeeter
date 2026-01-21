#!/usr/bin/env bash
# Prerequisites Module - Check and install required tools

# Check if gum is installed
check_gum() {
    if command -v gum &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Install gum via charm.sh repository
install_gum() {
    print_info "Installing gum from charm.sh repository..."
    echo

    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then
        print_error "This installation requires root privileges"
        print_info "Please run this script with sudo or as root"
        return 1
    fi

    # Add GPG key
    print_working "Adding Charm repository GPG key..."
    if ! mkdir -p /etc/apt/keyrings 2>/dev/null; then
        print_complete "Failed to create keyrings directory" "failed"
        return 1
    fi

    if ! curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null; then
        print_complete "Failed to add GPG key" "failed"
        return 1
    fi
    print_complete "GPG key added" "success"

    # Add repository
    print_working "Adding Charm repository..."
    if ! echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list >/dev/null; then
        print_complete "Failed to add repository" "failed"
        return 1
    fi
    print_complete "Repository added" "success"

    # Update package list
    print_working "Updating package lists..."
    if ! apt update >/dev/null 2>&1; then
        print_complete "Failed to update packages" "failed"
        return 1
    fi
    print_complete "Package lists updated" "success"

    # Install gum
    print_working "Installing gum..."
    if ! apt install -y gum >/dev/null 2>&1; then
        print_complete "Failed to install gum" "failed"
        return 1
    fi
    print_complete "gum installed successfully!" "success"

    return 0
}

# Check if fzf is installed (optional)
check_fzf() {
    if command -v fzf &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Install fzf via apt
install_fzf() {
    print_info "Installing fzf..."
    echo

    if [ "$EUID" -ne 0 ]; then
        print_error "This installation requires root privileges"
        return 1
    fi

    if apt install -y fzf >/dev/null 2>&1; then
        print_success "fzf installed successfully!"
        return 0
    else
        print_error "Failed to install fzf"
        return 1
    fi
}

# Check all prerequisites
check_prerequisites() {
    local missing_tools=()
    local optional_missing=()

    # Check required tools
    if ! check_gum; then
        missing_tools+=("gum")
    fi

    # Check optional tools
    if ! check_fzf; then
        optional_missing+=("fzf")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_warning "Missing required tools: ${missing_tools[*]}"
        echo
        print_info "PeerYeeter requires 'gum' for interactive menus and enhanced user experience"
        echo
        print_info "Installation command:"
        echo "  sudo mkdir -p /etc/apt/keyrings"
        echo "  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg"
        echo "  echo \"deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\" | sudo tee /etc/apt/sources.list.d/charm.list"
        echo "  sudo apt update && sudo apt install gum"
        echo

        if ask_yes_no "Would you like to install gum now?"; then
            echo
            if install_gum; then
                print_success "Installation complete!"
            else
                print_error "Installation failed"
                echo
                print_error "Cannot proceed without gum. Please install it manually and try again."
                return 1
            fi
        else
            print_error "Cannot proceed without gum"
            echo
            print_info "Please install gum manually and run PeerYeeter again"
            return 1
        fi
    fi

    # Inform about optional tools
    if [ ${#optional_missing[@]} -gt 0 ]; then
        print_info "Optional tools not installed: ${optional_missing[*]}"
        print_info "These tools enhance the experience but are not required"
    fi

    return 0
}
