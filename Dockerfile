FROM lscr.io/linuxserver/openssh-server:latest

LABEL org.opencontainers.image.source="https://github.com/thebaoster/supertermai" \
      org.opencontainers.image.description="supertermai: always-on SSH shell with herdr, tmux and Claude Code"

ARG HERDR_VERSION=v0.9.1

RUN apk add --no-cache \
      bash \
      curl \
      git \
      libgcc \
      libstdc++ \
      ripgrep \
      tmux \
      nodejs \
      npm

# herdr publishes a static-pie Linux binary, so it runs on Alpine/musl as-is.
RUN curl -fsSL -o /usr/local/bin/herdr \
      "https://github.com/herdrdev/herdr/releases/download/${HERDR_VERSION}/herdr-linux-x86_64" \
    && chmod 0755 /usr/local/bin/herdr \
    && herdr --version

# The native installer targets $HOME/.local; copy the resolved binary system-wide so
# the unprivileged SSH user can run it without access to /root.
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && install -m 0755 "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude \
    && rm -rf /root/.local/share/claude /root/.local/bin/claude \
    && claude --version

# Updates come from rebuilding the image, not from the binary self-updating into /config.
ENV DISABLE_AUTOUPDATER=1 \
    USE_BUILTIN_RIPGREP=0
