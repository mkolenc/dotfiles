#!/usr/bin/env bash
set -e

# Get the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/scripts" && pwd)"

export UTILS_PATH="$SCRIPT_DIR/utils.sh"
export DOWNLOAD_DIR="$SCRIPT_DIR/downloads"
mkdir -p "$DOWNLOAD_DIR"

# Run the installation
bash "$SCRIPT_DIR/01_sanity_checks.sh"
bash "$SCRIPT_DIR/02_download_installation_media.sh"
# bash "$SCRIPT_DIR/03_prepare_filesystems.sh"

