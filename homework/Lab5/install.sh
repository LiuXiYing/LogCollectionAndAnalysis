#!/usr/bin/env bash
# Lab5：软件统一安装，三个组件分步配置。Ubuntu 教学虚拟机使用。
# 用法：sudo bash install.sh packages|loki|alloy|grafana
# 不传参数时仅显示帮助；配置备份位于 /opt/loglab-state/Lab5。
set -euo pipefail

LAB_NAME="Lab5"
STATE_ROOT="${STATE_ROOT:-/opt/loglab-state}"
STATE_DIR="${STATE_ROOT}/${LAB_NAME}"
GRAFANA_APT_URL="https://mirrors.tuna.tsinghua.edu.cn/grafana/apt"

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

packages() {
# ---------- ① 基础包 + Grafana 清华 TUNA 镜像源 ----------
log "① 安装基础包并添加 Grafana 清华 TUNA 镜像源……"
# 重跑旧版脚本时，先替换已写入的官方源，再刷新索引。
if [ -f /etc/apt/sources.list.d/grafana.list ]; then
  sed -i "s|https://apt.grafana.com|${GRAFANA_APT_URL}|g" /etc/apt/sources.list.d/grafana.list
fi
apt-get update
apt-get install -y ca-certificates apt-transport-https software-properties-common wget gpg curl nginx rsyslog logrotate
mkdir -p /etc/apt/keyrings
if [ ! -s /etc/apt/keyrings/grafana.gpg ]; then
  # 镜像提供软件包，签名公钥仍从 Grafana 官方获取；失败时不留下空密钥文件。
  local key_tmp
  key_tmp="$(mktemp)"
  if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 https://apt.grafana.com/gpg.key \
    | gpg --batch --dearmor > "$key_tmp"; then
    rm -f "$key_tmp"
    echo "获取 Grafana 签名公钥失败，请检查网络后重试。" >&2
    return 1
  fi
  install -m 0644 "$key_tmp" /etc/apt/keyrings/grafana.gpg
  rm -f "$key_tmp"
fi
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] ${GRAFANA_APT_URL} stable main" > /etc/apt/sources.list.d/grafana.list

# ---------- ② 安装三大件 ----------
log "② 从清华 TUNA 镜像安装 grafana / loki / alloy……"
apt-get update
apt-get install -y grafana loki alloy
systemctl enable --now rsyslog

}

loki() {
# ---------- ③ Loki 配置（存储端） ----------
local loki_group
# 软件包可能创建 loki 用户，却使用其他主组，不能假定组名也是 loki。
if ! loki_group="$(id -gn loki 2>/dev/null)"; then
  echo "未找到 loki 服务用户，请先确认 Loki 软件包已正确安装。" >&2
  return 1
fi
log "③ 写入 /etc/loki/config.yml……"
mkdir -p /etc/loki
backup_path /etc/loki/config.yml
cat > /etc/loki/config.yml <<'EOF'
auth_enabled: false
server:
  http_listen_port: 3100
common:
  instance_addr: 127.0.0.1
  ring:
    kvstore:
      store: inmemory
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
ruler:
  alertmanager_url: http://localhost:9093
EOF

install -d -o loki -g "$loki_group" /var/lib/loki /var/lib/loki/chunks /var/lib/loki/rules
systemctl enable --now loki
systemctl restart loki
}

alloy() {
# ---------- ④ Alloy 配置（采集端） ----------
log "④ 写入 /etc/alloy/config.alloy……"
mkdir -p /etc/alloy
backup_path /etc/alloy/config.alloy
cat > /etc/alloy/config.alloy <<'EOF'
loki.write "local" {
  endpoint {
    url = "http://127.0.0.1:3100/loki/api/v1/push"
  }
}

loki.source.file "linux_logs" {
  targets = [
    {"__path__" = "/var/log/syslog", "job" = "syslog", "host" = constants.hostname},
    {"__path__" = "/var/log/auth.log", "job" = "auth", "host" = constants.hostname},
    {"__path__" = "/var/log/nginx/access.log", "job" = "nginx_access", "host" = constants.hostname},
    {"__path__" = "/var/log/nginx/error.log", "job" = "nginx_error", "host" = constants.hostname},
  ]
  forward_to = [loki.write.local.receiver]
  file_match {
    enabled = true
  }
}
EOF

usermod -aG adm alloy
systemctl enable --now alloy
systemctl restart alloy
}

grafana() {
# ---------- ⑤ Grafana 数据源预配置 ----------
log "⑤ 预配 Grafana 的 Loki 数据源……"
mkdir -p /etc/grafana/provisioning/datasources
backup_path /etc/grafana/provisioning/datasources/loki.yml
cat > /etc/grafana/provisioning/datasources/loki.yml <<'EOF'
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://127.0.0.1:3100
    isDefault: true
EOF

systemctl enable --now grafana-server
systemctl restart grafana-server
}

case "${1:-help}" in
  packages|loki|alloy|grafana)
    need_root
    "$1"
    log "阶段 $1 完成，请按实验文档验证后再继续。"
    ;;
  help|--help|-h)
    echo "用法：sudo bash install.sh packages|loki|alloy|grafana"
    ;;
  *) echo "未知阶段：$1" >&2; exit 2 ;;
esac
