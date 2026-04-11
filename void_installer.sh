#!/bin/bash
#      
# A custom void linux installer script.
# 
# Author: Max Kolenc
# Date: April 10, 2026

set -e

USERNAME=
USERCOMMENT=
PASSWORD=
HOSTNAME=
USERGROUPS=audio,video

KEYMAP=us
LOCALE=en_US.UTF-8
TIMEZONE=America/Vancouver # To be auto-detected

DISK=/dev/nvme0n1 # to be auto-detected
EFIPART="${DISK}p1"
ROOTPART="${DISK}p2"
LUKSNAME=crypt
MAPPER="/dev/mapper/${LUKSNAME}"

TARGETDIR=/mnt
EFIDIR="${TARGETDIR}/boot"
LOGFILE= # later

INSTALL_SUCCESS=1

trap "cleanup" INT TERM QUIT EXIT

cleanup() {
    umount -R "$TARGETDIR" 2>/dev/null || true
    if cryptsetup status -q "$MAPPER" > /dev/null 2>&1; then
        cryptsetup close "$LUKSNAME"
    fi
    return $INSTALL_SUCCESS
}

prompt_user() {
    clear
    printf '%s' "$1"
    read -r "$2"
}

get_user_info() {
    prompt_user 'Enter your username: ' USERNAME
    prompt_user 'Enter your display name: ' USERCOMMENT
    prompt_user 'Enter your hostname: ' HOSTNAME

    prompt_user 'Enter your password: ' PASSWORD
    prompt_user 'Again: ' password_confirm

    if [[ "$PASSWORD" != "$password_confirm" || -z "$PASSWORD" ]]; then
        exit 1
    fi
}

create_filesystems() {
    # Partition disk
    sgdisk -Z "$DISK"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI "$DISK"
    sgdisk -n 2:0:0     -t 2:8300 -c 2:root "$DISK"
    
    partprobe "$DISK"
    sleep 1

    # Setup LUKS
    printf '%s' "$PASSWORD" | cryptsetup luksFormat --key-file - -q "$ROOTPART"
    printf '%s' "$PASSWORD" | cryptsetup open --key-file - "$ROOTPART" "$LUKSNAME"

    # Format partitions
    mkfs.vfat -F32 "$EFIPART"
    mkfs.ext4 "$MAPPER"

    # Mount partitions
    mount "$MAPPER" "$TARGETDIR"
    mkdir -p "$EFIDIR"
    mount "$EFIPART" "$EFIDIR"

    # modprobe ext4 fat
}

mount_filesystems() {
    for fs in dev proc sys; do
        mkdir -p "${TARGETDIR}/${fs}"
        mount --rbind "/$fs" "${TARGETDIR}/${fs}"
        mount --make-rslave "${TARGETDIR}/${fs}"
    done
}

