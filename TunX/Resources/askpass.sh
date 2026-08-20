#!/bin/sh
# SSH_ASKPASS 助手：从临时文件读取密码或私钥口令并打印给 ssh。
# Created by glli
# ssh 在 askpass 非 0 退出时会丢弃已输出的口令；文件末尾无换行时 read 也会返回 1。
if [ ! -r "$TUNX_SSH_ASKPASS_FILE" ]; then
    exit 1
fi
IFS= read -r line < "$TUNX_SSH_ASKPASS_FILE" || true
printf '%s\n' "$line"
exit 0
