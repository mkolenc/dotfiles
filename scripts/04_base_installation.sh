#!/usr/bin/env bash

FLAG="$1"

if [[ "$FLAG" != "in_chroot" ]]; then
    echo "Running on main system"
    sleep 2

    cp "$0" /home/mkolenc/Downloads
    bash /home/mkolenc/Downloads/$0 in_chroot

    # Copy self to new system
    #cp "$0" "$CHROOT_DIR/root/install.sh"
    #chmod +x "$CHROOT_DIR/root/install.sh"

    # Run inside chroot with flag
    #xchroot "$CHROOT_DIR" /root/install.sh in_chroot

    echo "back in main system"
    sleep 2

    exit $?

fi

# === below here is code that runs inside chroot ===

echo "Running inside chroot — continuing install"
sleep 2

# your install steps:
# set hostname, locales, user, grub, etc.
