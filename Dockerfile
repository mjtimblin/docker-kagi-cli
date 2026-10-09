FROM rust:1.99-slim-bookworm AS build

ARG KAGI_VERSION=0.22.0

WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "v${KAGI_VERSION}" https://github.com/Microck/kagi-cli.git .

# Add the HTTP transport to `kagi mcp`. The patch targets v${KAGI_VERSION};
# update it when the pinned version changes.
COPY patches/mcp-http-transport.patch /tmp/mcp-http-transport.patch
RUN git apply --verbose /tmp/mcp-http-transport.patch

RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/target/release/kagi /usr/local/bin/kagi
ENTRYPOINT ["kagi"]

