#!/bin/bash
# RackNerd 1GB KVM (Debian 13) 一键检查 + 优化 + 安全加固
# 用法: 在 ctrl 网页控制台以 root 身份执行:
#   curl -sSL https://raw.githubusercontent.com/okrumi88-wq/free-resources/main/racknerd-vps-setup.sh | bash
# 执行后: 仅密钥可登录 SSH (root 密码登录关闭), 防火墙只放行 22 端口, fail2ban 开启。
# 如需恢复密码登录, 可在 ctrl 面板重置 root 密码后, 控制台执行:
#   sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && systemctl restart ssh
set -e
export DEBIAN_FRONTEND=noninteractive

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

echo "=== 5. 新建 rumi 用户 + 部署 SSH 密钥 ==="
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOfwjzwi3fPADBWzRFV6TSkeAVacfd4Fyopqrxrzg6LJ rumi@racknerd-vps"
id -u rumi >/dev/null 2>&1 || useradd -m -s /bin/bash rumi
usermod -aG sudo rumi
mkdir -p /home/rumi/.ssh /root/.ssh
echo "$PUBKEY" > /home/rumi/.ssh/authorized_keys
echo "$PUBKEY" > /root/.ssh/authorized_keys
chmod 700 /home/rumi/.ssh /root/.ssh
chmod 600 /home/rumi/.ssh/authorized_keys /root/.ssh/authorized_keys
chown -R rumi:rumi /home/rumi/.ssh

echo "=== 6. SSH 加固: 只允许密钥登录 ==="
SSHD=/etc/ssh/sshd_config
cp -n "$SSHD" "${SSHD}.bak.$(date +%Y%m%d)" || true
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSHD"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD"
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD"
grep -q '^PermitRootLogin' "$SSHD" || echo 'PermitRootLogin prohibit-password' >> "$SSHD"
grep -q '^PasswordAuthentication' "$SSHD" || echo 'PasswordAuthentication no' >> "$SSHD"
sshd -t && systemctl restart ssh || systemctl restart sshd || true

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
