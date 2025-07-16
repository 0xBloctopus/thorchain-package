FROM hasura/graphql-engine:v2.46.0

# Install Hasura CLI (arch-aware) so we can run `hasura metadata apply` inside the container
# Install curl if it's not already present (handles both Debian/Ubuntu & Alpine base images)
RUN set -eux; \
    if command -v apk >/dev/null 2>&1; then \
      apk add --no-cache curl ca-certificates; \
    else \
      apt-get update; \
      apt-get install -y --no-install-recommends curl ca-certificates; \
      rm -rf /var/lib/apt/lists/*; \
    fi; \
    ARCH="$(uname -m)"; \
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        curl -L https://github.com/hasura/graphql-engine/releases/latest/download/cli-hasura-linux-arm64 -o /usr/local/bin/hasura; \
    else \
        curl -L https://github.com/hasura/graphql-engine/releases/latest/download/cli-hasura-linux-amd64 -o /usr/local/bin/hasura; \
    fi; \
    chmod +x /usr/local/bin/hasura