#!/usr/bin/env bash
set -e
source "$UTILS_PATH"

check_and_optimize_lba_format() {
    local nvme_dev="$1"

    msg "Checking optimal sector size for $nvme_dev"

    # Get the current and available LBA formats
    local nvme_output
    nvme_output=$(nvme id-ns -H "$nvme_dev" 2>/dev/null | grep "Relative Performance")
    if [ -z "$nvme_output" ]; then
        warn "Unable to detect LBA formats for $nvme_dev — skipping sector size optimization"
        return
    fi

    local current_line=$(echo "$nvme_output" | grep "(in use)")
    local current_lbaf=$(echo "$current_line" | grep -oP 'LBA Format\s+\K\d+')
    local current_size=$(echo "$current_line" | grep -oP 'Data Size:\s+\K[0-9]+')
    ok "Found current sector size: ${current_size} bytes (LBA Format ${current_lbaf})"

    local best_line=$(echo "$nvme_output" | sort -k17,17 | head -n1)
    local best_lbaf=$(echo "$best_line" | grep -oP 'LBA Format\s+\K\d+')
    local best_size=$(echo "$best_line" | grep -oP 'Data Size:\s+\K[0-9]+')
    ok "Found optimal sector size: ${best_size} bytes (LBA Format ${best_lbaf})"

    if [[ "$current_lbaf" == "$best_lbaf" ]]; then
        ok "Optimal sector size is already in use, skipping"
        return
    fi

    msg "Attempting to format $nvme_dev to ${best_size} sector size (from ${current_size})"
    if nvme format --lbaf="$best_lbaf" --force "$nvme_dev"; then
        ok "Successfully formatted $nvme_dev to optimal sector size (${best_size} bytes)"
    else
        warn "Unable to format $nvme_dev to optimal sector size — nothing to worry about, this is commonly not supported"
    fi
}

create_partition_table() {
    msg "Creating new GPT partition table"
    sgdisk --zap-all --clear "$DISK"
    sgdisk -o "$DISK"
    ok "New GPT table"
}

create_partitions() {
    msg "Creating partitions"
    sgdisk --set-alignment=2048 --align-end "$DISK"
    sgdisk --new=1::512M --typecode=1:EF00 --change-name=1:'EFI SYSTEM' "$DISK"
    ok "Created EFI system partition"

    if [[ -n "$SWAP_SIZE_GB" ]]; then
        sgdisk --new=2::-"$SWAP_SIZE_GB" --typecode=2::8300 --change-name=2:'LINUX ROOT' "$DISK"
        ok "Created root partition"
        sgdisk --new=3::-0 --typecode=3:8200 --change-name=3:'LINUX SWAP' "$DISK"
        ok "Created swap partition"
    else
        sgdisk --new=2::-0 --typecode=2::8300 --change-name=2:'LINUX ROOT' "$DISK"
        ok "Created root partition"
    fi

    # Refresh partition table
    partprobe "$DISK"
    sleep 1
}

format_partitions() {
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
    SWAP_PART="${DISK}p3"

    msg "Formatting EFI partition as FAT32..."
    mkfs.vfat -F32 -n "EFI SYSTEM" "$EFI_PART"
    ok "EFI formatted"

    msg "Formatting root partition as ext4..."
    mkfs.ext4 -F -L "LINUX ROOT" "$ROOT_PART"
    ok "Root formatted"

    if [[ -n "$SWAP_SIZE_GB" ]]; then
        msg "Formatting swap partition..."
        mkswap "$SWAP_PART"
        swapon "$SWAP_PART"
        ok "Swap enabled"
    fi
}

mount_partitions() {
    msg "Mounting the newly created partitions"
    mount -o defaults,noatime -t ext4 "$ROOT_PART" /mnt
    ok "Root mounted"

    mkdir -p /mnt/boot/efi
    mount -o defaults,noatime "$EFI_PART" /mnt/boot/efi
    ok "EFI mounted"
}

msg "Preparing disk for installation..."

if [[ -z "$DISK" ]]; then
    err "DISK variable not set. Aborting."
fi
ok "Target disk: $DISK"

check_and_optimize_lba_format "$DISK"
create_partition_table
create_partitions
format_partitions
mount_partitions

ok "Disk setup complete"
