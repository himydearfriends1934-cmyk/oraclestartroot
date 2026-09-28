#!/usr/bin/env bash

set -Eeuo pipefail

BACKUP_DIR="/root/oci-root-ssh-backup-$(date +%Y%m%d-%H%M%S)"

log() {
    echo
    echo "[+] $*"
}

warn() {
    echo
    echo "[!] $*" >&2
}

die() {
    echo
    echo "[ERROR] $*" >&2
    exit 1
}

# ============================================================
# Root check
# ============================================================

if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

echo "============================================================"
echo " OCI Root SSH Key Login Configurator"
echo "============================================================"
echo

# ============================================================
# Backup directory
# ============================================================

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

log "Backup directory: $BACKUP_DIR"

# ============================================================
# Detect source user
# ============================================================

SOURCE_USER=""
SOURCE_AUTHORIZED_KEYS=""

# If executed through sudo, SUDO_USER is usually the original user.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then

    if [[ -f "/home/${SUDO_USER}/.ssh/authorized_keys" ]]; then
        SOURCE_USER="${SUDO_USER}"
        SOURCE_AUTHORIZED_KEYS="/home/${SUDO_USER}/.ssh/authorized_keys"
    fi

fi

# Try common OCI/Linux users.
if [[ -z "$SOURCE_AUTHORIZED_KEYS" ]]; then

    for user in \
        ubuntu \
        opc \
        debian \
        ec2-user \
        admin \
        rocky \
        almalinux
    do

        if [[ -f "/home/${user}/.ssh/authorized_keys" ]]; then
            SOURCE_USER="${user}"
            SOURCE_AUTHORIZED_KEYS="/home/${user}/.ssh/authorized_keys"
            break
        fi

    done

fi

if [[ -z "$SOURCE_AUTHORIZED_KEYS" ]]; then
    die "Could not find a user's authorized_keys file."
fi

if [[ ! -s "$SOURCE_AUTHORIZED_KEYS" ]]; then
    die "Source authorized_keys exists but is empty."
fi

log "Source user: $SOURCE_USER"
log "Source key file: $SOURCE_AUTHORIZED_KEYS"

# ============================================================
# Backup source authorized_keys
# ============================================================

cp -a \
    "$SOURCE_AUTHORIZED_KEYS" \
    "$BACKUP_DIR/authorized_keys.${SOURCE_USER}.bak"

# ============================================================
# Backup SSH configuration
# ============================================================

if [[ -f /etc/ssh/sshd_config ]]; then
    cp -a \
        /etc/ssh/sshd_config \
        "$BACKUP_DIR/sshd_config.bak"
fi

if [[ -d /etc/ssh/sshd_config.d ]]; then
    cp -a \
        /etc/ssh/sshd_config.d \
        "$BACKUP_DIR/sshd_config.d.bak"
fi

if [[ -f /etc/cloud/cloud.cfg ]]; then
    cp -a \
        /etc/cloud/cloud.cfg \
        "$BACKUP_DIR/cloud.cfg.bak"
fi

# ============================================================
# Prepare /root/.ssh
# ============================================================

log "Preparing /root/.ssh"

install \
    -d \
    -m 700 \
    -o root \
    -g root \
    /root/.ssh

# ============================================================
# Copy authorized_keys
# ============================================================

log "Copying authorized_keys to root"

cp -f \
    "$SOURCE_AUTHORIZED_KEYS" \
    /root/.ssh/authorized_keys

# ============================================================
# Remove OCI command="..." restriction
# ============================================================
#
# OCI public keys can look like:
#
# command="echo Please login as the user..." ssh-rsa AAAA...
#
# or:
#
# command="..." ssh-ed25519 AAAA...
#
# This removes the command option while keeping the actual
# SSH public key.
#
# This version intentionally does NOT use Perl.
# ============================================================

log "Cleaning OCI command restrictions"

CLEANED_KEYS="/root/.ssh/authorized_keys.cleaned"

