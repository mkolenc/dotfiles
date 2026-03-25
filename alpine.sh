#!/bin/sh
# setup-dwl.sh
# Run as ROOT after a fresh Alpine sys install.
# Lenovo ThinkPad T14 Gen1 AMD / Ryzen 5 Pro
#
# What this covers:
#   repos, eudev, dbus, seatd, AMD GPU firmware & Mesa,
#   ThinkPad-specific firmware (WiFi, BT, trackpad),
#   Wayland libraries, build tools, dwl (from source),
#   foot, bemenu, PipeWire + WirePlumber, bluez,
#   XDG_RUNTIME_DIR via pam-rundir, and a startdwl script.

set -e

# ── sanity check ──────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }

printf "Username for your daily account: "
read -r USER_NAME
id "$USER_NAME" > /dev/null 2>&1 || { echo "User '$USER_NAME' does not exist. Create it first with adduser."; exit 1; }

# ── 1. repos ─────────────────────────────────────────────────────────────────
# Enable community; edge/testing only for packages not yet in stable.
ALPINE_VER=$(cut -d. -f1,2 /etc/alpine-release)
cat > /etc/apk/repositories <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/community
EOF
apk update
apk upgrade

# ── 2. eudev + dbus ──────────────────────────────────────────────────────────
# eudev: udev-compatible device manager Alpine uses instead of systemd-udev.
# dbus: required by PipeWire, bluez, and most Wayland toolkits.
apk add eudev eudev-openrc dbus dbus-openrc
setup-devd udev
rc-update add udev sysinit
rc-update add udev-trigger sysinit
rc-update add dbus default
rc-service dbus start

# ── 3. seatd ─────────────────────────────────────────────────────────────────
# seatd mediates access to GPU and input devices without needing root.
# The user must be in the 'seat' group. Do NOT install elogind alongside it.
apk add seatd seatd-openrc
rc-update add seatd default
rc-service seatd start
addgroup "$USER_NAME" seat
# NOTE from Alpine wiki: "input and video groups are in most cases incorrect
# and insecure — the seat manager already provides the necessary permissions."

# ── 4. XDG_RUNTIME_DIR via pam-rundir ────────────────────────────────────────
# pam-rundir creates /run/user/<uid> on login with correct permissions.
# This is the right solution when not using elogind.
apk add pam-rundir

# ── 5. AMD GPU firmware + Mesa ───────────────────────────────────────────────
# T14 Gen1 AMD has Renoir (Ryzen 5 PRO 4650U) — uses amdgpu driver.
# mesa-dri-gallium provides the radeonsi Gallium3D driver for it.
# mesa-va-gallium: VA-API hardware video decode (useful for browser video).
apk add \
    linux-firmware-amdgpu \
    mesa-dri-gallium \
    mesa-va-gallium \
    mesa-vulkan-radeon \
    vulkan-loader

# ── 6. ThinkPad T14 AMD firmware ─────────────────────────────────────────────
# Intel AX200 WiFi/BT (this model ships with it despite being AMD).
# The trackpad and keyboard are I2C/PS2 — handled by libinput, no extra fw.
apk add \
    linux-firmware-other \
    linux-firmware-rtlwifi \
    linux-firmware-rtl_nic

# ── 7. Build tools (for dwl) ─────────────────────────────────────────────────
apk add \
    build-base \
    git \
    pkgconf \
    wayland-dev \
    wayland-protocols \
    wlroots-dev \
    libinput-dev \
    libxkbcommon-dev \
    pixman-dev \
    xcb-util-wm-dev \
    libdrm-dev

# ── 8. Wayland runtime libraries ─────────────────────────────────────────────
apk add \
    wayland \
    libxkbcommon \
    libinput \
    libdrm

# ── 9. foot + bemenu ─────────────────────────────────────────────────────────
apk add foot bemenu bemenu-wayland

# ── 10. PipeWire + WirePlumber ───────────────────────────────────────────────
# pipewire-pulse: PulseAudio compatibility layer (needed by Firefox, etc.)
# pipewire-spa-bluez: Bluetooth audio support.
# On Alpine 3.22+ these can run as OpenRC user services.
apk add \
    pipewire \
    pipewire-pulse \
    pipewire-pulse-openrc \
    pipewire-spa-bluez \
    wireplumber \
    wireplumber-openrc

