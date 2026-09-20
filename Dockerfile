FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/thebaoster/supertermai" \
      org.opencontainers.image.description="supertermai: always-on SSH shell with herdr, tmux, Claude Code and VS Code tunnel"

ARG HERDR_VERSION=v0.9.1
ARG NODE_MAJOR=22

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Ubuntu 24.04 ships a default user on uid 1000; drop it so PUID can be anything.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gnupg \
        less \
        libpam-google-authenticator \
        netcat-openbsd \
        openssh-server \
        procps \
        ripgrep \
        sudo \
        tini \
        tmux \
        tzdata \
    && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && userdel -r ubuntu

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

RUN curl -fsSL "https://update.code.visualstudio.com/latest/cli-linux-x64/stable" \
      | tar -xz -C /usr/local/bin code \
    && code --version

COPY sshd_config /etc/ssh/sshd_config.d/50-supertermai.conf
COPY entrypoint.sh /usr/local/bin/entrypoint
RUN chmod 0755 /usr/local/bin/entrypoint && mkdir -p /run/sshd

EXPOSE 2222
VOLUME /config

ENTRYPOINT ["tini", "--", "entrypoint"]
