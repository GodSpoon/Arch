#!/bin/bash

SD_DEV="/dev/sda"
SD_PART="/dev/sda1"

echo "=== 1. S.M.A.R.T. info (if supported) ==="
sudo smartctl -a "$SD_DEV" || echo "S.M.A.R.T. not supported on this device."

echo
echo "=== 2. File system check and repair (fsck) ==="
echo "Unmounting $SD_PART (ignore errors if already unmounted)..."
sudo umount "$SD_PART"
sudo fsck -y "$SD_PART"

echo
echo "=== 3. Read/Write speed test (dd, non-destructive) ==="
MOUNT_POINT="/mnt/sdtest"
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$SD_PART" "$MOUNT_POINT"
echo "Write speed test:"
sudo dd if=/dev/zero of="$MOUNT_POINT/testfile" bs=100M count=1 oflag=dsync && sync
echo "Read speed test:"
sudo dd if="$MOUNT_POINT/testfile" of=/dev/null bs=100M count=1 iflag=dsync && sync
sudo rm "$MOUNT_POINT/testfile"
sudo umount "$MOUNT_POINT"

echo
echo "=== 4. Bad sector scan (badblocks, non-destructive read-only) ==="
sudo badblocks -sv "$SD_DEV"

echo
echo "All tests completed."
