# OCI Root SSH Setup

Configure SSH public-key login for the `root` user on Oracle Cloud Infrastructure (OCI) Linux instances.

## 🚀 Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh | sudo bash
```

> ⚠️ **Important:** Keep your current SSH session open while running the script.
> Open a **second terminal** and verify that `root` SSH login works before closing the existing session.

```bash
ssh root@YOUR_SERVER_IP
```

---

## What This Script Does

* Detects the existing OCI/default user
* Copies the user's `authorized_keys` to `/root/.ssh/authorized_keys`
* Removes the OCI `command="..."` SSH key restriction
* Enables root SSH public-key login
* Disables SSH password authentication
* Optionally configures cloud-init
* Fixes SSH key permissions
* Restores SELinux context when available
* Creates backups before making changes
* Validates the SSH configuration with `sshd -t`
* Restarts the SSH service only after successful validation

---

## Recommended Installation

For additional safety, download and inspect the script before executing it:

### 1. Download

```bash
curl -fsSL https://raw.githubusercontent.com/himydearfriends1934-cmyk/oraclestartroot/main/root.sh -o /tmp/root.sh
```

### 2. Inspect

```bash
less /tmp/root.sh
```

### 3. Check syntax

```bash
bash -n /tmp/root.sh
```

### 4. Run

```bash
sudo bash /tmp/root.sh
```

---

## Verify SSH Configuration

After the script completes:

```bash
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication) '
```

Expected:

```text
permitrootlogin prohibit-password
passwordauthentication no
pubkeyauthentication yes
```

Some older OpenSSH versions may display:

```text
permitrootlogin without-password
```

`without-password` is the legacy equivalent of `prohibit-password`.

You can also run:

```bash
sshd -t
```

No output means the SSH configuration syntax is valid.

---

## Test Root Login

From a **second terminal**:

```bash
ssh root@YOUR_SERVER_IP
```

If you use a custom private-key path:

```bash
ssh -i /path/to/private_key root@YOUR_SERVER_IP
```

**Do not close the original SSH session until this test succeeds.**

---

## Security Notes

The script disables SSH password authentication:

```text
PasswordAuthentication no
```

Make sure you have a working SSH public/private key pair before running the script.

Keep your existing SSH connection open until root public-key login has been successfully tested.

---

## Backups

The script creates a backup directory similar to:

```text
/root/oci-root-ssh-backup-YYYYMMDD-HHMMSS
```

Backups may include:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/
/etc/cloud/cloud.cfg
```

The original user's `authorized_keys` is also backed up.

---

## Troubleshooting

### Check SSH configuration

```bash
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication) '
```

### Validate SSH configuration

```bash
sshd -t
```

### Check SSH service

```bash
systemctl status sshd
```

or:

```bash
systemctl status ssh
```

### Check SSH logs

```bash
journalctl -u sshd -n 100 --no-pager
```

or:

```bash
journalctl -u ssh -n 100 --no-pager
```

### Check root SSH permissions

```bash
ls -ld /root/.ssh
ls -l /root/.ssh/authorized_keys
```

Expected:

```text
/root/.ssh                  700
/root/.ssh/authorized_keys  600
```

---

## Requirements

* Linux with OpenSSH server
* Root or `sudo` access
* Existing SSH public-key authentication
* Bash
* Standard Linux utilities

Primarily intended for Oracle Cloud Infrastructure (OCI) Linux instances.

---

## License

Use at your own risk.

Always review the script before running it on a production server.
