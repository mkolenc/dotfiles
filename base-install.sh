#!/bin/bash

set -e

# Sanity check: running on Void Linux
if ! grep -qi 'void' /etc/os-release 2>/dev/null; then
    echo "Error: This script must be run on Void Linux."
    exit 1
fi

# Sanity check: running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# Sanity check: running on UEFI system
if [ ! -d /sys/firmware/efi/efivars ]; then
    echo "Error: No EFI variables found. This system does not appear to be booted in UEFI mode."
    exit 1
fi

# Auto-detect largest NVMe SSD
read DISK_NAME DISK_SIZE < <(lsblk --nvme -dno NAME,SIZE | sort -hk2 | tail -n1)
DISK="/dev/$DISK_NAME"

if [ -z "$DISK_NAME" ]; then
    echo "No NVMe SSD detected. Aborting."
    exit 1
fi

# Auto-detect timezone
TIMEZONE=$(curl -s https://ipinfo.io/timezone)
if [ -z "$TIMEZONE" ]; then
    echo "Failed to auto-detect timezone. Aborting."
    exit 1
fi

# === Interactive Configuration Section ===
# Prompt the user for libc choice, username, and password
while true; do
    clear
    read -rp "Which libc to use? (musl/glibc): " LIBC
    case "$LIBC" in
        musl|glibc) break ;;
        *) echo -e "\nPlease enter 'musl' or 'glibc'. Press enter to try again."; read ;;
    esac
done

clear
read -rp "Enter username: " USERNAME

while true; do
    clear
    echo "Enter password for user '$USERNAME'"
    read -rsp "Password: " PASSWORD
    echo
    read -rsp "Confirm password: " PASSWORD_CONFIRM
    echo
    if [ "$PASSWORD" = "$PASSWORD_CONFIRM" ]; then
        break
    else
        echo -e "\nPasswords do not match. Press enter to try again."
        read
    fi
done

clear
echo "===== Configuration Summary ====="
echo "LIBC:      $LIBC"
echo "DISK:      $DISK ($DISK_SIZE)"
echo "USERNAME:  $USERNAME"
echo "PASSWORD:  [HIDDEN]"
echo "TIMEZONE:  $TIMEZONE"
echo "================================="
read -rp "Proceed with these settings? (yes/no): " confirm
case "$confirm" in
    yes|YES|Yes|y|Y) ;;
    *) echo "Aborted."; exit 1 ;;
esac

clear
echo "!!! WARNING !!!"
echo "This will ERASE all data on $DISK and install Void Linux."
echo "Press Ctrl+C to cancel."
echo -n "Starting in "

for i in {10..1}; do
    echo -n "$i..."
    sleep 1
done
echo "now"
# === End of user input; starting automated installation ===

xbps-install -Syu xbps
xbps-install -Syu gptfdisk nvme-cli

# Ensure the nvme is using the optimal format
optimal_disk_format=$(nvme id-ns -H $DISK | grep "Relative Performance" | \
                      sort -k17,17 | \
                      head -n 1 | \
                      awk '{ print $3, $12 }')

read optimal_block_format optimal_sector_size <<< "$optimal_disk_format"
nvme format --force --lbaf=$optimal_block_format $DISK || echo "nvme format not supported, continuing..."

# Destroy the GPT and MBR data structres and set optimal alignment for SSD devices
sgdisk --zap-all --clear $DISK
sgdisk --set-alignment=2048 --align-end $DISK

# Standard partitioning
sgdisk --new=1::+512M --typecode=1:EF00 --change-name=1:'EFIBOOT' $DISK
sgdisk --new=2::-0 --typecode=2:8300 --change-name=2:'ROOT' $DISK
partprobe $DISK

mkfs.vfat -F32 -n 'EFIBOOT' ${DISK}p1
mkfs.ext4 -F -L 'ROOT' ${DISK}p2

mount -o defaults,noatime -t ext4 ${DISK}p2 /mnt
mount -o defaults,noatime --mkdir -t vfat ${DISK}p1 /mnt/boot/efi/

# Copy the RSA keys from the installation medium to the target root directory
mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

# Install base packages
REPO=https://repo-default.voidlinux.org/current
ARCH=$(uname -m)

if [ "$LIBC" = "musl" ]; then
    REPO="$REPO/musl"
    ARCH="$ARCH-musl"
fi

XBPS_ARCH=$ARCH xbps-install -S -r /mnt -R "$REPO" base-system
xgenfstab -U /mnt > /mnt/etc/fstab

# Configure the new system
xchroot /mnt LIBC="$LIBC" /bin/bash <<'EOF'

# Synchronize the hardware clock with the system clock
hwclock --systohc

# Set locales
echo "void" > /etc/hostname
echo 'HARDWARECLOCK="UTC"' > /etc/rc.conf
echo 'KEYMAP=us' >> /etc/rc.conf
echo 'LANG=en_US_UTF-8' > /etc/locale.conf

if [ "$LIBC" = "glibc" ]; then
    sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/default/libc-locales
    xbps-reconfigure -f glibc-locales
fi

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

# Set up a super user
useradd --create-home --groups wheel,audio,video,input,lp,kvm,users,xbuilder $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
passwd --lock root

# Install grub as the bootloader
xbps-install -S grub-x86_64-efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Void"

xbps-reconfigure -fa
EOF

sync
umount -R /mnt
echo 'Installation complete. You can now eject the installation media and reboot.'
