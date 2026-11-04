#!/usr/bin/env bash
# 仅恢复本实验备份的配置，不卸载软件、不删除日志或仪表盘数据。
set -euo pipefail
LAB_NAME="Lab5"
STATE_ROOT="${STATE_ROOT:-/opt/loglab-state}"
STATE_DIR="${STATE_ROOT}/${LAB_NAME}"
if [ "$(id -u)" -ne 0 ]; then echo "请使用 sudo 运行。" >&2; exit 1; fi
if [ ! -f "$STATE_DIR/backup.list" ]; then echo "没有可恢复的备份。"; exit 0; fi
systemctl stop alloy grafana-server loki
while IFS= read -r target; do
  key="$(printf '%s' "$target" | sed 's#/#__#g')"
  if [ -f "$STATE_DIR/backups/${key}.MISSING" ]; then
    rm -f -- "$target"
  elif [ -e "$STATE_DIR/backups/$key" ] || [ -L "$STATE_DIR/backups/$key" ]; then
    rm -f -- "$target"
    cp -a "$STATE_DIR/backups/$key" "$target"
  else
    echo "备份缺失，停止恢复：$target" >&2; exit 1
  fi
done < "$STATE_DIR/backup.list"
echo "平台服务已停止。重新搭建时依次运行 install.sh loki、alloy、grafana。"
echo "[$LAB_NAME] 配置已恢复；备份保留在 ${STATE_DIR}。"
