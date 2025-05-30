#!/bin/bash

set -e

echo "=== Cloudflare DNS Manager ==="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for AUR helper
get_aur_helper() {
    if command_exists yay; then
        echo "yay"
    elif command_exists paru; then
        echo "paru"
    else
        echo "none"
    fi
}

# Install flarectl if needed
if ! command_exists flarectl; then
    echo "flarectl not found. Installing..."
    AUR_HELPER=$(get_aur_helper)

    if [ "$AUR_HELPER" = "none" ]; then
        echo "No AUR helper found. Please install yay or paru first:"
        echo "  sudo pacman -S --needed base-devel git"
        echo "  git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si"
        exit 1
    fi

    echo "Installing flarectl with $AUR_HELPER..."
    $AUR_HELPER -S --noconfirm flarectl-bin
else
    echo "✓ flarectl is available"
fi

# Export CF API token from pass
if ! command_exists pass; then
    echo "Error: pass is not installed. Run the setup script first."
    exit 1
fi

if ! pass show cloudflare/api-token >/dev/null 2>&1; then
    echo "Error: Cloudflare API token not found in pass. Run the setup script first."
    exit 1
fi

export CF_API_TOKEN="$(pass show cloudflare/api-token)"
echo "✓ Loaded Cloudflare API token from pass"

# Main menu function
show_main_menu() {
    echo ""
    echo "Choose an action:"
    echo "1) List DNS records"
    echo "2) Create DNS record"
    echo "3) Update DNS record"
    echo "4) Delete DNS record"
    echo "5) Exit"
    echo ""
}

# DNS record type menu
show_record_types() {
    echo ""
    echo "Select DNS record type:"
    echo "1) A (IPv4 address)"
    echo "2) AAAA (IPv6 address)"
    echo "3) CNAME (Canonical name)"
    echo "4) MX (Mail exchange)"
    echo "5) TXT (Text record)"
    echo "6) SRV (Service record)"
    echo "7) NS (Name server)"
    echo ""
}

# Get zone from user
get_zone() {
    read -p "Enter zone (e.g., spoon.rip): " ZONE
    if [ -z "$ZONE" ]; then
        echo "Zone cannot be empty"
        return 1
    fi
}

# Get record name
get_record_name() {
    read -p "Enter record name (e.g., pve-m1 for pve-m1.$ZONE): " RECORD_NAME
    if [ -z "$RECORD_NAME" ]; then
        echo "Record name cannot be empty"
        return 1
    fi
}

# Get record content based on type
get_record_content() {
    local record_type="$1"

    case "$record_type" in
        "A")
            read -p "Enter IPv4 address (e.g., 192.168.1.100): " CONTENT
            ;;
        "AAAA")
            read -p "Enter IPv6 address (e.g., 2001:db8::1): " CONTENT
            ;;
        "CNAME")
            read -p "Enter target hostname (e.g., opnsense.spoon.rip): " CONTENT
            ;;
        "MX")
            read -p "Enter priority (e.g., 10): " PRIORITY
            read -p "Enter mail server (e.g., mail.spoon.rip): " CONTENT
            ;;
        "TXT")
            read -p "Enter text content (e.g., \"v=spf1 include:_spf.google.com ~all\"): " CONTENT
            ;;
        "SRV")
            read -p "Enter priority: " PRIORITY
            read -p "Enter weight: " WEIGHT
            read -p "Enter port: " PORT
            read -p "Enter target: " CONTENT
            ;;
        "NS")
            read -p "Enter nameserver (e.g., ns1.example.com): " CONTENT
            ;;
        *)
            echo "Unknown record type"
            return 1
            ;;
    esac

    if [ -z "$CONTENT" ]; then
        echo "Content cannot be empty"
        return 1
    fi
}

# List DNS records
list_records() {
    get_zone || return 1
    echo "Listing DNS records for zone: $ZONE"
    flarectl dns list --zone "$ZONE"
}