install_packages() {
    # Definitely want to config xbps here ourself. e.g. find
    # fastest mirror or whatever. For now we just copy everything

    # Copy xbps keys and xbps defaults
    mkdir -p "${TARGETDIR}/var/db/xbps/keys" "${TARGETDIR}/usr/share"
    cp -a /usr/share/xbps.d "${TARGETDIR}/usr/share/"
    cp /var/db/xbps/keys/*.plist "${TARGETDIR}/var/db/xbps/keys"

    stdbuf -oL env XBPS_ARCH=x86_64 \
        xbps-install  -r "$TARGETDIR" -SyU base-system cryptsetup limine
    xbps-reconfigure -r "$TARGETDIR" -f base-files
    stdbuf -oL chroot "$TARGETDIR" xbps-reconfigure -a 
}

write_fstab() {
    local efi_uuid root_uuid

    efi_uuid=$(blkid -s UUID -o value "$EFIPART")
    root_uuid=$(blkid -s UUID -o value "$MAPPER")

    # Note: <<- gets the her doc to ignore leading tabs (but not spaces)
    cat <<-EOF > "${TARGETDIR}/etc/fstab"
	# <file system>        <dir>   <type>  <options>                                                                           <dump> <pass>
	UUID=$root_uuid        /       ext4    rw,relatime                                                                          0      1
	UUID=$efi_uuid         /boot   vfat    rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8  0      2
	tmpfs                  /tmp    tmpfs   defaults,nosuid,nodev                                                                0      0
	EOF
    chmod 644 "${TARGETDIR}/etc/fstab"
}

set_keymap() {
    local rcconf="${TARGETDIR}/etc/rc.conf"

    if grep -q '^#\?KEYMAP=' "$rcconf"; then
        sed -i "s|^#\?KEYMAP=.*|KEYMAP=${KEYMAP}|" "$rcconf"
    else
        echo "KEYMAP=${KEYMAP}" >> "$rcconf"
    fi
}

set_locale() {
    # skip locale setup on musl (no libc-locales). This line is mainly
    # to remind me to get musl working on this script too
    [ -f "${TARGETDIR}/etc/default/libc-locales" ] || return 0

    # Set system locale
    echo "LANG=${LOCALE}" > "${TARGETDIR}/etc/locale.conf"

    # Uncomment locale in libc-locales and regenerate
    sed -i "/${LOCALE}/s/^#//" "${TARGETDIR}/etc/default/libc-locales"
    chroot "$TARGETDIR" xbps-reconfigure -f glibc-locales
}

set_timezone() {
    # Yes we are hardcoding this for now. No, we won't do this in the future
    # oh, can you tell im from vancouver?
    ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${TARGETDIR}/etc/localtime"
}

set_hostname() {
    echo "$HOSTNAME" > "${TARGETDIR}"/etc/hostname
}

set_rootpassword() {
    # set a super secret password for root
    echo "root:${PASSWORD}" | chroot "$TARGETDIR" chpasswd -c SHA512
}

set_useraccount() {
    # placeholder groups and names. probably need to do things
    # like set permissions for user e.g. sudo in the future
    chroot "$TARGETDIR" useradd -m -G "$USERGROUPS" \
        -c "$USERCOMMENT" "$USERNAME"
    echo "${USERNAME}:${PASSWORD}" | \
        chroot "$TARGETDIR" chpasswd -c SHA512
}

set_bootloader() {
    local luks_uuid
    luks_uuid=$(blkid -s UUID -o value "$ROOTPART")

    # Edit the crypttab (in target, not host)
    echo "$LUKSNAME  UUID=${luks_uuid}  none  luks" >> "${TARGETDIR}/etc/crypttab"

    # Configure dracut (in target, not host)
    mkdir -p "${TARGETDIR}/etc/dracut.conf.d"
    cat <<-EOF > "${TARGETDIR}/etc/dracut.conf.d/${LUKSNAME}.conf"
	hostonly=yes
	hostonly_cmdline=yes
	add_dracutmodules+=" ${LUKSNAME} "
	install_items+=" /etc/crypttab "
	EOF

    # Reconfigure to rebuild initramfs with LUKS support
    stdbuf -oL chroot "$TARGETDIR" xbps-reconfigure -fa

    # Copy limine EFI binary
    mkdir -p "${EFIDIR}/EFI/BOOT"
    cp "${TARGETDIR}/usr/share/limine/BOOTX64.EFI" "${EFIDIR}/EFI/BOOT/"

    # Remove stale GRUB and Limine entries. Even on a fresh install
    # some post-install scripts generate these. i guess grub is so ubiquitous
    # that some tools assume its getting installed?
    efibootmgr | grep -iE 'grub|limine' | grep -oP '(?<=Boot)[0-9A-F]{4}' | \
        xargs -r -I{} efibootmgr -q --delete-bootnum --bootnum {}

    efibootmgr --create \
        --disk "$DISK" \
        --part 1 \
        --label Limine \
        --loader /EFI/BOOT/BOOTX64.EFI

    # Configure limine. This is the kernel version. will want to write a hook
    # later to update this when the kernel is updated.
    local kver
    kver=$(ls "${EFIDIR}"/vmlinuz-* | sed "s|${EFIDIR}/vmlinuz-||")

    mkdir -p "${EFIDIR}/limine/"
    cat <<-EOF > "${EFIDIR}/limine/limine.conf"
	timeout: 3

	    /Void Linux
	    protocol: linux
	    kernel_path: boot():/vmlinuz-${kver}
	    module_path: boot():/initramfs-${kver}.img
	    cmdline: rd.luks.uuid=${luks_uuid} rd.luks.name=${luks_uuid}=${LUKSNAME} root=${MAPPER} rw quiet
	EOF
}

print_step() {
    clear
    echo "============================================="
    echo "$1"
    echo "============================================="
    echo ""
}

xbps-install -Syu xbps
xbps-install -y gptfdisk parted

get_user_info
print_step "create filesystems"
create_filesystems
print_step "mount filesystems"
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

# Copy /etc/skel files for root (unquoted glob so shell expands it)
cp "${TARGETDIR}"/etc/skel/.[bix]* "${TARGETDIR}/root"

# Clean up polkit rule. it's in the live system and i dont think we want it
rm -f "${TARGETDIR}/etc/polkit-1/rules.d/void-live.rules"

print_step "set bootloader"
set_bootloader

print_step "making sure everything is configured properly one more time"
stdbuf -oL chroot "$TARGETDIR" xbps-reconfigure -fa

sync && sync && sync
INSTALL_SUCCESS=0
