#!/usr/bin/env bash
set -e
source "$UTILS"

msg "Fetching latest glibc x86_64 ROOTFS tarball info..."

BASE_URL="https://repo-default.voidlinux.org/live/current"
GITHUB_KEY_BASE="https://raw.githubusercontent.com/void-linux/void-packages/master/srcpkgs/void-release-keys/files"

# Get latest ROOTFS tarball name
TARBALL=$(curl -s "$BASE_URL/" | grep -oE 'void-x86_64-ROOTFS-[0-9]+\.tar\.xz' | sort -V | tail -n1)
DATE=$(echo "$TARBALL" | grep -oE '[0-9]{8}')

if [ -z "$TARBALL" ] || [ -z "$DATE" ]; then
    err "Error: Could not find latest tarball or extract date."
fi

ok "Found tarball: $TARBALL"
ok "Date extracted: $DATE"

# Download files
msg "Downloading tarball and related files..."
pushd "$DOWNLOAD_DIR" >/dev/null

curl -sS -O "$BASE_URL/$TARBALL"
ok "Downloaded tarball"

curl -sS -O "$BASE_URL/sha256sum.txt"
curl -sS -O "$BASE_URL/sha256sum.sig"
ok "Downloaded checksums"

# Fetch pubkey from GitHub
PUB_KEY="void-release-${DATE}.pub"
PUB_URL="${GITHUB_KEY_BASE}/${PUB_KEY}"

curl -sSfL "$PUB_URL" -o "$PUB_KEY" || {
    err "Failed to download key: $PUB_KEY"
}
ok "Downloaded public key: $PUB_KEY"

msg "Verifying downloads..."

# Verify sha256sum.txt signature
if minisign -Vm sha256sum.txt -x sha256sum.sig -p "$PUB_KEY" >/dev/null; then
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

ok "All verifications passed for $TARBALL"
popd >/dev/null

