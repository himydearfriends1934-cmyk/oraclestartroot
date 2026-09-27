#!/bin/bash
sudo -i << 'EOF'

# 1. 创建 root 密钥目录并从原账户复制密钥
mkdir -p /root/.ssh
cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/ 2>/dev/null || \
cp /home/opc/.ssh/authorized_keys /root/.ssh/ 2>/dev/null || \
cp /home/$SUDO_USER/.ssh/authorized_keys /root/.ssh/ 2>/dev/null

# 2. 剔除 Oracle 在 authorized_keys 中植入的登录拦截命令
sed -i 's/.*\(ssh-[^ ]* .*\)/\1/' /root/.ssh/authorized_keys

# 3. 设置严格的文件权限与 SELinux 上下文
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
restorecon -R -v /root/.ssh 2>/dev/null

# 4. 配置 SSH：仅允许 root 密钥登录，禁止密码登录
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null

# 5. 修改 cloud-init 配置，防止重启后重新锁死 root
sed -i 's/disable_root: true/disable_root: false/g' /etc/cloud/cloud.cfg 2>/dev/null
sed -i 's/disable_root: 1/disable_root: 0/g' /etc/cloud/cloud.cfg 2>/dev/null

# 6. 重启 SSH 服务使配置生效
systemctl restart sshd 2>/dev/null || systemctl restart ssh

EOF
