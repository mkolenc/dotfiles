#!/usr/bin/env bash
set -e
source "$UTILS"

msg "Fetching latest glibc x86_64 ROOTFS tarball info..."

BASE_URL="https://repo-default.voidlinux.org/live/current"
GITHUB_KEY_BASE="https://raw.githubusercontent.com/void-linux/void-packages/master/srcpkgs/void-release-keys/files"

# Get latest ROOTFS tarball name
tarball=$(curl -s "$BASE_URL/" | grep -oE 'void-x86_64-ROOTFS-[0-9]+\.tar\.xz' | sort -V | tail -n1)
date=$(echo "$tarball" | grep -oE '[0-9]{8}')

if [ -z "$tarball" ] || [ -z "$date" ]; then
    err "Error: Could not find latest tarball or extract date."
fi

ok "Found tarball: $tarball"
ok "Date extracted: $date"

# Move into DOWNLOAD_DIR if defined
if [[ -n "$DOWNLOAD_DIR" ]]; then
    pushd "$DOWNLOAD_DIR" > /dev/null
fi

msg "Downloading tarball and related files..."

curl -sS -O "$BASE_URL/$tarball"
ok "Downloaded tarball"

curl -sS -O "$BASE_URL/sha256sum.txt"
curl -sS -O "$BASE_URL/sha256sum.sig"
ok "Downloaded checksums"

# Fetch pubkey from GitHub
pub_key="void-release-${date}.pub"
pub_url="${GITHUB_KEY_BASE}/${pub_key}"

curl -sSfL "$pub_url" -o "$pub_key" || {
    err "Failed to download key: $pub_key"
}
ok "Downloaded public key: $pub_key"

msg "Verifying downloads..."

# Verify sha256sum.txt signature
if minisign -Vm sha256sum.txt -x sha256sum.sig -p "$pub_key" >/dev/null; then
    ok "Signature verified successfully."
else
    err "Signature verification failed."
fi

# Verify file integrity
if sha256sum -c --ignore-missing sha256sum.txt >/dev/null; then
    ok "Tarball integrity verified."
else
    err "Tarball checksum mismatch."
fi

# Restore previous directory
if [[ -n "$DOWNLOAD_DIR" ]]; then
    popd >/dev/null
fi

ok "All verifications passed for $tarball"