sed -E \
    's/^command="[^"]*"[[:space:]]*,?[[:space:]]*//' \
    "$SOURCE_AUTHORIZED_KEYS" \
    > "$CLEANED_KEYS"

if [[ ! -s "$CLEANED_KEYS" ]]; then
    rm -f "$CLEANED_KEYS"
    die "Key cleanup produced an empty authorized_keys file."
fi

mv -f \
    "$CLEANED_KEYS" \
    /root/.ssh/authorized_keys

# Remove blank lines.
sed -i '/^[[:space:]]*$/d' /root/.ssh/authorized_keys

# ============================================================
# Root SSH permissions
# ============================================================

chown root:root /root/.ssh
chown root:root /root/.ssh/authorized_keys

chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

# ============================================================
# SELinux
# ============================================================

if command -v restorecon >/dev/null 2>&1; then

    log "Restoring SELinux context"

    restorecon \
        -RF \
        /root/.ssh \
        >/dev/null 2>&1 || true

fi

# ============================================================
# Check sshd
# ============================================================

SSHD_CONFIG="/etc/ssh/sshd_config"

if [[ ! -f "$SSHD_CONFIG" ]]; then
    die "Cannot find $SSHD_CONFIG"
fi

SSHD_BIN=""

if command -v sshd >/dev/null 2>&1; then
    SSHD_BIN="$(command -v sshd)"
elif [[ -x /usr/sbin/sshd ]]; then
    SSHD_BIN="/usr/sbin/sshd"
fi

if [[ -z "$SSHD_BIN" ]]; then
    die "sshd binary not found."
fi

log "Using SSH daemon: $SSHD_BIN"

# ============================================================
# Configure main sshd_config
# ============================================================

log "Configuring SSH"

# Remove existing PermitRootLogin directives.
sed -i -E \
    '/^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+/d' \
    "$SSHD_CONFIG"

# Remove existing PasswordAuthentication directives.
sed -i -E \
    '/^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+/d' \
    "$SSHD_CONFIG"

cat >> "$SSHD_CONFIG" <<'EOF'

# ============================================================
# OCI Root SSH Key Login
# Managed by oci-root-ssh
# ============================================================

PermitRootLogin prohibit-password
PasswordAuthentication no
EOF

# ============================================================
# Configure sshd_config.d
# ============================================================

if [[ -d /etc/ssh/sshd_config.d ]]; then

    log "Checking SSH drop-in configuration"

    while IFS= read -r -d '' file; do

        # Do not modify our own generated file here.
        if [[ "$file" == "/etc/ssh/sshd_config.d/99-oci-root-ssh.conf" ]]; then
            continue
        fi

        # Remove conflicting directives.
        sed -i -E \
            '/^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+/d' \
            "$file" \
            2>/dev/null || true

        sed -i -E \
            '/^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+/d' \
            "$file" \
            2>/dev/null || true

    done < <(
        find \
            /etc/ssh/sshd_config.d \
            -maxdepth 1 \
            -type f \
            -name '*.conf' \
            -print0
    )

    # Create a final drop-in.
    cat > /etc/ssh/sshd_config.d/99-oci-root-ssh.conf <<'EOF'
# ============================================================
# OCI Root SSH Key Login
# Managed by oci-root-ssh
# ============================================================

PermitRootLogin prohibit-password
PasswordAuthentication no
EOF

fi

# ============================================================
# cloud-init
# ============================================================

if [[ -f /etc/cloud/cloud.cfg ]]; then

    log "Checking cloud-init configuration"

    if grep -Eq \
        '^[[:space:]]*disable_root[[:space:]]*:' \
        /etc/cloud/cloud.cfg
    then

        sed -i -E \
            's/^[[:space:]]*disable_root[[:space:]]*:.*/disable_root: false/' \
            /etc/cloud/cloud.cfg

    else

        warn "disable_root was not found in cloud.cfg."
        warn "Leaving cloud-init configuration unchanged."

    fi

else

    warn "/etc/cloud/cloud.cfg not found."
    warn "Skipping cloud-init configuration."

fi

