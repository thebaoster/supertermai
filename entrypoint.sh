#!/bin/bash
set -euo pipefail

PUID="${PUID:-99}"
PGID="${PGID:-100}"
USER_NAME="${USER_NAME:-agent}"
SUDO_ACCESS="${SUDO_ACCESS:-false}"
PASSWORD_AUTH="${PASSWORD_AUTH:-false}"
VSCODE_TUNNEL="${VSCODE_TUNNEL:-false}"
TUNNEL_NAME="${TUNNEL_NAME:-supertermai}"

log() { echo "[supertermai] $*"; }

if [[ -n "${TZ:-}" && -f "/usr/share/zoneinfo/$TZ" ]]; then
  ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
fi

if ! getent group "$PGID" >/dev/null; then
  groupadd -g "$PGID" "$USER_NAME"
fi
if id -u "$USER_NAME" >/dev/null 2>&1; then
  usermod -o -u "$PUID" -g "$PGID" -d /config -s /bin/bash "$USER_NAME"
else
  useradd -o -M -u "$PUID" -g "$PGID" -d /config -s /bin/bash "$USER_NAME"
fi
log "user $USER_NAME uid=$PUID gid=$PGID"

if [[ "$SUDO_ACCESS" == "true" ]]; then
  echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/supertermai
  chmod 0440 /etc/sudoers.d/supertermai
else
  rm -f /etc/sudoers.d/supertermai
fi

mkdir -p /config/.ssh
touch /config/.ssh/authorized_keys
if [[ -n "${PUBLIC_KEY:-}" ]] && ! grep -qxF "$PUBLIC_KEY" /config/.ssh/authorized_keys; then
  echo "$PUBLIC_KEY" >> /config/.ssh/authorized_keys
  log "added PUBLIC_KEY to authorized_keys"
fi
if [[ ! -s /config/.ssh/authorized_keys ]]; then
  log "WARNING: authorized_keys is empty; set PUBLIC_KEY or nobody can log in"
fi

chown -R "$PUID:$PGID" /config
chmod 700 /config/.ssh
chmod 600 /config/.ssh/authorized_keys

mkdir -p /config/ssh_host_keys
for t in ed25519 rsa; do
  if [[ ! -f "/config/ssh_host_keys/ssh_host_${t}_key" ]]; then
    ssh-keygen -q -t "$t" -N "" -f "/config/ssh_host_keys/ssh_host_${t}_key"
    log "generated ssh_host_${t}_key"
  fi
done
chown -R root:root /config/ssh_host_keys
chmod 700 /config/ssh_host_keys
chmod 600 /config/ssh_host_keys/*_key

# Optional SSH certificate auth (e.g. Cloudflare Access short-lived certificates).
# Cloudflare logs in as the certificate principal (the email prefix) regardless of
# the username typed, so each principal becomes an alias account sharing
# USER_NAME's uid, group and home.
if [[ -n "${SSH_CA_PUBKEY:-}" ]]; then
  printf '%s\n' "$SSH_CA_PUBKEY" > /etc/ssh/trusted_ca.pub
  chmod 644 /etc/ssh/trusted_ca.pub
  echo "TrustedUserCAKeys /etc/ssh/trusted_ca.pub" > /etc/ssh/sshd_config.d/20-ca.conf
  for p in $(tr ',' ' ' <<<"${SSH_CA_PRINCIPALS:-}"); do
    [[ "$p" == "$USER_NAME" ]] && continue
    if id -u "$p" >/dev/null 2>&1; then
      usermod -o -u "$PUID" -g "$PGID" -d /config -s /bin/bash "$p"
    else
      useradd -o -M -u "$PUID" -g "$PGID" -d /config -s /bin/bash "$p"
    fi
    if [[ "$SUDO_ACCESS" == "true" ]]; then
      echo "$p ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/supertermai
    fi
  done
  log "certificate auth enabled (principals: ${SSH_CA_PRINCIPALS:-$USER_NAME})"
else
  rm -f /etc/ssh/sshd_config.d/20-ca.conf
fi

# Optional password login (for machines with nothing but an ssh client). With
# TOTP_SECRET set, PAM asks for the password and then a one-time code.
accounts="$USER_NAME $(tr ',' ' ' <<<"${SSH_CA_PRINCIPALS:-}")"
if [[ "$PASSWORD_AUTH" == "true" ]]; then
  [[ -n "${USER_PASSWORD:-}" ]] || { log "ERROR: PASSWORD_AUTH=true but USER_PASSWORD is empty"; exit 1; }
  for a in $accounts; do echo "$a:$USER_PASSWORD" | chpasswd; done
  cat > /etc/ssh/sshd_config.d/10-auth.conf <<'EOF'
KbdInteractiveAuthentication yes
AuthenticationMethods publickey keyboard-interactive
EOF
  if [[ -n "${TOTP_SECRET:-}" ]]; then
    printf '%s\n" RATE_LIMIT 3 30\n" WINDOW_SIZE 3\n" DISALLOW_REUSE\n" TOTP_AUTH\n' "$TOTP_SECRET" > /config/.google_authenticator
    chown "$PUID:$PGID" /config/.google_authenticator
    chmod 400 /config/.google_authenticator
    grep -q pam_google_authenticator /etc/pam.d/sshd || echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
    log "password + one-time code login enabled for: $accounts"
  else
    sed -i '/pam_google_authenticator/d' /etc/pam.d/sshd
    log "password login enabled (no TOTP) for: $accounts"
  fi
else
  for a in $accounts; do passwd -l "$a" >/dev/null 2>&1 || true; done
  rm -f /etc/ssh/sshd_config.d/10-auth.conf
  sed -i '/pam_google_authenticator/d' /etc/pam.d/sshd
fi

mkdir -p /run/sshd
/usr/sbin/sshd -t
/usr/sbin/sshd -D -e &
sshd_pid=$!
log "sshd listening on 2222"

tunnel_pid=""
if [[ "$VSCODE_TUNNEL" == "true" ]]; then
  # Runs until login exists; `code tunnel user login --provider github` over SSH
  # stores the token in /config/.vscode/cli and the next iteration picks it up.
  runuser -u "$USER_NAME" -- env HOME=/config VSCODE_CLI_DATA_DIR=/config/.vscode/cli bash -c '
    while true; do
      code tunnel --accept-server-license-terms --name "$0" </dev/null || true
      echo "[supertermai] tunnel exited (not logged in yet?). Over SSH run: code tunnel user login --provider github. Retrying in 60s."
      sleep 60
    done' "$TUNNEL_NAME" &
  tunnel_pid=$!
  log "vscode tunnel service enabled (name: $TUNNEL_NAME)"
fi

shutdown() {
  log "stopping"
  [[ -n "$tunnel_pid" ]] && kill "$tunnel_pid" 2>/dev/null || true
  kill "$sshd_pid" 2>/dev/null || true
}
trap shutdown TERM INT

wait "$sshd_pid"
