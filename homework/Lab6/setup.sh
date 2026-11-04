#!/usr/bin/env bash
# Lab6：配置 8080 演示站。先完成 Lab5 软件安装与采集配置。
set -euo pipefail

LAB_NAME="Lab6"
STATE_ROOT="${STATE_ROOT:-/opt/loglab-state}"
STATE_DIR="${STATE_ROOT}/${LAB_NAME}"

log() { printf '[%s] %s\n' "$LAB_NAME" "$*"; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 运行本脚本。" >&2
    exit 1
  fi
}

safe_key() { printf '%s' "$1" | sed 's#/#__#g'; }

backup_path() {
  local target="$1" key
  key="$(safe_key "$target")"
  mkdir -p "$STATE_DIR/backups"
  if [ -e "$STATE_DIR/backups/${key}" ] || [ -L "$STATE_DIR/backups/${key}" ] || [ -e "$STATE_DIR/backups/${key}.MISSING" ]; then
    return
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    cp -a "$target" "$STATE_DIR/backups/${key}"
  else
    : > "$STATE_DIR/backups/${key}.MISSING"
  fi
  printf '%s\n' "$target" >> "$STATE_DIR/backup.list"
}


need_root
command -v nginx >/dev/null || { echo "请先完成 Lab5 软件安装。" >&2; exit 1; }
systemctl is-active --quiet alloy || { echo "请先恢复 Lab5 的 Alloy 服务。" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
backup_path /etc/nginx/sites-available/loglab-demo.conf
backup_path /etc/nginx/sites-enabled/loglab-demo.conf
install -m 0644 "$SCRIPT_DIR/nginx-demo.conf" /etc/nginx/sites-available/loglab-demo.conf
ln -sfn /etc/nginx/sites-available/loglab-demo.conf /etc/nginx/sites-enabled/loglab-demo.conf
nginx -t
systemctl enable --now nginx
systemctl restart nginx
for path in / /api/ok /api/missing /admin; do
  case "$path" in /|/api/ok) expected=200 ;; *) expected=404 ;; esac
  code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080${path}")
  if [ "$code" != "$expected" ]; then
    log "$path 预期 ${expected}，实际 ${code}，请检查站点配置。"
    exit 1
  fi
done

log "演示站已准备好。请验证 / 与 /api/ok 为 200，/api/missing 与 /admin 为 404。"