# Create DNS record
create_record() {
    get_zone || return 1
    get_record_name || return 1

    show_record_types
    read -p "Select record type (1-7): " TYPE_CHOICE

    case "$TYPE_CHOICE" in
        1) RECORD_TYPE="A" ;;
        2) RECORD_TYPE="AAAA" ;;
        3) RECORD_TYPE="CNAME" ;;
        4) RECORD_TYPE="MX" ;;
        5) RECORD_TYPE="TXT" ;;
        6) RECORD_TYPE="SRV" ;;
        7) RECORD_TYPE="NS" ;;
        *) echo "Invalid choice"; return 1 ;;
    esac

    get_record_content "$RECORD_TYPE" || return 1

    # Build flarectl command
    CMD="flarectl dns create --zone \"$ZONE\" --name \"$RECORD_NAME\" --type \"$RECORD_TYPE\" --content \"$CONTENT\""

    # Add additional parameters for specific record types
    case "$RECORD_TYPE" in
        "MX")
            CMD="$CMD --priority $PRIORITY"
            ;;
        "SRV")
            CMD="$CMD --priority $PRIORITY --port $PORT"
            if [ -n "$WEIGHT" ]; then
                CMD="$CMD --weight $WEIGHT"
            fi
            ;;
    esac

    echo ""
    echo "Creating DNS record..."
    echo "Command: $CMD"
    echo ""

    eval $CMD

    if [ $? -eq 0 ]; then
        echo "✓ DNS record created successfully!"
    else
        echo "✗ Failed to create DNS record"
    fi
}

# Update DNS record
update_record() {
    echo "Update functionality requires record ID. Listing records first..."
    list_records || return 1
    echo ""
    read -p "Enter the record ID to update: " RECORD_ID

    if [ -z "$RECORD_ID" ]; then
        echo "Record ID cannot be empty"
        return 1
    fi

    show_record_types
    read -p "Select new record type (1-7): " TYPE_CHOICE

    case "$TYPE_CHOICE" in
        1) RECORD_TYPE="A" ;;
        2) RECORD_TYPE="AAAA" ;;
        3) RECORD_TYPE="CNAME" ;;
        4) RECORD_TYPE="MX" ;;
        5) RECORD_TYPE="TXT" ;;
        6) RECORD_TYPE="SRV" ;;
        7) RECORD_TYPE="NS" ;;
        *) echo "Invalid choice"; return 1 ;;
    esac

    get_record_content "$RECORD_TYPE" || return 1

    echo ""
    echo "Updating DNS record..."
    flarectl dns update --zone "$ZONE" --id "$RECORD_ID" --type "$RECORD_TYPE" --content "$CONTENT"

    if [ $? -eq 0 ]; then
        echo "✓ DNS record updated successfully!"
    else
        echo "✗ Failed to update DNS record"
    fi
}

# Delete DNS record
delete_record() {
    list_records || return 1
    echo ""
    read -p "Enter the record ID to delete: " RECORD_ID

    if [ -z "$RECORD_ID" ]; then
        echo "Record ID cannot be empty"
        return 1
    fi

    read -p "Are you sure you want to delete record ID $RECORD_ID? (y/N): " CONFIRM

    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Deleting DNS record..."
        flarectl dns delete --zone "$ZONE" --id "$RECORD_ID"

        if [ $? -eq 0 ]; then
            echo "✓ DNS record deleted successfully!"
        else
            echo "✗ Failed to delete DNS record"
        fi
    else
        echo "Delete cancelled"
    fi
}

# Main loop
while true; do
    show_main_menu
    read -p "Enter your choice (1-5): " CHOICE

    case "$CHOICE" in
        1)
            list_records
            ;;
        2)
            create_record
            ;;
        3)
            update_record
            ;;
        4)
            delete_record
            ;;
        5)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please select 1-5."
            ;;
    esac

    echo ""
    read -p "Press Enter to continue..."
done
