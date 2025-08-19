#!/bin/sh
# Ran by dwl on startup

pipewire &
wireplumber &

# Dwl writes layout/title/app-id info to this script's stdin for status bars.
# If we don't read it, dwl blocks--so close stdin.
exec <&-
