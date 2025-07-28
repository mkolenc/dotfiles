#!/usr/bin/env bash
set -e
source "$UTILS_PATH"

check_root() {
    run_cmd "Running as root" \
        test "$(id -u)" -eq 0
}

check_uefi() {
    run_cmd "Booted in UEFI mode" \
        test -d /sys/firmware/efi/efivars
}

check_arch() {
    run_cmd "Architecture is x86_64" \
        test "$(uname -m)" = "x86_64"
}

check_nvme_present() {
    run_cmd "NVMe device is present" \
        test -n "$(lsblk --nvme -n)"
}

check_network() {
    run_cmd "Network is up" \
        ping -c 1 -W 1 1.1.1.1
}

check_required_cmds() {
    local required_cmds=(curl sha256sum minisign nvme sgdisk partprobe mkfs.vfat mkfs.ext4)
    for cmd in "${required_cmds[@]}"; do
        run_cmd "'$cmd' command is available" \
            command -v "$cmd"
    done
}

msg "Running sanity checks..."

check_root
check_uefi
check_arch
check_nvme_present
check_network
check_required_cmds
