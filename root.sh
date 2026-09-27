```bash
#!/usr/bin/env bash

# ============================================================
# OCI Root SSH Key Login Configurator
#
# Supported:
#   Ubuntu / Debian / Oracle Linux / RHEL-like systems
#
# Features:
#   - Backup SSH configuration before modification
#   - Detect the current login user automatically
#   - Copy the user's authorized_keys to root
#   - Remove OCI-style command="..." login restriction
#   - Configure PermitRootLogin prohibit-password
#   - Disable SSH PasswordAuthentication
#   - Update cloud-init root restriction where applicable
#   - Fix permissions and SELinux context
#   - Validate sshd configuration BEFORE restarting SSH
#
# IMPORTANT:
#   Keep the current SSH session open until root login has
#   been successfully tested from another terminal.
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="oci-root-ssh"
BACKUP_DIR="/root/${SCRIPT_NAME}-backup-$(date +%Y%m%d-%H%M%S)"

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

cleanup_on_error() {
    local rc=$?

    echo
    echo "[ERROR] Script failed with exit code ${rc}."
    echo "[ERROR] Your current SSH session has NOT been intentionally closed."
    echo "[ERROR] Backups are available at:"
    echo "        ${BACKUP_DIR}"
    echo

    exit "$rc"
}

trap cleanup_on_error ERR

# ------------------------------------------------------------
# 1. Root check
# ------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

echo "============================================================"
echo " OCI Root SSH Key Login Configurator"
echo "============================================================"
echo
echo "Backup directory:"
echo "  ${BACKUP_DIR}"
echo

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

# ------------------------------------------------------------
# 2. Detect OS
# ------------------------------------------------------------

OS_ID=""
OS_VERSION=""

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
fi

log "Detected OS: ${OS_ID} ${OS_VERSION}"

# ------------------------------------------------------------
# 3. Detect current SSH/login user
# ------------------------------------------------------------

CURRENT_USER="${SUDO_USER:-}"

if [[ -z "${CURRENT_USER}" || "${CURRENT_USER}" == "root" ]]; then
    CURRENT_USER=""

    # Try SSH connection information first.
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        # SSH_CONNECTION contains:
        # client_ip client_port server_ip server_port
        :
    fi

    # Fall back to common OCI users.
    for candidate in ubuntu opc debian ec2-user admin rocky almalinux; do
        if id "${candidate}" >/dev/null 2>&1 &&
           [[ -f "/home/${candidate}/.ssh/authorized_keys" ]]; then
            CURRENT_USER="${candidate}"
            break
        fi
    done
fi

# ------------------------------------------------------------
# 4. Find authorized_keys source
# ------------------------------------------------------------

SOURCE_AUTHORIZED_KEYS=""

if [[ -n "${CURRENT_USER}" ]]; then
    candidate="/home/${CURRENT_USER}/.ssh/authorized_keys"

    if [[ -f "${candidate}" ]]; then
        SOURCE_AUTHORIZED_KEYS="${candidate}"
    fi
fi

# If automatic detection failed, search common home directories.
if [[ -z "${SOURCE_AUTHORIZED_KEYS}" ]]; then
    for candidate in \
        /home/ubuntu/.ssh/authorized_keys \
        /home/opc/.ssh/authorized_keys \
        /home/debian/.ssh/authorized_keys \
        /home/admin/.ssh/authorized_keys \
        /home/ec2-user/.ssh/authorized_keys
    do
        if [[ -f "${candidate}" ]]; then
            SOURCE_AUTHORIZED_KEYS="${candidate}"
            CURRENT_USER="$(basename "$(dirname "$(dirname "${candidate}")")")"
            break
        fi
    done
fi

if [[ -z "${SOURCE_AUTHORIZED_KEYS}" ]]; then
    die "Could not find a source authorized_keys file."
fi

log "Source user: ${CURRENT_USER}"
log "Source key file: ${SOURCE_AUTHORIZED_KEYS}"

# ------------------------------------------------------------
# 5. Validate source key file
# ------------------------------------------------------------

if [[ ! -s "${SOURCE_AUTHORIZED_KEYS}" ]]; then
    die "Source authorized_keys exists but is empty."
fi

# Backup source key.
cp -a \
    "${SOURCE_AUTHORIZED_KEYS}" \
    "${BACKUP_DIR}/authorized_keys.${CURRENT_USER}.bak"

# ------------------------------------------------------------
# 6. Backup root SSH configuration
# ------------------------------------------------------------

mkdir -p "${BACKUP_DIR}/ssh"

if [[ -f /etc/ssh/sshd_config ]]; then
    cp -a \
        /etc/ssh/sshd_config \
        "${BACKUP_DIR}/ssh/sshd_config.bak"
fi

if [[ -d /etc/ssh/sshd_config.d ]]; then
    cp -a \
        /etc/ssh/sshd_config.d \
        "${BACKUP_DIR}/sshd_config.d.bak"
fi

if [[ -f /etc/cloud/cloud.cfg ]]; then
    cp -a \
        /etc/cloud/cloud.cfg \
        "${BACKUP_DIR}/cloud.cfg.bak"
fi

# ------------------------------------------------------------
# 7. Create root SSH directory
# ------------------------------------------------------------

log "Preparing /root/.ssh"

mkdir -p /root/.ssh

chmod 700 /root/.ssh
chown root:root /root/.ssh

# ------------------------------------------------------------
# 8. Copy authorized_keys
# ------------------------------------------------------------

log "Copying SSH public keys to root"

cp -f \
    "${SOURCE_AUTHORIZED_KEYS}" \
    /root/.ssh/authorized_keys

chown root:root /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# ------------------------------------------------------------
# 9. Remove OCI command="..." restriction
#
# We only remove the command option at the beginning of a key
# entry. Other SSH options are intentionally preserved.
#
# Example:
#
# command="echo Please login as the user opc..." ssh-rsa AAAA...
#
# becomes:
#
# ssh-rsa AAAA...
#
# If a line contains:
#
# from="1.2.3.4",command="..." ssh-ed25519 AAAA...
#
# it becomes:
#
# from="1.2.3.4" ssh-ed25519 AAAA...
#
# ------------------------------------------------------------

log "Cleaning OCI command restrictions from authorized_keys"

CLEANED_KEYS="/root/.ssh/authorized_keys.cleaned"

if command -v perl >/dev/null 2>&1; then

    perl -pe '
        # Remove an OpenSSH command="..." option.
        # Handles escaped characters inside double quotes.
        s/(^|,)\s*command="(?:\\.|[^"\\])*"\s*,?/$1/;
        s/^\s*,//;
        s/,\s+ssh-/ ssh-/;
        s/,\s+(ecdsa-|sk-|ssh-)/ $1/;
    ' \
    /root/.ssh/authorized_keys > "${CLEANED_KEYS}"

else

    warn "perl is not installed; using conservative fallback."

    # Conservative fallback:
    # Only remove a command option when it is the first option.
    sed -E \
        's/^command="([^"\\]|\\.)*"[, ]+//' \
        /root/.ssh/authorized_keys > "${CLEANED_KEYS}"
fi

if [[ ! -s "${CLEANED_KEYS}" ]]; then
    die "Key cleanup produced an empty authorized_keys file."
fi

mv -f "${CLEANED_KEYS}" /root/.ssh/authorized_keys

chown root:root /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# ------------------------------------------------------------
# 10. Remove accidental duplicate blank lines
# ------------------------------------------------------------

sed -i '/^[[:space:]]*$/d' /root/.ssh/authorized_keys

# ------------------------------------------------------------
# 11. SELinux context
# ------------------------------------------------------------

if command -v restorecon >/dev/null 2>&1; then
    log "Restoring SELinux context"
    restorecon -RF /root/.ssh >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------
# 12. Configure SSH
# ------------------------------------------------------------

SSHD_CONFIG="/etc/ssh/sshd_config"

if [[ ! -f "${SSHD_CONFIG}" ]]; then
    die "Cannot find ${SSHD_CONFIG}"
fi

log "Configuring SSH"

# Remove active or commented duplicate global directives from
# the main configuration.
#
# We then append our explicit settings.
#
# This is intentionally limited to the two directives we own.

sed -i \
    -E \
    '/^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+/d' \
    "${SSHD_CONFIG}"

sed -i \
    -E \
    '/^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+/d' \
    "${SSHD_CONFIG}"

cat >> "${SSHD_CONFIG}" <<'EOF'

# ============================================================
# OCI Root SSH Key Login
# Managed by oci-root-ssh
# ============================================================

PermitRootLogin prohibit-password
PasswordAuthentication no

EOF

# ------------------------------------------------------------
# 13. Deal with sshd_config.d
#
# Remove conflicting global directives from drop-in files.
# We do NOT delete arbitrary SSH configuration.
# ------------------------------------------------------------

if [[ -d /etc/ssh/sshd_config.d ]]; then

    while IFS= read -r -d '' file; do

        # Skip our own potential generated file.
        [[ "${file}" == */99-oci-root-ssh.conf ]] && continue

        # Remove only the directives controlled by this script.
        sed -i \
            -E \
            '/^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+/d' \
            "${file}" 2>/dev/null || true

        sed -i \
            -E \
            '/^[[:space:]]*#?[[:space:]]*PasswordAuthentication[[:space:]]+/d' \
            "${file}" 2>/dev/null || true

    done < <(find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name '*.conf' -print0)
fi

# ------------------------------------------------------------
# 14. Configure cloud-init
# ------------------------------------------------------------

if [[ -f /etc/cloud/cloud.cfg ]]; then

    log "Checking cloud-init root configuration"

    # Replace common forms:
    #
    # disable_root: true
    # disable_root: 1
    #
    # with:
    #
    # disable_root: false
    #

    if grep -Eq '^[[:space:]]*disable_root:' /etc/cloud/cloud.cfg; then

        sed -i \
            -E \
            's/^[[:space:]]*disable_root:[[:space:]]*.*/disable_root: false/' \
            /etc/cloud/cloud.cfg

    else

        cat >> /etc/cloud/cloud.cfg <<'EOF'

# Allow root SSH access configured by oci-root-ssh.
disable_root: false
EOF

    fi

else
    warn "/etc/cloud/cloud.cfg not found; skipping cloud-init configuration."
fi

# ------------------------------------------------------------
# 15. Find sshd binary
# ------------------------------------------------------------

SSHD_BIN=""

if command -v sshd >/dev/null 2>&1; then
    SSHD_BIN="$(command -v sshd)"
elif [[ -x /usr/sbin/sshd ]]; then
    SSHD_BIN="/usr/sbin/sshd"
fi

if [[ -z "${SSHD_BIN}" ]]; then
    die "sshd binary not found."
fi

log "Using SSH daemon: ${SSHD_BIN}"

# ------------------------------------------------------------
# 16. Validate SSH configuration
# ------------------------------------------------------------

log "Validating SSH configuration"

if ! "${SSHD_BIN}" -t; then

    warn "sshd configuration validation FAILED."
    warn "Restoring previous SSH configuration."

    if [[ -f "${BACKUP_DIR}/ssh/sshd_config.bak" ]]; then
        cp -af \
            "${BACKUP_DIR}/ssh/sshd_config.bak" \
            /etc/ssh/sshd_config
    fi

    if [[ -d "${BACKUP_DIR}/sshd_config.d.bak" ]]; then
        rm -rf /etc/ssh/sshd_config.d

        cp -a \
            "${BACKUP_DIR}/sshd_config.d.bak" \
            /etc/ssh/sshd_config.d
    fi

    die "SSH configuration was invalid. Original configuration restored."
fi

log "SSH configuration syntax is valid."

# ------------------------------------------------------------
# 17. Show effective SSH configuration
# ------------------------------------------------------------

log "Effective SSH settings"

EFFECTIVE_CONFIG="$("${SSHD_BIN}" -T 2>/dev/null || true)"

echo "${EFFECTIVE_CONFIG}" | grep -E \
    '^(permitrootlogin|passwordauthentication|pubkeyauthentication) ' \
    || true

# ------------------------------------------------------------
# 18. Verify required settings
# ------------------------------------------------------------

if ! echo "${EFFECTIVE_CONFIG}" |
    grep -q '^permitrootlogin prohibit-password$'
then
    warn "Effective PermitRootLogin is not prohibit-password."
    warn "The system may have another SSH configuration source."
fi

if ! echo "${EFFECTIVE_CONFIG}" |
    grep -q '^passwordauthentication no$'
then
    warn "Effective PasswordAuthentication is not no."
    warn "The system may have another SSH configuration source."
fi

# ------------------------------------------------------------
# 19. Fix permissions one more time
# ------------------------------------------------------------

chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

chown root:root /root/.ssh
chown root:root /root/.ssh/authorized_keys

if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF /root/.ssh >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------
# 20. Restart SSH
# ------------------------------------------------------------

log "Restarting SSH service"

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

if [[ -n "${SSH_SERVICE}" ]]; then

    if ! systemctl restart "${SSH_SERVICE}"; then
        die "Failed to restart ${SSH_SERVICE}. Keep this SSH session open and inspect the service."
    fi

else

    warn "Could not automatically determine SSH service name."
    warn "Configuration has been validated, but SSH was not restarted."
fi

# ------------------------------------------------------------
# 21. Final verification
# ------------------------------------------------------------

if systemctl is-active --quiet "${SSH_SERVICE:-sshd}" 2>/dev/null; then
    log "SSH service is active."
fi

echo
echo "============================================================"
echo " Configuration completed"
echo "============================================================"
echo
echo "Root SSH key file:"
echo "  /root/.ssh/authorized_keys"
echo
echo "SSH configuration:"
echo "  PermitRootLogin prohibit-password"
echo "  PasswordAuthentication no"
echo
echo "Backup:"
echo "  ${BACKUP_DIR}"
echo
echo "IMPORTANT:"
echo "  DO NOT close this SSH session yet."
echo
echo "From another terminal, test:"
echo
echo "  ssh root@<SERVER_IP>"
echo
echo "If root login works, the configuration is ready."
echo
echo "============================================================"
```
