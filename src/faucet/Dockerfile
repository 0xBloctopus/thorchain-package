ARG TARGETPLATFORM
ARG BUILDPLATFORM

FROM registry.gitlab.com/thorchain/thornode:mainnet AS runtime

# fix debian mirror + install tools
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list && \
    find /etc/apt/sources.list.d -type f -print0 2>/dev/null | xargs -0 -r sed -i 's|http://deb.debian.org|https://deb.debian.org|g' && \
    apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends netcat-openbsd util-linux jq && \
    rm -rf /var/lib/apt/lists/*