#!/bin/bash
#      
# A custom void linux installer script.
# 
# Author: Max Kolenc
# Date: April 10, 2026

set -e

# DONE
create_filesystems() {
    # Parition disk
    sgdisk -Z /dev/nvme0n1
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI /dev/nvme0n1
    sgdisk -n 2:0:0     -t 2:8300 -c 2:root /dev/nvme0n1
    
    partprobe /dev/nvme0n1
    sleep 1

    # Setup LUKS
    printf '%s' '1234' | cryptsetup luksFormat --key-file - -q /dev/nvme0n1p2
    printf '%s' '1234' | cryptsetup open --key-file - /dev/nvme0n1p2 crypt

    # Format partitions
    mkfs.vfat -F32 /dev/nvme0n1p1
    mkfs.ext4 /dev/mapper/crypt

    # Mount partitions
    mount /dev/mapper/crypt /mnt
    mkdir -p /mnt/boot
    mount /dev/nvme0n1p1 /mnt/boot

    # modprobe ext4 fat
}

# DONE
mount_filesystems() {
    mkdir -p /mnt/{dev,proc,sys}
    for fs in dev proc sys; do
        mount --rbind "/$fs" "/mnt/$fs"
        mount --make-rslave "/mnt/$fs"
    done
}

# DONE
install_packages() {
    # Definitely want to config xbps here ourself. e.g. find
    # fastest mirror or whatever. For now we just copy everything

    # Copy xbpk keys and xbps defaults
    mkdir -p /mnt/var/db/xbps/keys /mnt/usr/share
    cp -a /usr/share/xbps.d /mnt/usr/share/
    cp /var/db/xbps/keys/*.plist /mnt/var/db/xbps/keys

    stdbuf -oL env XBPS_ARCH=x86_64 \
        xbps-install  -r /mnt -SyU base-system cryptsetup limine
    xbps-reconfigure -r /mnt -f base-files
    stdbuf -oL chroot /mnt xbps-reconfigure -a 
}

write_fstab() {
    local efi_uuid root_uuid

    efi_uuid=$(blkid -s UUID -o value /dev/nvme0n1p1)
    root_uuid=$(blkid -s UUID -o value /dev/mapper/crypt) # wrapper


    # Note: <<- gets the her doc to ignore leading tabs (but not spaces)
    cat <<-EOF > /mnt/etc/fstab
	# <file system>        <dir>   <type>  <options>                                                                           <dump> <pass>
	UUID=$root_uuid        /       ext4    rw,relatime                                                                          0      1
	UUID=$efi_uuid         /boot   vfat    rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8  0      2
	tmpfs                  /tmp    tmpfs   defaults,nosuid,nodev                                                                0      0
	EOF
    chmod 644 /mnt/etc/fstab
}

set_keymap() {
    local keymap='us'
    local rcconf="/mnt/etc/rc.conf"

    if grep -q '^#\?KEYMAP=' "$rcconf"; then
        sed -i "s|^#\?KEYMAP=.*|KEYMAP=$keymap|" "$rcconf"
    else
        echo "KEYMAP=$keymap" >> "$rcconf"
    fi
}

set_locale() {
    # skip locale setup on musl (no libc-locales). This line is mainly
    # to remind me to get musl working on this script too
    [ -f /mnt/etc/default/libc-locales ] || return 0

    local locale='en_US.UTF-8'

    # Set system locale
    echo "LANG=$locale" > /mnt/etc/locale.conf

    # Uncomment locale in libc-locales and regenerate
    sed -i "/${locale}/s/^#//" /mnt/etc/default/libc-locales
    chroot /mnt xbps-reconfigure -f glibc-locales
}

set_timezone() {
    # Yes we are hardcoding this for now. No, we won't do this in the future
    # oh, can you tell im from vancouver?
    ln -sf "/usr/share/zoneinfo/America/Vancouver" "/mnt/etc/localtime"
}

set_hostname() {
    echo "void" > /mnt/etc/hostname
}

set_rootpassword() {
    # set a super secret password for root
    echo "root:1234" | chroot /mnt chpasswd -c SHA512
}

set_useraccount() {
    # placeholder groups and names. probalby need to do things
    # like set permissions for user e.g. sudo in the future
    chroot /mnt useradd -m -G "wheel,audio,video" \
        -c "Void User" "voiduser"
    echo "voiduser:1234" | \
        chroot /mnt chpasswd -c SHA512
}

set_bootloader() {
    # Edit the crypttab
    local luks_uuid=$(blkid -s UUID -o value /dev/nvme0n1p2)
    echo "crypt  UUID="$luks_uuid"  none  luks" >> /etc/crypttab

    # configure dracut
    cat <<-EOF > /etc/dracut.conf.d/crypt.conf
    hostonly=yes
    hostonly_cmdline=yes
    add_dracutmodules+=" crypt "
    install_items+=" /etc/crypttab "
	EOF

    # Reconfigure initramfs? maybe. Not sure if needed again
    stdbuf -oL chroot /mnt xbps-reconfigure -fa

    # copy limine efi binary
    mkdir -p /mnt/boot/EFI/BOOT
    cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/EFI/BOOT/

    # Remove stale GRUB and Limine entries. Even on a fresh install
    # some post-install scripts generate these. i guess grub is so ubiquitious
    # that some tools assume its getting installed?
    efibootmgr | grep -iE 'grub|limine' | grep -oP '(?<=Boot)[0-9A-F]{4}' | \
        xargs -r -I{} efibootmgr -q --delete-bootnum --bootnum {}

    efibootmgr --create \
        --disk /dev/nvme0n1 \
        --part 1 \
        --label "Limine" \
        --loader /EFI/BOOT/BOOTX64.EFI

    # Configure limine. This is the kerenl version. will want to write a hook
    # later to update this when the kernal is updated.
    local kver=$(ls /mnt/boot/vmlinuz-* | sed 's|/mnt/boot/vmlinuz-||')

    mkdir -p /mnt/boot/limine/
    cat <<-EOF > /mnt/boot/limine/limine.conf
    timeout: 3

        /Void Linux
        protocol: linux
        kernel_path: boot():/vmlinuz-$kver
        module_path: boot():/initramfs-$kver.img
        cmdline: rd.luks.uuid=$luks_uuid rd.luks.name=$luks_uuid=crypt root=/dev/mapper/crypt rw quiet
	EOF
}

print_step() {
    clear
    echo "============================================="
    echo "$1"
    echo "============================================="
    echo ""
    sleep 2
}

xbps-install -Syu xbps
xbps-install -y gptfdisk parted

print_step "create filesystems"
create_filesystems
print_step "moutn filesystems"
mount_filesystems
print_step "install packages"
install_packages
print_step "write fstab"
write_fstab

# Basic configuration
print_step "set keymap"
set_keymap
print_step "set locale"
set_locale
print_step "set timezone"
set_timezone
print_step "set hostname"
set_hostname
print_step "set root password"
set_rootpassword
print_step "setup user"
set_useraccount

# Copy /etc/skel files for root.
cp /mnt/etc/skel/.[bix]* /mnt/root

# clean up polkit rule. it's in the live system and i dont think we want it
rm -f /mnt/etc/polkit-1/rules.d/void-live.rules

print_step "set bootloader"
set_bootloader

print_step "making sure everything is configured properly one more time"
stdbuf -oL chroot /mnt xbps-reconfigure -fa

sync && sync && sync
umount -R /mnt
cryptsetup close crypt # do we need this?