# PipeWire needs realtime scheduling. Add user to pipewire group (PAM login).
addgroup "$USER_NAME" pipewire 2>/dev/null || true
# If rtkit is present instead, add to rtkit.
apk add rtkit 2>/dev/null && addgroup "$USER_NAME" rtkit 2>/dev/null || true

# Enable as OpenRC user services (Alpine 3.22+).
# These run under the user session, not as root.
rc-update -U add pipewire gui    2>/dev/null || true
rc-update -U add wireplumber gui 2>/dev/null || true
rc-update -U add pipewire-pulse gui 2>/dev/null || true

# ── 11. Bluetooth ─────────────────────────────────────────────────────────────
apk add bluez bluez-openrc
rc-update add bluetooth default
rc-service bluetooth start
addgroup "$USER_NAME" lp  # bluez requires lp group for rfcomm

# ── 12. doas ─────────────────────────────────────────────────────────────────
apk add doas
echo "permit persist :wheel" > /etc/doas.d/wheel.conf

# ── 13. Build dwl ────────────────────────────────────────────────────────────
# dwl must be built from source — the version must match the packaged wlroots.
# We check the installed wlroots version and checkout the matching dwl release.
WLROOTS_VER=$(apk info wlroots 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
echo "Installed wlroots: $WLROOTS_VER"

# Clone and build as the target user so the source lives in their home.
su - "$USER_NAME" -c "
    set -e
    mkdir -p ~/.local/src
    cd ~/.local/src

    if [ ! -d dwl ]; then
        git clone https://codeberg.org/dwl/dwl.git
    fi
    cd dwl

    # Check out the release whose wlroots requirement matches what's installed.
    # dwl v0.7 requires wlroots 0.18; v0.6 requires 0.17; etc.
    # Fetch tags so we can check them out.
    git fetch --tags

    # Use the latest release tag (safer than main which tracks wlroots-git).
    LATEST_TAG=\$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+$' | head -1)
    echo \"Checking out dwl \$LATEST_TAG\"
    git checkout \"\$LATEST_TAG\"

    # Copy default config so 'make' doesn't overwrite any future edits.
    cp config.def.h config.h

    make install
"

# ── 14. startdwl wrapper ─────────────────────────────────────────────────────
# This is what you type at the TTY to launch your session.
# It sets the required env vars and wraps dwl in dbus-run-session so that
# D-Bus (required by PipeWire, Firefox screensharing, etc.) works correctly.
#
# XDG_RUNTIME_DIR is already set by pam-rundir on login — we just verify it.
cat > /usr/local/bin/startdwl <<'SCRIPT'
#!/bin/sh
# startdwl — launch a dwl Wayland session from a TTY.
# Run this after logging in as your user. Do NOT run as root.

if [ -z "$XDG_RUNTIME_DIR" ]; then
    echo "ERROR: XDG_RUNTIME_DIR is not set."
    echo "Log out and back in so pam-rundir can set it, then try again."
    exit 1
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=dwl
export MOZ_ENABLE_WAYLAND=1          # Firefox native Wayland
export QT_QPA_PLATFORM=wayland       # Qt apps
export SDL_VIDEODRIVER=wayland       # SDL apps
export _JAVA_AWT_WM_NONREPARENTING=1 # Java GUI apps

# Start OpenRC user services (pipewire, wireplumber, pipewire-pulse).
# These are no-ops if already running.
openrc -U gui 2>/dev/null || true

# Launch dwl inside a dbus session.
# -s runs a startup command as a child of dwl (like .xinitrc for X11).
# Add your autostart commands there, e.g.: -s "foot &; dunst &"
exec dbus-run-session dwl -s 'foot --server <&-'
SCRIPT
chmod +x /usr/local/bin/startdwl

# ── Done ─────────────────────────────────────────────────────────────────────
cat <<EOF

Done. A few things to do before you reboot:

  1. Set a password if you haven't:
       passwd $USER_NAME

  2. Reboot so firmware, seatd, and pam-rundir take effect:
       reboot

After rebooting, log into a TTY as $USER_NAME and type:
       startdwl

dwl keybinds (default config.def.h):
  Super+Shift+Enter  → terminal (st by default — change in config.h)
  Super+Shift+Q      → close window
  Super+Shift+E      → quit dwl
  Super+1..9         → switch tag/workspace

To use foot as your terminal, edit config.h before building:
  ~/.local/src/dwl/config.h
  Change the termcmd line to: { "foot", NULL }
  Then: cd ~/.local/src/dwl && make && sudo install -Dm755 dwl /usr/local/bin/dwl

EOF
