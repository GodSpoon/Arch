#!/bin/bash

# This script provides a simple GUI for writing a .img.bz2 (or .img) file
# to a selected drive using bzcat and dd.
# It uses 'whiptail' for the graphical interface.

# --- Function to display an error message and exit ---
display_error_and_exit() {
    whiptail --msgbox "$1" 10 78
    exit 1
}

# --- Check for whiptail availability ---
if ! command -v whiptail &> /dev/null; then
    echo "Error: 'whiptail' command not found."
    echo "Please install it. On Debian/Ubuntu: sudo apt install whiptail"
    echo "On Fedora/RHEL: sudo yum install newt"
    exit 1
fi

# --- Define the Downloads directory ---
# Using $HOME ensures it works correctly regardless of how the script is run.
DOWNLOADS_DIR="$HOME/Downloads"

# --- 1. Find image files (.img.bz2 first, then .img*) ---
IMG_FILES=()

# Search for .img.bz2 files
while IFS= read -r -d $'\0'; do
    IMG_FILES+=("$REPLY")
done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -name "*.img.bz2" -print0 2>/dev/null)

# If no .img.bz2 files are found, search for any .img* files
if [ ${#IMG_FILES[@]} -eq 0 ]; then
    while IFS= read -r -d $'\0'; do
        IMG_FILES+=("$REPLY")
    done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -name "*.img*" -print0 2>/dev/null)
fi

# Check if any image files were found
if [ ${#IMG_FILES[@]} -eq 0 ]; then
    display_error_and_exit "No .img.bz2 or .img* files found in '$DOWNLOADS_DIR'."
fi

# --- 2. Let the user select the image file ---
FILE_OPTIONS=()
for i in "${!IMG_FILES[@]}"; do
    # Add a numbered option and the basename of the file
    FILE_OPTIONS+=("$((i+1))" "$(basename "${IMG_FILES[$i]}")")
done

# Display a menu for file selection
SELECTED_FILE_INDEX=$(whiptail --menu "Select an image file to write:" 20 78 10 "${FILE_OPTIONS[@]}" 3>&1 1>&2 2>&3)

# Check if the user cancelled the selection
if [ -z "$SELECTED_FILE_INDEX" ]; then
    echo "Image file selection cancelled. Exiting."
    exit 0
fi

# Get the full path of the selected image file
SELECTED_IMAGE_PATH="${IMG_FILES[$((SELECTED_FILE_INDEX-1))]}"
whiptail --msgbox "You selected: $(basename "$SELECTED_IMAGE_PATH")" 8 78

# --- 3. Prompt for the drive to write to ---
DRIVE_INFO=()   # Array to store descriptive info for whiptail
DRIVE_PATHS=()  # Array to store actual /dev/ paths
SYSTEM_DRIVES=() # Array to store paths identified as potential system drives

# Determine the root device (heuristic for identifying system drives)
# This removes partition numbers (e.g., /dev/sda1 -> /dev/sda)
ROOT_DEV_PATH=$(df / | grep -E '^/dev/' | awk '{print $1}' | sed -E 's/[0-9]+$//')

# Get detailed block device information using lsblk
# -d: no headings for devices (only disks)
# -n: no header line
# -o: output specific columns: NAME, SIZE, TYPE, MOUNTPOINT, VENDOR, MODEL, TRAN (transport)
# We filter for 'disk' type devices only.
while IFS= read -r line; do
    # Parse the output line into individual variables
    NAME=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    TYPE=$(echo "$line" | awk '{print $3}')
    MOUNTPOINT=$(echo "$line" | awk '{print $4}') # Can be empty
    VENDOR=$(echo "$line" | awk '{print $5}')
    MODEL=$(echo "$line" | awk '{print $6}')
    TRAN=$(echo "$line" | awk '{print $7}')

    # Only consider actual disk devices (not partitions, loop devices, etc.)
    if [[ "$TYPE" == "disk" ]]; then
        DEVICE_PATH="/dev/$NAME"
        DESCRIPTION="$SIZE - $VENDOR $MODEL ($TRAN)"

        # Check if this disk is likely a system drive
        # If the root device path starts with the current device path, it's a system drive.
        if [[ "$ROOT_DEV_PATH" == "$DEVICE_PATH"* ]]; then
            DESCRIPTION="!!! SYSTEM DRIVE !!! $DESCRIPTION"
            SYSTEM_DRIVES+=("$DEVICE_PATH")
        fi

        DRIVE_PATHS+=("$DEVICE_PATH")
        DRIVE_INFO+=("$(( ${#DRIVE_PATHS[@]} ))" "$DESCRIPTION")
    fi
done < <(lsblk -dn -o NAME,SIZE,TYPE,MOUNTPOINT,VENDOR,MODEL,TRAN 2>/dev/null)

# Check if any suitable drives were found
if [ ${#DRIVE_PATHS[@]} -eq 0 ]; then
    display_error_and_exit "No suitable disk drives found to write to."
fi

# Display a menu for drive selection
SELECTED_DRIVE_INDEX=$(whiptail --menu "Select the drive to write to (!!! WARNING: ALL DATA ON SELECTED DRIVE WILL BE ERASED !!!):" 25 78 15 "${DRIVE_INFO[@]}" 3>&1 1>&2 2>&3)

# Check if the user cancelled the selection
if [ -z "$SELECTED_DRIVE_INDEX" ]; then
    echo "Drive selection cancelled. Exiting."
    exit 0
fi

# Get the full path and description of the selected drive
SELECTED_DRIVE_PATH="${DRIVE_PATHS[$((SELECTED_DRIVE_INDEX-1))]}"
SELECTED_DRIVE_DESCRIPTION="${DRIVE_INFO[$(( (SELECTED_DRIVE_INDEX-1)*2 + 1 ))]}" # Get the description part from DRIVE_INFO

# --- 4. Confirm drive selection ---
CONFIRM_MESSAGE="You are about to write:\n\n"
CONFIRM_MESSAGE+="  Image: $(basename "$SELECTED_IMAGE_PATH")\n"
CONFIRM_MESSAGE+="  To Drive: $SELECTED_DRIVE_PATH\n"
CONFIRM_MESSAGE+="  Drive Info: $SELECTED_DRIVE_DESCRIPTION\n\n"
CONFIRM_MESSAGE+="!!! THIS WILL PERMANENTLY ERASE ALL DATA ON $SELECTED_DRIVE_PATH !!!\n\n"
CONFIRM_MESSAGE+="Are you absolutely sure you want to proceed?"

# Ask for final confirmation
if (whiptail --yesno "$CONFIRM_MESSAGE" 20 78 --title "CONFIRM WRITE OPERATION"); then
    echo "User confirmed the write operation."
else
    echo "Operation cancelled by user. Exiting."
    exit 0
fi

# --- Additional warning if a system drive was selected ---
IS_SYSTEM_DRIVE="false"
for sys_dev in "${SYSTEM_DRIVES[@]}"; do
    if [[ "$SELECTED_DRIVE_PATH" == "$sys_dev" ]]; then
        IS_SYSTEM_DRIVE="true"
        break
    fi
done

if [ "$IS_SYSTEM_DRIVE" == "true" ]; then
    if (whiptail --yesno "WARNING: You have selected a drive identified as a SYSTEM DRIVE ($SELECTED_DRIVE_PATH).\n\nWriting to this drive will likely make your system UNBOOTABLE and require a full reinstall.\n\nAre you ABSOLUTELY, POSITIVELY sure you want to proceed with writing to your system drive?" 20 78 --title "EXTREME DANGER: SYSTEM DRIVE SELECTED"); then
        echo "User confirmed writing to system drive."
    else
        echo "Operation cancelled due to system drive selection. Exiting."
        exit 0
    fi
fi

# --- 5. Execute the bzcat | dd command ---
echo "Starting image writing process..."
echo "Command: bzcat \"$SELECTED_IMAGE_PATH\" | sudo dd if=/dev/stdin of=\"$SELECTED_DRIVE_PATH\" oflag=sync status=progress bs=128M"

# Check for sudo availability
if ! command -v sudo &> /dev/null; then
    display_error_and_exit "Error: 'sudo' command not found. Please ensure sudo is installed and configured for your user."
fi

# Verify device exists and is accessible just before writing
if ! sudo test -b "$SELECTED_DRIVE_PATH"; then
    display_error_and_exit "Error: The selected device '$SELECTED_DRIVE_PATH' does not exist as a block device or is not accessible with sudo privileges. The device may have been disconnected or its name may have changed. Please check the device connection and try again."
fi

# Execute the command
# The pipe ensures bzcat's output is fed directly to dd's stdin.
# 'sudo' is applied to 'dd' as it requires root privileges to write to block devices.
if bzcat "$SELECTED_IMAGE_PATH" | sudo dd if=/dev/stdin of="$SELECTED_DRIVE_PATH" oflag=sync status=progress bs=128M; then
    whiptail --msgbox "Image writing completed successfully to $SELECTED_DRIVE_PATH!" 8 78
else
    display_error_and_exit "An error occurred during the image writing process. Check terminal for dd errors."
fi

echo "Script finished."
exit 0
