# supertermai

An always-on SSH shell for Unraid that runs Claude Code (or other coding agents) inside a persistent [herdr](https://herdr.dev) or tmux session, with an optional VS Code Remote Tunnel.
SSH in from any device, start an agent, detach, and reattach later to find it still running.
Or open the whole box in VS Code from anywhere.

It is a plain Docker container installed through the Unraid Docker tab.
Nothing is installed on the Unraid host: no plugins, no NerdPack packages, nothing in `/boot/config/go`.
The container is unprivileged, uses bridge networking, mounts only its own appdata folder, and needs no inbound ports beyond SSH (the tunnel is outbound-only).

## What's in the image

`ghcr.io/thebaoster/supertermai` is built from [Dockerfile](Dockerfile) on Ubuntu 24.04:

- OpenSSH server on port 2222, key-only, root login disabled, host keys persisted in appdata
- `herdr` (static binary, pinned by `HERDR_VERSION`) and `tmux` as a fallback multiplexer
- Claude Code via the official native installer, with the in-container auto-updater disabled so the binary never drifts from the image
- VS Code CLI (`code`) for Remote Tunnels
- Node.js 22 for npx-based MCP servers, plus git, ripgrep, sudo (off by default)

## Install on Unraid

Unraid 7 no longer downloads third-party template repositories (the "Template Repositories" box is inert), so the template is installed as a user template on the flash drive, the same place the Docker tab saves its own.

1. Copy the template to your server, from a machine with SSH access:

   ```bash
   scp templates/supertermai.xml root@<unraid-ip>:/boot/config/plugins/dockerMan/templates-user/my-supertermai.xml
   ```

2. Docker tab > **Add Container** > pick `supertermai` under **User templates**.
3. Paste your SSH public key (the contents of your `.pub` file) into **Public Key**, set **Timezone**, and Apply.
   Password login is disabled; only that key can log in.
4. First login, run `claude` once to authenticate.
   With no browser available it prints a login code to paste back into the terminal.
   Credentials persist under the appdata path (`/mnt/user/appdata/supertermai/.claude/` by default).
   Alternatively export `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token` on another machine).

Template: [templates/supertermai.xml](templates/supertermai.xml).

| Variable | Default | Purpose |
|---|---|---|
| `PUBLIC_KEY` | | SSH public key allowed to log in (required) |
| `USER_NAME` | `agent` | Login user |
| `TZ` | `UTC` | Timezone |
| `VSCODE_TUNNEL` | `false` | `true` to run a VS Code Remote Tunnel in the background |
| `TUNNEL_NAME` | `supertermai` | Tunnel name shown in VS Code |
| `SUDO_ACCESS` | `false` | `true` for passwordless sudo inside the container |
| `SSH_CA_PUBKEY` | | Optional: public key of an SSH certificate authority to trust (see Cloudflare below) |
| `SSH_CA_PRINCIPALS` | | Optional: comma-separated certificate principals; each becomes an alias of `USER_NAME` (same uid and home) |
| `PUID` / `PGID` | `99` / `100` | Owner of the appdata files (Unraid `nobody:users`) |

## Daily use

```bash
ssh -p 2222 agent@<unraid-ip>
herdr        # launches or reattaches the default background session
```

Detach with `Ctrl-b q` (herdr) or `Ctrl-b d` (tmux), or just close the terminal.
Agents keep running inside the container until you come back.
For tmux instead: `tmux new -A -s claude`.

## VS Code

Two ways to use VS Code against the container:

**Remote-SSH (no setup):** add a host with port 2222 and your key; works on the LAN or over your VPN.

**Remote Tunnel (from anywhere, no VPN):**

1. Set `VSCODE_TUNNEL` to `true` in the template and apply.
2. Log the tunnel in once. Easiest: open the container log (Docker tab > log icon); the service prints a GitHub device code, so visit `https://github.com/login/device` and enter it.
   Or SSH in and run `code tunnel user login --provider github`.
   The login is stored in appdata (`.vscode/cli/`), so this is a one-time step.
3. Within a minute the background service registers the tunnel.
   Open it from VS Code's Remote Explorer > Tunnels, or in a browser at `https://vscode.dev/tunnel/<TUNNEL_NAME>`.

If the tunnel isn't showing up, check the container log; the service prints why it is waiting.

## Browser terminal from anywhere (Cloudflare Access)

If you already run a Cloudflare Tunnel, you can get a browser-rendered SSH terminal at a public hostname, protected by Cloudflare Access login, with no client, VPN or open port:

1. Tunnel: add a public hostname (e.g. `term.example.com`) with service `ssh://<unraid-ip>:2222`.
2. Access: create a self-hosted application for that hostname with type **SSH** (browser rendering) and an Allow policy for your identity.
3. Certificates: under Access > Service credentials > SSH, generate a short-lived certificate for that application and copy its public key.
4. Container: set `SSH_CA_PUBKEY` to that public key and `SSH_CA_PRINCIPALS` to your email prefix. Cloudflare always logs in as the email prefix, whatever you type at the username prompt, so the container creates that name as an alias of `USER_NAME` (same uid, same home). Apply.

Visit the hostname, log in, enter anything at the username prompt, and you are in the same box as over SSH; `herdr` attaches to the same sessions.

## Updating

The image is rebuilt on every change to the Dockerfile, entrypoint or sshd config, and can be rebuilt on demand (Actions > image > Run workflow) to pick up a new Claude Code or VS Code CLI release.
Unraid's Docker tab will then show an update for `supertermai`; apply it like any other container.

## Limitation

A container restart (update, `docker restart`, Docker daemon restart, host reboot) kills the herdr/tmux server and everything running in it.
This is inherent to terminal multiplexers, not something the container adds.
Finish or checkpoint agent work before applying an update.
