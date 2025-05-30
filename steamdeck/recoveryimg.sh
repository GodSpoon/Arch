#!/bin/bash

# Steam Deck Recovery USB Creator - Qt GUI Version
# A GUI script to select/download Steam Deck recovery image and write it to USB

set -euo pipefail

# Configuration
DOWNLOAD_URL="https://steamdeck-images.steamos.cloud/recovery/steamdeck-repair-latest.img.bz2"
DEFAULT_SEARCH_DIR="/home/$USER/Downloads/"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SELECTED_IMAGE=""
SELECTED_DEVICE=""

# Function to check if required tools are installed
check_dependencies() {
    local missing_tools=()
    
    for tool in kdialog wget lsblk dd sudo; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    # Check for bzcat or bzip2
    if ! command -v bzcat &> /dev/null && ! command -v bzip2 &> /dev/null; then
        missing_tools+=("bzcat/bzip2")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        if command -v kdialog &> /dev/null; then
            kdialog --error "Missing required tools: ${missing_tools[*]}\n\nPlease install them and try again.\n\nOn Ubuntu/Debian: sudo apt install kde-cli-tools wget bzip2\nOn Fedora: sudo dnf install kdialog wget bzip2\nOn Arch: sudo pacman -S kdialog wget bzip2"
        else
            echo -e "${RED}Error: Missing required tools: ${missing_tools[*]}${NC}"
            echo "Please install kdialog and other dependencies first."
        fi
        exit 1
    fi
}

# Function to show welcome dialog
show_welcome() {
    kdialog --msgbox "Steam Deck Recovery USB Creator\n\nThis tool will help you:\n• Select an existing recovery image (.img/.bz2) or download latest\n• Select a USB drive\n• Create a bootable recovery USB\n\nWARNING: This will completely erase the selected USB drive!" \
        --title "Steam Deck Recovery USB Creator"
}

# Function to find existing image files
find_image_files() {
    local search_dir="$1"
    local files=()
    
    # Find .img and .bz2 files
    while IFS= read -r -d '' file; do
        if [[ "$file" =~ \.(img|bz2)$ ]]; then
            files+=("$file")
        fi
    done < <(find "$search_dir" -maxdepth 2 -type f \( -name "*.img" -o -name "*.bz2" \) -print0 2>/dev/null)
    
    printf '%s\n' "${files[@]}"
}

# Function to format file info for display
format_file_info() {
    local file="$1"
    local basename=$(basename "$file")
    local size=$(du -h "$file" | cut -f1)
    local date=$(date -r "$file" "+%Y-%m-%d %H:%M")
    local dir=$(dirname "$file")
    
    echo "$basename|$size|$date|$file"
}

# Function to handle image selection
select_image_file() {
    local action=$(kdialog --menu "Choose an option:" \
        "scan" "Scan for existing .img/.bz2 files" \
        "browse" "Browse for image file" \
        "download" "Download latest Steam Deck recovery image" \
        --title "Image Source Selection")
    
    case "$action" in
        "scan")
            local search_dir=$(kdialog --getexistingdirectory "$DEFAULT_SEARCH_DIR" \
                --title "Select directory to scan for image files")
            
            if [ -z "$search_dir" ]; then
                return 1
            fi
            
            echo -e "${BLUE}Scanning for image files in $search_dir...${NC}"
            
            local files=($(find_image_files "$search_dir"))
            
            if [ ${#files[@]} -eq 0 ]; then
                kdialog --sorry "No .img or .bz2 files found in $search_dir"
                return 1
            fi
            
            # Prepare file list for selection
            local file_list=""
            for file in "${files[@]}"; do
                local info=$(format_file_info "$file")
                file_list="$file_list $info"
            done
            
            local selection=$(echo "$file_list" | tr ' ' '\n' | \
                kdialog --radiolist "Select image file:" \
                --title "Found Image Files" \
                --separate-output \
                $(echo "$file_list" | tr ' ' '\n' | while IFS='|' read -r name size date path; do
                    echo "\"$path\" \"$name ($size, $date)\" off"
                done))
            
            if [ -n "$selection" ]; then
                SELECTED_IMAGE="$selection"
                return 0
            fi
            return 1
            ;;
            
        "browse")
            local file=$(kdialog --getopenfilename "$DEFAULT_SEARCH_DIR" "*.img *.bz2|Image Files (*.img *.bz2)" \
                --title "Select Image File")
            
            if [ -n "$file" ] && [ -f "$file" ]; then
                SELECTED_IMAGE="$file"
                return 0
            fi
            return 1
            ;;
            
        "download")
            download_image
            return $?
            ;;
            
        *)
            return 1
            ;;
    esac
}

