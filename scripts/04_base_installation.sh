#!/usr/bin/env bash
set -e
source "$UTILS_PATH"

unpack_tarball_into_chroot() {
    run_cmd "Unpacking the tarball" \
        tar xJf "$DOWNLOAD_DIR/void-x86_64-ROOTFS-*.tar.xz" -C "$CHROOT_DIR"
}

install_base_system() {
    run_cmd "Updating the packages" \
        "$XTOOLS_DIR/xchroot" "$CHROOT_DIR" /bin/sh -e -c '
            xbps-install -Su -y xbps &&
            xbps-install -u -y
        '

    run_cmd "Installing the base system" \
        "$XTOOLS_DIR/xchroot" "$CHROOT_DIR" /bin/sh -e -c '
            xbps-install -y base-system &&
            xbps-remove -Ro -y base-container-full
        '
}

generate_fstab() {
    run_cmd "Writing the fstab" \
        "$XTOOLS_DIR/xgenfstab" -U "$CHROOT_DIR" > "$ROOT_DIR/etc/fstab"
}

msg "Installing Void on the new system..."
check_vars_set DOWNLOAD_DIR CHROOT_DIR XTOOLS_DIR

unpack_tarball_into_chroot
install_base_system
generate_fstab
