#!/bin/bash
# RackNerd 1GB KVM (Debian 13) 一键检查 + 优化 + 安全加固
# 用法: 在 ctrl 网页控制台以 root 身份执行, 或在自己电脑上 SSH 登录 root 后执行:
#   curl -sSL https://raw.githubusercontent.com/okrumi88-wq/free-resources/main/racknerd-vps-setup.sh | bash
# 安全用法(推荐): 先在自己电脑上生成自己的密钥对, 再把自己的公钥传进去跑,
#   这样脚本只会追加你的公钥、并在确认你有可用密钥后才关闭密码登录:
#   EXTRA_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" curl -sSL https://raw.githubusercontent.com/okrumi88-wq/free-resources/main/racknerd-vps-setup.sh | bash
# 安全原则(2026-11-23 修正, 旧版曾用 > 覆盖 authorized_keys 会清空已有密钥):
#   第 5 步只追加(>> 效果, 且去重), 绝不覆盖已有密钥;
#   第 6 步只在 EXTRA_PUBKEY 已提供时才关闭密码登录, 否则保留密码登录,
#   跑完先用自己的密钥另开终端验证能登录, 再手动关闭密码登录。
# 执行后: 仅密钥可登录 SSH (root 密码登录关闭, 仅当 EXTRA_PUBKEY 已提供时), 防火墙只放行 22 端口, fail2ban 开启。
# 如需恢复密码登录, 可在 ctrl 面板重置 root 密码后, 控制台执行:
#   sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && systemctl restart ssh
set -e
export DEBIAN_FRONTEND=noninteractive
# 调用者自己的公钥(可选, 但强烈建议提供): 传进来才会在第 6 步关闭密码登录。
EXTRA_PUBKEY="${EXTRA_PUBKEY:-}"

echo "=== 1. 系统信息 ==="
hostname; cat /etc/os-release | grep PRETTY_NAME
uptime; free -m; df -h /; nproc

echo "=== 2. 更新系统并安装工具 ==="
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq ufw fail2ban unattended-upgrades curl sudo vim htop

echo "=== 3. 时区设为 Asia/Singapore ==="
timedatectl set-timezone Asia/Singapore || true

echo "=== 4. 1GB swapfile (内存小, 防 OOM) ==="
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile
  grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
sysctl -w vm.swappiness=10 || true
grep -q vm.swappiness /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

echo "=== 5. 新建 rumi 用户 + 部署 SSH 密钥(只追加, 不覆盖) ==="
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOfwjzwi3fPADBWzRFV6TSkeAVacfd4Fyopqrxrzg6LJ rumi@racknerd-vps"
id -u rumi >/dev/null 2>&1 || useradd -m -s /bin/bash rumi
usermod -aG sudo rumi
mkdir -p /home/rumi/.ssh /root/.ssh
touch /home/rumi/.ssh/authorized_keys /root/.ssh/authorized_keys
# 只追加且去重: 已有密钥一律保留, 避免旧版 ">" 覆盖导致锁死。
for KEYFILE in /home/rumi/.ssh/authorized_keys /root/.ssh/authorized_keys; do
  grep -qxF "$PUBKEY" "$KEYFILE" || echo "$PUBKEY" >> "$KEYFILE"
  if [ -n "$EXTRA_PUBKEY" ]; then
    grep -qxF "$EXTRA_PUBKEY" "$KEYFILE" || echo "$EXTRA_PUBKEY" >> "$KEYFILE"
  fi
done
chmod 700 /home/rumi/.ssh /root/.ssh
chmod 600 /home/rumi/.ssh/authorized_keys /root/.ssh/authorized_keys
chown -R rumi:rumi /home/rumi/.ssh
# 保险: 两个文件都必须至少有一把密钥, 否则不往下走。
[ -s /home/rumi/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ] || { echo "ERROR: authorized_keys 为空, 中止"; exit 1; }

echo "=== 6. SSH 加固: 只在调用者提供了自己的公钥时才关闭密码登录 ==="
SSHD=/etc/ssh/sshd_config
cp -n "$SSHD" "${SSHD}.bak.$(date +%Y%m%d)" || true
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSHD"
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD"
if [ -n "$EXTRA_PUBKEY" ]; then
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD"
else
  echo "提示: 未提供 EXTRA_PUBKEY, 密码登录保持开启(安全默认)。"
  echo "请先用自己的密钥另开终端验证能登录, 再手动执行:"
  echo "  sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' $SSHD && systemctl restart ssh"
fi
grep -q '^PermitRootLogin' "$SSHD" || echo 'PermitRootLogin prohibit-password' >> "$SSHD"
if [ -n "$EXTRA_PUBKEY" ]; then
  grep -q '^PasswordAuthentication' "$SSHD" || echo 'PasswordAuthentication no' >> "$SSHD"
fi
sshd -t && (systemctl restart ssh || systemctl restart sshd)

echo "=== 7. 防火墙 UFW: 只放行 SSH 22 ==="
ufw allow 22/tcp || true
ufw --force enable || true

echo "=== 8. fail2ban + 自动安全更新 ==="
systemctl enable --now fail2ban || true
systemctl enable --now unattended-upgrades || true

echo "=== 9. 完成, 状态汇总 ==="
free -m; df -h /; swapon --show
ufw status verbose || true
fail2ban-client status sshd || true
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication)' || true
echo "DONE"
