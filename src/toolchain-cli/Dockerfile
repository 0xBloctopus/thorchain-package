FROM tiljordan/thornode-forking:1.0.23-23761879

SHELL ["/bin/bash", "-lc"]

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:$PATH

# Install minimal build dependencies required by the MCP CosmWasm tooling.
RUN set -euo pipefail \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    libssl-dev \
    pkg-config \
    python3 \
    binaryen \
 && rm -rf /var/lib/apt/lists/*

# Install Rust 1.77.1 toolchain with the wasm target plus supporting utilities.
RUN set -euo pipefail \
 && curl --retry 5 --retry-connrefused --retry-delay 2 https://sh.rustup.rs -sSf \
    | sh -s -- -y --profile minimal --default-toolchain 1.77.1 \
 && source "${CARGO_HOME}/env" \
 && rustup target add wasm32-unknown-unknown --toolchain 1.77.1 \
 && rustup component add rustfmt --toolchain 1.77.1 >/dev/null 2>&1 || true \
 && cargo +1.77.1 install wasm-tools --locked \
 && mkdir -p /root/.cargo \
 && printf '%s\n' \
      "[net]" \
      "git-fetch-with-cli = true" \
      > /root/.cargo/config.toml

ENV RUSTUP_TOOLCHAIN=1.77.1 \
    RUSTFLAGS="-C link-arg=-s -C target-feature=-bulk-memory,-sign-ext,-reference-types"

CMD ["/bin/sh", "-lc", "sleep infinity"]