# ============================================================
# Validate SSH configuration BEFORE restart
# ============================================================

log "Validating SSH configuration"

if ! "$SSHD_BIN" -t; then

    warn "sshd -t FAILED."
    warn "Restoring previous SSH configuration."

    if [[ -f "$BACKUP_DIR/sshd_config.bak" ]]; then

        cp -af \
            "$BACKUP_DIR/sshd_config.bak" \
            /etc/ssh/sshd_config

    fi

    if [[ -d "$BACKUP_DIR/sshd_config.d.bak" ]]; then

        rm -rf /etc/ssh/sshd_config.d

        cp -a \
            "$BACKUP_DIR/sshd_config.d.bak" \
            /etc/ssh/sshd_config.d

    fi

    if [[ -f "$BACKUP_DIR/cloud.cfg.bak" ]]; then

        cp -af \
            "$BACKUP_DIR/cloud.cfg.bak" \
            /etc/cloud/cloud.cfg

    fi

    "$SSHD_BIN" -t || true

    die "SSH configuration was invalid. Original SSH configuration was restored."

fi

log "sshd configuration syntax is valid."

# ============================================================
# Show effective configuration
# ============================================================

log "Effective SSH configuration"

EFFECTIVE_CONFIG="$(
    "$SSHD_BIN" -T 2>/dev/null || true
)"

echo "$EFFECTIVE_CONFIG" |
    grep -E \
        '^(permitrootlogin|passwordauthentication|pubkeyauthentication) ' \
    || true

echo

# ============================================================
# Verify important settings
# ============================================================

if echo "$EFFECTIVE_CONFIG" |
    grep -q '^permitrootlogin prohibit-password$'
then

    echo "[OK] PermitRootLogin = prohibit-password"

else

    warn "Effective PermitRootLogin is not prohibit-password."

fi

if echo "$EFFECTIVE_CONFIG" |
    grep -q '^passwordauthentication no$'
then

    echo "[OK] PasswordAuthentication = no"

else

    warn "Effective PasswordAuthentication is not no."

fi

if echo "$EFFECTIVE_CONFIG" |
    grep -q '^pubkeyauthentication yes$'
then

    echo "[OK] PubkeyAuthentication = yes"

else

    warn "Effective PubkeyAuthentication is not yes."

fi

# ============================================================
# Restart SSH service
# ============================================================

SSH_SERVICE=""

if systemctl list-unit-files 2>/dev/null |
    grep -q '^sshd\.service'
then

    SSH_SERVICE="sshd"

elif systemctl list-unit-files 2>/dev/null |
    grep -q '^ssh\.service'
then

    SSH_SERVICE="ssh"

fi

if [[ -z "$SSH_SERVICE" ]]; then

    warn "Could not determine SSH service name."
    warn "SSH configuration was validated but the service was not restarted."

else

    log "Restarting SSH service: $SSH_SERVICE"

    if ! systemctl restart "$SSH_SERVICE"; then

        die "Failed to restart $SSH_SERVICE. Keep this SSH session open."

    fi

    if ! systemctl is-active --quiet "$SSH_SERVICE"; then

        die "$SSH_SERVICE is not active after restart."

    fi

    log "SSH service is active."

fi

# ============================================================
# Final permissions
# ============================================================

chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

chown root:root /root/.ssh
chown root:root /root/.ssh/authorized_keys

if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF /root/.ssh >/dev/null 2>&1 || true
fi

# ============================================================
# Complete
# ============================================================

echo
echo "============================================================"
echo " Configuration completed successfully"
echo "============================================================"
echo
echo "Root SSH key:"
echo "  /root/.ssh/authorized_keys"
echo
echo "SSH settings:"
echo "  PermitRootLogin prohibit-password"
echo "  PasswordAuthentication no"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "IMPORTANT:"
echo "  DO NOT close this SSH session yet."
echo
echo "Open another terminal and test:"
echo
echo "  ssh root@YOUR_SERVER_IP"
echo
echo "After root login succeeds, you can close this session."
echo "============================================================"
