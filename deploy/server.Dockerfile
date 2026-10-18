FROM rust:1-slim-bookworm AS builder
WORKDIR /build
COPY server/Cargo.toml server/Cargo.lock ./server/
COPY server/src ./server/src
COPY server/migrations ./server/migrations
COPY shared/data ./shared/data
COPY client/assets/data ./client/assets/data
RUN cargo build --release --locked --manifest-path server/Cargo.toml

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 vssjx \
    && useradd --uid 10001 --gid 10001 --no-create-home vssjx \
    && install -d -o vssjx -g vssjx /app/logs
WORKDIR /app
COPY --from=builder /build/server/target/release/vssjx-server /usr/local/bin/vssjx-server
ENV SSJX_ENV_FILE="" SSJX_LOG_DIR=/app/logs
USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/vssjx-server"]
