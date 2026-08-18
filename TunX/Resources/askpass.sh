#!/bin/sh
# SSH_ASKPASS 助手：从临时文件读取密码或私钥口令并打印给 ssh。
# Created by glli
if [ -r "$TUNX_SSH_ASKPASS_FILE" ]; then
    read -r line < "$TUNX_SSH_ASKPASS_FILE"
    printf '%s\n' "$line"
fi
