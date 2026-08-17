#!/bin/sh
if [ -r "$TUNX_SSH_ASKPASS_FILE" ]; then
    read -r line < "$TUNX_SSH_ASKPASS_FILE"
    printf '%s\n' "$line"
fi