# Function to download the recovery image
download_image() {
    local download_dir=$(kdialog --getexistingdirectory "$DEFAULT_SEARCH_DIR" \
        --title "Select download directory")
    
    if [ -z "$download_dir" ]; then
        return 1
    fi
    
    local image_file="$download_dir/steamdeck-repair-latest.img.bz2"
    
    # Check if file already exists
    if [ -f "$image_file" ]; then
        local file_size=$(du -h "$image_file" | cut -f1)
        local file_date=$(date -r "$image_file" "+%Y-%m-%d %H:%M")
        
        if kdialog --yesno "File already exists:\n\nFile: $(basename "$image_file")\nSize: $file_size\nDate: $file_date\n\nDo you want to overwrite it?"; then
            rm "$image_file"
        else
            SELECTED_IMAGE="$image_file"
            return 0
        fi
    fi
    
    echo -e "${BLUE}Starting download...${NC}"
    
    # Start download with progress
    (
        wget --progress=dot:giga -O "$image_file" "$DOWNLOAD_URL" 2>&1 | \
        while IFS= read -r line; do
            if [[ $line =~ ([0-9]+)% ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
        done
    ) | kdialog --progressbar "Downloading steamdeck-repair-latest.img.bz2...\n\nThis may take several minutes depending on your internet connection." 100 \
        --title "Downloading Recovery Image"
    
    if [ $? -eq 0 ] && [ -f "$image_file" ]; then
        kdialog --msgbox "Download completed successfully!\n\nFile: $(basename "$image_file")\nSize: $(du -h "$image_file" | cut -f1)"
        SELECTED_IMAGE="$image_file"
        return 0
    else
        kdialog --error "Download failed! Please check your internet connection and try again."
        return 1
    fi
}

# Function to get USB devices
get_usb_devices() {
    local devices=()
    local device_descriptions=()
    
    # Get USB block devices
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local device=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $4}')
            local model=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=""; print $0}' | sed 's/^[[:space:]]*//' | sed 's/_/ /g')
            local vendor=$(echo "$line" | awk '{print $6}' | sed 's/_/ /g')
            
            # Skip if device is mounted or is a partition
            if [[ ! "$device" =~ [0-9]$ ]] && [ -b "/dev/$device" ]; then
                local mount_points=$(lsblk -n -o MOUNTPOINT "/dev/$device" 2>/dev/null | grep -v "^$" | wc -l)
                if [ "$mount_points" -eq 0 ]; then
                    devices+=("/dev/$device")
                    device_descriptions+=("$device ($size) - $vendor $model")
                fi
            fi
        fi
    done < <(lsblk -d -n -o NAME,TYPE,HOTPLUG,RM,SIZE,VENDOR,MODEL | awk '$2=="disk" && $3=="1" && $4=="1"')
    
    if [ ${#devices[@]} -eq 0 ]; then
        kdialog --error "No removable USB devices found!\n\nPlease:\n• Insert a USB drive\n• Make sure it's not mounted\n• Try again"
        return 1
    fi
    
    # Create selection dialog
    local radio_options=""
    for i in "${!devices[@]}"; do
        radio_options="$radio_options \"${devices[$i]}\" \"${device_descriptions[$i]}\" off"
    done
    
    local selection=$(eval kdialog --radiolist \
        \"WARNING: The selected device will be completely erased!\n\nSelect the USB device to write the recovery image to:\" \
        --title \"Select USB Device\" \
        $radio_options)
    
    if [ -n "$selection" ]; then
        SELECTED_DEVICE="$selection"
        return 0
    fi
    
    return 1
}

# Function to confirm the destructive operation
confirm_operation() {
    local device="$1"
    local image="$2"
    local device_info=$(lsblk -n -o SIZE,VENDOR,MODEL "$device" 2>/dev/null | head -1)
    local image_info="$(basename "$image") ($(du -h "$image" | cut -f1))"
    
    kdialog --yesno "FINAL WARNING!\n\nYou are about to:\n• COMPLETELY ERASE device: $device\n• Device info: $device_info\n• Write image: $image_info\n\nALL DATA ON THIS DEVICE WILL BE LOST!\n\nAre you absolutely sure you want to continue?" \
        --title "Final Confirmation"
    
    return $?
}

# Function to write image to USB device
write_image() {
    local device="$1"
    local image="$2"
    
    echo -e "${YELLOW}Writing image to $device...${NC}"
    
    # Check if device exists and is a block device
    if [ ! -b "$device" ]; then
        kdialog --error "Device $device is not a valid block device!"
        return 1
    fi
    
    # Unmount any mounted partitions
    for partition in $(lsblk -ln -o NAME "$device" | tail -n +2); do
        if mountpoint -q "/dev/$partition" 2>/dev/null; then
            sudo umount "/dev/$partition" 2>/dev/null || true
        fi
    done
    
    # Determine how to handle the image file
    local decompress_cmd=""
    if [[ "$image" =~ \.bz2$ ]]; then
        if command -v bzcat &> /dev/null; then
            decompress_cmd="bzcat"
        else
            decompress_cmd="bzip2 -dc"
        fi
    else
        decompress_cmd="cat"
    fi
    
    # Create progress dialog and write image
    (
        echo "10"
        echo "# Preparing to write image..."
        sleep 1
        
        echo "20"
        echo "# Starting image write process..."
        
        # Execute the write command
        $decompress_cmd "$image" | sudo dd if=/dev/stdin of="$device" oflag=sync status=none bs=128M
        local dd_result=$?
        
        if [ $dd_result -eq 0 ]; then
            echo "90"
            echo "# Syncing and ejecting..."
            sync
            sudo eject "$device" 2>/dev/null || true
            
            echo "100"
            echo "# Complete!"
            sleep 1
        else
            echo "# Error occurred during write!"
            exit 1
        fi
    ) | kdialog --progressbar "Writing Steam Deck recovery image to $device...\n\nThis may take 10-30 minutes depending on your USB drive speed." 100 \
        --title "Writing Recovery Image"
    
    local write_result=$?
    
    if [ $write_result -eq 0 ]; then
        kdialog --msgbox "Steam Deck recovery USB created successfully!\n\nDevice: $device\n\nThe USB drive has been ejected and is ready to use.\n\nTo use:\n1. Insert USB into Steam Deck\n2. Power on while holding Volume Down + Power\n3. Select boot from USB" \
            --title "Success!"
        return 0
    else
        kdialog --error "Failed to write image to $device!\n\nPlease check:\n• USB device is working properly\n• You have sufficient permissions\n• Device is not write-protected"
        return 1
    fi
}

# Main function
main() {
    echo -e "${GREEN}Steam Deck Recovery USB Creator (Qt GUI)${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    # Check dependencies
    check_dependencies
    
    # Show welcome dialog
    show_welcome
    
    # Select or download image
    if ! select_image_file; then
        kdialog --sorry "No image file selected. Exiting."
        exit 0
    fi
    
    echo -e "${GREEN}Selected image: $SELECTED_IMAGE${NC}"
    
    # Get USB device selection
    if ! get_usb_devices; then
        exit 1
    fi
    
    echo -e "${GREEN}Selected device: $SELECTED_DEVICE${NC}"
    
    # Confirm operation
    if ! confirm_operation "$SELECTED_DEVICE" "$SELECTED_IMAGE"; then
        kdialog --msgbox "Operation cancelled by user."
        exit 0
    fi
    
    # Write image to device
    if write_image "$SELECTED_DEVICE" "$SELECTED_IMAGE"; then
        echo -e "${GREEN}Process completed successfully!${NC}"
    else
        echo -e "${RED}Process failed!${NC}"
        exit 1
    fi
}

# Check if running as root (shouldn't be)
if [ "$EUID" -eq 0 ]; then
    if command -v kdialog &> /dev/null; then
        kdialog --error "Please do not run this script as root!\n\nThe script will ask for sudo permissions when needed."
    else
        echo -e "${RED}Please do not run this script as root!${NC}"
    fi
    exit 1
fi

# Run main function
main "$@"
