# supertermai

An always-on SSH shell for Unraid that runs Claude Code (or other coding agents) inside a persistent [herdr](https://herdr.dev) or tmux session.
SSH in from any device, start an agent, detach, and reattach later to find it still running.

It is a plain Docker container installed through the Unraid Docker tab.
Nothing is installed on the Unraid host: no plugins, no NerdPack packages, nothing in `/boot/config/go`.
The container is unprivileged, uses bridge networking, and mounts only its own appdata folder.

## What's in the image

`ghcr.io/thebaoster/supertermai` is built from [Dockerfile](Dockerfile):

- Base: `lscr.io/linuxserver/openssh-server` (Alpine, key-only SSH on port 2222, home directory at `/config`)
- `herdr` (static binary, pinned by `HERDR_VERSION`) and `tmux` as a fallback multiplexer
- Claude Code via the official native installer, with the in-container auto-updater disabled so the binary never drifts from the image
- `nodejs` and `npm` for npx-based MCP servers

## Install on Unraid

1. Docker tab > **Template Repositories** (bottom of the page) > add `https://github.com/thebaoster/supertermai` > Save.
2. Docker tab > **Add Container** > pick `supertermai` from the template dropdown.
3. Paste your SSH public key (the contents of your `.pub` file) into **Public Key**, set **Timezone**, and Apply.
   Password login is disabled; only that key can log in.
4. First login, run `claude` once to authenticate.
   With no browser available it prints a login code to paste back into the terminal.
   Credentials persist under the appdata path (`/mnt/user/appdata/supertermai/.claude/` by default).
   Alternatively export `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token` on another machine).

Template: [templates/supertermai.xml](templates/supertermai.xml).

## Daily use

```bash
ssh -p 2222 agent@<unraid-ip>
herdr        # launches or reattaches the default background session
```

Detach with `Ctrl-b q` (herdr) or `Ctrl-b d` (tmux), or just close the terminal.
Agents keep running inside the container until you come back.
For tmux instead: `tmux new -A -s claude`.

## Updating

The image is rebuilt on every Dockerfile change and can be rebuilt on demand (Actions > image > Run workflow) to pick up a new Claude Code release.
Unraid's Docker tab will then show an update for `supertermai`; apply it like any other container.

## Limitation

A container restart (update, `docker restart`, Docker daemon restart, host reboot) kills the herdr/tmux server and everything running in it.
This is inherent to terminal multiplexers, not something the container adds.
Finish or checkpoint agent work before applying an update.
