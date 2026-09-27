# Oracle Cloud (OCI) Root SSH Key Login

用于 Oracle Cloud Infrastructure (OCI) Compute 实例的一键 Root SSH 公钥登录配置脚本。

适用于常见的：

* Ubuntu
* Debian
* Oracle Linux
* RHEL 系 Linux

脚本会自动检测当前实例上的 SSH 公钥，并配置到 `root` 用户，同时调整 SSH 和 cloud-init 配置。

## ✨ 功能

* 🔑 自动检测当前实例已有的 `authorized_keys`
* 🔑 将 SSH 公钥配置到 `/root/.ssh/authorized_keys`
* 🧹 清理 OCI 镜像中常见的 `command="..."` Root 登录限制
* 🔒 设置 `PermitRootLogin prohibit-password`
* 🔒 禁用 SSH `PasswordAuthentication`
* 🛡️ 尝试调整 cloud-init 的 `disable_root`
* 🔐 自动修复 `/root/.ssh` 权限
* 🛡️ 支持 SELinux `restorecon`
* 💾 修改 SSH 配置前自动备份
* ✅ 重启 SSH 前执行 `sshd -t`
* 🚨 SSH 配置检查失败时尝试恢复原配置

## 🚀 一键运行

登录 OCI 实例默认用户，例如：

```text
ubuntu
```

或者：

```text
opc
```

执行：

```bash
curl -fsSL https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh | sudo bash
```

也可以先下载再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh -o root.sh
chmod +x root.sh
sudo ./root.sh
```

## 🔐 配置结果

执行成功后，SSH 的目标配置为：

```text
PermitRootLogin prohibit-password
PasswordAuthentication no
```

也就是说：

* `root` 可以通过 SSH 公钥登录
* `root` 不允许通过 SSH 密码登录
* SSH 密钥仍然使用 OpenSSH 标准认证机制

## 🔑 登录 Root

执行完成后，不要立即关闭当前 SSH 会话。

在本地另一台终端测试：

```bash
ssh root@YOUR_SERVER_IP
```

例如：

```bash
ssh root@1.2.3.4
```

如果使用指定私钥：

```bash
ssh -i ~/.ssh/id_rsa root@YOUR_SERVER_IP
```

确认 Root 登录正常后，再关闭原来的 SSH 会话。

## 🔍 检查 SSH 配置

可以执行：

```bash
sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication'
```

正常情况下应包含：

```text
permitrootlogin prohibit-password
passwordauthentication no
pubkeyauthentication yes
```

检查 SSH 配置语法：

```bash
sshd -t
```

如果没有输出，通常表示配置语法检查通过。

## 📂 Root SSH 文件

配置完成后：

```text
/root/.ssh/
/root/.ssh/authorized_keys
```

权限：

```text
/root/.ssh                 700
/root/.ssh/authorized_keys 600
```

## 🛡️ OCI command 限制

部分 OCI 镜像会在默认用户的 `authorized_keys` 中使用 OpenSSH key option，例如：

```text
command="..." ssh-rsa AAAA...
```

脚本会尝试移除 `command="..."` 限制，同时尽量保留其他 SSH key options。

例如：

```text
command="..." ssh-ed25519 AAAA...
```

会转换为：

```text
ssh-ed25519 AAAA...
```

## 💾 自动备份

脚本修改配置前会创建类似：

```text
/root/oci-root-ssh-backup-20260927-164800/
```

的备份目录。

其中可能包含：

```text
sshd_config.bak
sshd_config.d.bak/
cloud.cfg.bak
authorized_keys.<user>.bak
```

如果出现问题，可以利用当前 SSH 会话从备份恢复。

## ☁️ cloud-init

如果系统存在：

```text
/etc/cloud/cloud.cfg
```

脚本会检查：

```yaml
disable_root:
```

并尝试设置为：

```yaml
disable_root: false
```

不同 OCI 镜像的 cloud-init 配置可能不同，因此脚本不会假设所有镜像结构完全一致。

## ⚠️ 安全注意事项

开启 Root SSH 登录意味着：

```text
root
```

可以直接成为 SSH 登录用户。

因此建议：

1. 使用 SSH 公钥，不使用密码认证。
2. 使用强度足够的 SSH 私钥。
3. 不要共享私钥。
4. OCI Security List / NSG 尽量限制 TCP 22 的来源。
5. 第一次配置后不要立即关闭现有 SSH 会话。
6. 先从另一台终端确认 Root SSH 登录正常。

## ⚠️ 关于一键 curl | bash

如果你不希望直接执行远程脚本，可以先下载：

```bash
curl -fsSL https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh -o root.sh
```

检查：

```bash
less root.sh
```

然后：

```bash
chmod +x root.sh
sudo ./root.sh
```

这种方式更适合生产环境。

## 📌 支持情况

主要针对：

* Ubuntu OCI 官方镜像
* Oracle Linux OCI 官方镜像
* Debian OCI 镜像
* 其他采用标准 OpenSSH / systemd 的 Linux 系统

不同镜像的 SSH、cloud-init 和默认用户配置可能存在差异。

如果脚本无法自动检测当前用户，可以手动检查：

```bash
whoami
```

以及：

```bash
ls -la ~/.ssh/
```

## 📄 License

MIT
