#!/usr/bin/env bash
set -e
source "$UTILS"

msg "Running sanity checks..."

if [[ $(id -u) -ne 0 ]]; then
    err "Must be run as root."
fi
ok "Running as root"

if [[ ! -d /sys/firmware/efi/efivars ]]; then
    err "System not booted in UEFI mode."
fi
ok "UEFI mode confirmed"

ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    err "Unsupported architecture: $ARCH. Only x86_64 is supported."
fi
ok "Architecture: $ARCH"

# Ensure we have internet
if ping -q -c 1 -W 1 1.1.1.1 &>/dev/null; then
    ok "Network is up"
else
    err "No internet connection. Aborting."
fi

# Check for required commands
REQUIRED_CMDS=(curl sha256sum minisign nvme sgdisk partprobe mkfs.vfat mkfs.ext4 mkswap swapon mount)
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Missing required command: $cmd"
    fi
done
ok "Required disk tools present"

ok "All sanity checks passed"

