#!/usr/bin/env bash
set -e
source "$UTILS_PATH"

check_and_optimize_lba_format() {
    run_cmd "Fetching LBA formats for $DISK" \
        bash -o pipefail -c \
        'nvme id-ns -H "$DISK" | grep "Relative Performance"'
    LBA_formats=$(<"$TMP_OUTPUT")

    run_cmd "Identifying active LBA format" \
        grep "(in use)" <<< "$LBA_formats"
    local curr_format=$(<"$TMP_OUTPUT")

    run_cmd "Extracting current LBA format number" \
	grep -oP "LBA Format\\s+\\K\\d+" <<< "$curr_format"
    local curr_LBA_num=$(<"$TMP_OUTPUT")

    run_cmd "Extracting current LBA data size" \
        grep -oP "Data Size:\\s+\\K[0-9]+" <<< "$curr_format"
    local curr_LBA_data_size=$(<"$TMP_OUTPUT")

    ok "Current sector size: $curr_LBA_data_size bytes (LBA Format $curr_LBA_num)"

    run_cmd "Finding optimal LBA format" \
        bash -o pipefail -c \
        'sort -k17,17 <<< "$1" | head -n1' _ "$LBA_formats"
    local optimal_format=$(<"$TMP_OUTPUT")

    run_cmd "Extracting optimal LBA format number" \
        grep -oP "LBA Format\\s+\\K\\d+" <<< "$optimal_format"
    local optimal_LBA_num=$(<"$TMP_OUTPUT")

    run_cmd "Extracting optimal LBA data size" \
        grep -oP "Data Size:\\s+\\K[0-9]+" <<< "$optimal_format"
    local optimal_LBA_data_size=$(<"$TMP_OUTPUT")

    ok "Optimal sector size: $optimal_LBA_data_size bytes (LBA Format $optimal_LBA_num)"

    if [[ "$curr_LBA_num" == "$optimal_LBA_num" ]]; then
        ok "Optimal sector size already in use, skipping format"
        return
    fi

    # Attempt to format the disk to the optimal LBA sector size.
    # Note: Some NVMe drives advertise formats that are not actually supported.
    # This is a common failure case — it should *not* abort the install process.
    if nvme format --lbaf="$optimal_LBA_num" --force "$DISK" >/dev/null 2>&1; then
        ok "Successfully formatted $DISK to sector size $optimal_LBA_data_size (was $curr_LBA_data_size)"
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
