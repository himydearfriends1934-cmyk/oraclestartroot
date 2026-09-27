# Oracle Cloud (OCI) 一键开启 Root 密钥登录脚本

专为 **Oracle Cloud (OCI)** 实例（Ubuntu / Oracle Linux / Debian 等）设计的一键配置脚本。自动解除 OCI 官方镜像对 `root` 用户密钥登录的限制与硬编码拦截，实现安全的纯密钥登录。

---

## 🌟 脚本功能

- 🔑 **同步授权公钥**：自动获取当前默认用户（`ubuntu` / `opc` 等）的 SSH 授权密钥并同步至 `root` 目录。
- 🚫 **解除 Oracle 拦截**：自动剔除 OCI 在 `authorized_keys` 中植入的 `command="echo ..."` 登录拦截指令。
- 🔒 **SSH 强化配置**：配置仅允许 `root` 密钥登录（`prohibit-password`），同时禁用密码登录，保障绝对安全。
- 🛡️ **Cloud-Init 防重置**：修改 `cloud-init` 持久化配置，防止服务器重启后 `root` 账户被系统重新锁死。
- 📂 **权限与 SELinux 修复**：自动矫正 SSH 目录权限，并修复 Oracle Linux 环境下的 SELinux 安全标签。

---

## 🚀 一键使用

在实例的默认账户（如 `ubuntu` 或 `opc`）终端中，直接复制粘贴并运行以下命令：

```bash
curl -sSL [https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh](https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh) | bash
