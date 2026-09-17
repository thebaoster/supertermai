#!/bin/bash
set -euo pipefail

PUID="${PUID:-99}"
PGID="${PGID:-100}"
USER_NAME="${USER_NAME:-agent}"
SUDO_ACCESS="${SUDO_ACCESS:-false}"
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

# Optional SSH certificate auth (e.g. Cloudflare Access short-lived certificates):
# SSH_CA_PUBKEY is the CA public key; SSH_CA_PRINCIPALS lists the certificate
# principals allowed to log in as USER_NAME (Cloudflare uses the email prefix).
if [[ -n "${SSH_CA_PUBKEY:-}" ]]; then
  printf '%s\n' "$SSH_CA_PUBKEY" > /etc/ssh/trusted_ca.pub
  chmod 644 /etc/ssh/trusted_ca.pub
  {
    echo "TrustedUserCAKeys /etc/ssh/trusted_ca.pub"
    if [[ -n "${SSH_CA_PRINCIPALS:-}" ]]; then
      echo "AuthorizedPrincipalsFile /etc/ssh/principals/%u"
    fi
  } > /etc/ssh/sshd_config.d/ca.conf
  if [[ -n "${SSH_CA_PRINCIPALS:-}" ]]; then
    mkdir -p /etc/ssh/principals
    tr ',' '\n' <<<"$SSH_CA_PRINCIPALS" | sed '/^$/d' > "/etc/ssh/principals/$USER_NAME"
    chmod 644 "/etc/ssh/principals/$USER_NAME"
  fi
  log "certificate auth enabled (principals: ${SSH_CA_PRINCIPALS:-<username only>})"
else
  rm -f /etc/ssh/sshd_config.d/ca.conf
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
