# ── Stage 0: build patched ttyd ──────────────────────────────────────────────
# Pins to 1.7.7 for supply-chain safety; patch adds --credential-file so the
# password never appears in ps aux / /proc/cmdline on shared interactive nodes.
#
# Builds libwebsockets from source with -DLWS_WITH_LIBUV=ON — the apt package
# ships without the uv event loop plugin that ttyd requires. Pin to v4.3.3
# (the version ttyd 1.7.7 was tested against, per its startup log).
FROM ubuntu:24.04 AS ttyd-builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    libjson-c-dev \
    libssl-dev \
    libuv1-dev \
    zlib1g-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Build libwebsockets from source with libuv support
ARG LWS_VERSION=v4.3.3
RUN git clone https://github.com/warmcat/libwebsockets.git /lws \
    && git -C /lws checkout ${LWS_VERSION}
RUN cmake -S /lws -B /lws/build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DLWS_WITH_LIBUV=ON \
        -DLWS_WITH_EVLIB_PLUGINS=OFF \
        -DLWS_WITHOUT_TESTAPPS=ON \
        -DLWS_WITHOUT_TEST_SERVER=ON \
        -DLWS_WITHOUT_TEST_PING=ON \
        -DLWS_WITHOUT_TEST_CLIENT=ON \
    && cmake --build /lws/build --parallel \
    && cmake --install /lws/build

# Clone and patch ttyd
ARG TTYD_VERSION=1.7.7
RUN git clone https://github.com/tsl0922/ttyd.git /ttyd \
    && git -C /ttyd checkout ${TTYD_VERSION}

COPY ttyd-credential-file.patch /ttyd-credential-file.patch
RUN patch -p1 -d /ttyd < /ttyd-credential-file.patch

# Build ttyd against the locally-built libwebsockets
RUN cmake -S /ttyd -B /ttyd/build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=/usr/local \
    && cmake --build /ttyd/build --parallel \
    && cmake --install /ttyd/build
# ─────────────────────────────────────────────────────────────────────────────

# ── Stage 1: final image ──────────────────────────────────────────────────────
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    bash \
    ca-certificates \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    # Build tools (needed for Python packages with C extensions)
    build-essential \
    # JSON processing
    jq \
    # Hex dump utility
    bsdextrautils \
    # Fast code search
    ripgrep \
    # Text editors
    vim \
    nano \
    # SSH client for git over SSH remotes
    openssh-client \
    # Runtime libraries for ttyd (libwebsockets built from source with libuv support)
    libjson-c5 \
    libuv1t64 \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (LTS) via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install ttyd (patched build from ttyd-builder stage — supports --credential-file)
# Also copy the custom libwebsockets build (built with -DLWS_WITH_LIBUV=ON;
# the apt package lacks the uv event loop plugin ttyd requires).
COPY --from=ttyd-builder /usr/local/bin/ttyd /usr/local/bin/ttyd
COPY --from=ttyd-builder /usr/local/lib/libwebsockets.so* /usr/local/lib/
RUN ldconfig

# Create a non-root user to run OpenCode
RUN useradd -ms /bin/bash opencodeuser
USER opencodeuser
WORKDIR /home/opencodeuser
RUN chmod ugo+rx /home/opencodeuser

RUN mkdir -p /home/opencodeuser/.local/bin/

# Install uv (fast Python package manager)
RUN if [ -x "/home/opencodeuser/.local/bin/uv" ]; then \
      echo "uv already installed: $(/home/opencodeuser/.local/bin/uv --version)"; \
    else \
      curl -LsSf https://astral.sh/uv/install.sh | sh; \
    fi

# Install OpenCode via the official installer
# The installer places the binary at ~/.opencode/bin/opencode
RUN if [ -x "/home/opencodeuser/.opencode/bin/opencode" ]; then \
      echo "opencode already installed: $(/home/opencodeuser/.opencode/bin/opencode --version)"; \
    else \
      curl -fsSL https://opencode.ai/install | bash; \
    fi

ENV PATH="/home/opencodeuser/.opencode/bin:/home/opencodeuser/.local/bin:${PATH}"

# Default working directory for projects (mount your project here)
WORKDIR /home/opencodeuser/project

# Verify the installation
RUN opencode --version

# Default entrypoint
ENTRYPOINT ["opencode"]
CMD ["--help"]
