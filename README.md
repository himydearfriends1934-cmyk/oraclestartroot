# Oracle Cloud (OCI) 一键开启 Root 密钥登录脚本

专为 **Oracle Cloud (OCI)** 实例（Ubuntu / Oracle Linux / Debian 等）设计的一键配置脚本。自动解除 OCI 官方镜像对 `root` 用户 SSH 密钥登录的硬编码限制，实现安全的纯密钥登录。

---

## 🌟 核心功能

- 🔑 **自动同步密钥**：自动将当前默认用户（`ubuntu` / `opc` 等）的 SSH 授权公钥同步至 `/root/.ssh/authorized_keys`。
- 🚫 **彻底清除拦截**：自动清理 OCI 在公钥中植入的 `command="echo ..."` 登录拦截指令。
- 🔒 **SSH 安全强化**：配置仅允许 `root` 密钥登录 (`prohibit-password`)，同时禁用 SSH 密码连接。
- 🛡️ **Cloud-Init 防锁死**：修改 `cloud-init` 持久化配置，防止系统重启后重新禁用 `root` 账号。
- 📂 **修复 SELinux & 权限**：自动修正 SSH 目录权限，修复 Oracle Linux 环境下 SELinux 安全标签导致的连接拒绝。

---

## 🚀 一键安装运行

在实例的默认账户（如 `ubuntu` 或 `opc`）终端中，直接复制运行以下任意一行命令：

**使用 curl 命令：**
```bash
curl -sSL [https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh](https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh) | bash
