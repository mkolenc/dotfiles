#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/scripts" && pwd)"
export UTILS="$SCRIPT_DIR/utils.sh"
export DOWNLOAD_DIR="$SCRIPT_DIR/downloads"
mkdir -p "$DOWNLOAD_DIR"

bash "$SCRIPT_DIR/01_sanity_checks.sh"
bash "$SCRIPT_DIR/02_download_installation_media.sh"

