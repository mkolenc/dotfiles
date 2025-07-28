#!/usr/bin/env bash
set -e
source "$UTILS_PATH"

check_and_optimize_lba_format() {
    run_cmd "Fetching LBA formats for $DISK" \
        bash -o pipefail -c \
        'nvme id-ns -H "$1" | grep "Relative Performance"' _ "$DISK"

    local lba_formats=$(get_cmd_output)
    local current_format=$(grep "(in use)" <<< "$lba_formats")
    local current_lba_num=$(grep -oP "LBA Format\\s+\\K\\d+" <<< "$current_format")
    local current_lba_size=$(grep -oP "Data Size:\\s+\\K[0-9]+" <<< "$current_format")

    run_cmd "Finding optimal LBA format" \
        bash -o pipefail -c \
        'sort -k17,17 <<< "$1" | head -n1' _ "$lba_formats"

    local optimal_format=$(get_cmd_output)
    local optimal_lba_num=$(grep -oP "LBA Format\\s+\\K\\d+" <<< "$optimal_format")
    local optimal_lba_size=$(grep -oP "Data Size:\\s+\\K[0-9]+" <<< "$optimal_format")

    if [[ -z "$current_lba_num" || -z "$current_lba_size" || -z "$optimal_lba_num" || -z "$optimal_lba_size" ]]; then
        warn "Could not determine current or optimal LBA format — skipping format step"
        return
    fi

    if [[ "$current_lba_num" == "$optimal_lba_num" ]]; then
        ok "Optimal LBA format already in use (size: $current_lba_size)"
        return
    fi

    # Attempt to format the disk to the optimal LBA sector size.
    # Note: Some NVMe drives advertise formats that are not actually supported.
    # This is a common failure case — it should *not* abort the install process.
    if nvme format --lbaf="$optimal_lba_num" --force "$DISK" >/dev/null 2>&1; then
        ok "Successfully formatted $DISK to sector size $optimal_lba_size (was $current_lba_size)"
    else
        warn "Could not format $DISK to optimal sector size — this is a known limitation on some NVMe drives"
    fi
}

create_partition_table() {
    run_cmd "Wiping MBR and GPT data structures" \
        sgdisk --zap-all --clear "$DISK"

    run_cmd "Creating new GPT partition table" \
        sgdisk -o "$DISK"
}

create_partitions() {
    run_cmd "Setting disk alignment" \
        sgdisk --set-alignment=2048 --align-end "$DISK"

    run_cmd "Creating EFI system partition" \
        sgdisk --new=1::512M --typecode=1:EF00 --change-name=1:'EFI SYSTEM' "$DISK"

    run_cmd "Creating root partition" \
        sgdisk --new=2::-0 --typecode=2:8300 --change-name=2:'LINUX ROOT' "$DISK"

    run_cmd "Refreshing the partition table" \
        partprobe "$DISK" && sleep 1
}

format_partitions() {
    local EFI_PART="${DISK}p1"
    local ROOT_PART="${DISK}p2"

    run_cmd "Formatting EFI partition as FAT32" \
        mkfs.vfat -F32 -n "EFI SYSTEM" "$EFI_PART"

    run_cmd "Formatting root partition as ext4" \
        mkfs.ext4 -F -L "LINUX ROOT" "$ROOT_PART"
}

mount_partitions() {
    local EFI_PART="${DISK}p1"
    local ROOT_PART="${DISK}p2"
    local EFI_MOUNTPOINT="${CHROOT_DIR}/boot/efi"

    run_cmd "Mounting the root partition" \
        mount -o defaults,noatime -t ext4 "$ROOT_PART" "$CHROOT_DIR"

    run_cmd "Creating EFI directory $EFI_MOUNTPOINT" \
        mkdir -p "$EFI_MOUNTPOINT"

    run_cmd "Mounting the EFI partition" \
        mount -o defaults,noatime "$EFI_PART" "$EFI_MOUNTPOINT"
}

msg "Preparing disk for installation..."
check_vars_set DISK CHROOT_DIR

check_and_optimize_lba_format
create_partition_table
create_partitions
format_partitions
mount_partitions
