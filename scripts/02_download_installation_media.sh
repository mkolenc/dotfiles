#!/usr/bin/env bash
set -e
source "$UTILS_PATH"

BASE_URL="https://repo-default.voidlinux.org/live/current"
GITHUB_KEY_BASE="https://raw.githubusercontent.com/void-linux/void-packages/master/srcpkgs/void-release-keys/files"

ROOTFS_TARBALL=""
PUBLIC_KEY=""

fetch_latest_tarball() {
    run_cmd "Fetching latest ROOTFS tarball name" \
        bash -o pipefail -c \
        "curl -sf '$BASE_URL/' | grep -oE 'void-x86_64-ROOTFS-[0-9]+\.tar\.xz' | sort -V | tail -n1"

    ROOTFS_TARBALL=$(<"$TMP_OUTPUT")
}

change_to_download_dir() {
    run_cmd "Moving into $DOWNLOAD_DIR" \
        pushd "$DOWNLOAD_DIR"
}

download_files() {
    local ROOTFS_TARBALL_date=$(echo "$ROOTFS_TARBALL" | grep -oE '[0-9]{8}')
    PUBLIC_KEY="void-release-${ROOTFS_TARBALL_date}.pub"
    local public_key_url="${GITHUB_KEY_BASE}/${PUBLIC_KEY}"

    run_cmd "Download tarball" \
        curl -sS -O "$BASE_URL/$ROOTFS_TARBALL"
    run_cmd "Download sha256sum.txt" \
        curl -sS -O "$BASE_URL/sha256sum.txt"
    run_cmd "Download sha256sum.sig" \
        curl -sS -O "$BASE_URL/sha256sum.sig"
    run_cmd "Download public key: $PUBLIC_KEY" \
        curl -sSL "$public_key_url" -o "$PUBLIC_KEY"
}

verify_signature() {
    run_cmd "Verify signature of sha256sum.txt" \
        minisign -Vm sha256sum.txt -x sha256sum.sig -p "$PUBLIC_KEY"
}

verify_checksum() {
    run_cmd "Verify tarball checksum" \
        sha256sum -c --ignore-missing sha256sum.txt
}

restore_previous_dir() {
    run_cmd "Returning to working directory" \
        popd
}

msg "Starting ROOTFS tarball fetch and verification..."
check_vars_set DOWNLOAD_DIR

fetch_latest_tarball
change_to_download_dir
download_files
verify_signature
verify_checksum
restore_previous_dir
