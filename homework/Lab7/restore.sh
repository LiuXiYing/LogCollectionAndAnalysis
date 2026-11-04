#!/usr/bin/env bash
# Lab7：清理攻击环境。默认只删除 attack.sh 创建的临时网络资源；
# 使用 --all 时额外还原选读部分可能改动的 PAM/faillock 配置并删除测试账号。
# 真实 /var/log/auth.log 和 Loki 中的日志不会被删除。
# 用法：sudo bash restore.sh [--all]
set -euo pipefail

LAB_NAME="Lab7"
NETNS_A="lab7-atk-a"
NETNS_B="lab7-atk-b"
VETH_A="lab7-veth-a"
VETH_B="lab7-veth-b"
PAM_SSHD="/etc/pam.d/sshd"
PAM_SSHD_BAK="/etc/pam.d/sshd.lab7.bak"
FAILLOCK_CONF="/etc/security/faillock.conf"
FAILLOCK_BAK="/etc/security/faillock.conf.lab7.bak"
TEST_USER="lab7target"

log() { printf '[%s] %s\n' "$LAB_NAME" "$*"; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 sudo 运行本脚本。" >&2
    exit 1
  fi
}

MODE="${1:-}"

need_root

ip netns del "$NETNS_A" 2>/dev/null || true
ip netns del "$NETNS_B" 2>/dev/null || true
ip link del "$VETH_A" 2>/dev/null || true
ip link del "$VETH_B" 2>/dev/null || true
ip addr del 127.0.0.2/8 dev lo 2>/dev/null || true
ip addr del 127.0.0.3/8 dev lo 2>/dev/null || true
log "已清理 Lab7 的 netns/veth/回环别名。"

if [ "$MODE" = "--all" ]; then
  if [ -f "$PAM_SSHD_BAK" ]; then
    cp -a "$PAM_SSHD_BAK" "$PAM_SSHD"
    rm -f "$PAM_SSHD_BAK"
    log "已还原 ${PAM_SSHD}。"
  fi
  if [ -f "$FAILLOCK_BAK" ]; then
    cp -a "$FAILLOCK_BAK" "$FAILLOCK_CONF"
    rm -f "$FAILLOCK_BAK"
    log "已还原 ${FAILLOCK_CONF}。"
  fi
  if id "$TEST_USER" >/dev/null 2>&1; then
    faillock --user "$TEST_USER" --reset 2>/dev/null || true
    userdel -r "$TEST_USER" 2>/dev/null || true
    log "已删除选读测试账号 ${TEST_USER}。"
  fi
fi

log "真实 auth.log 和 Loki 中的日志不会被删除——它们就是本次事件的审计证据。"
log "如需彻底回到实验前状态，请使用虚拟机快照。"
