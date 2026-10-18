ARG RUST_BUILDER_IMAGE=rust:1-slim-bookworm
FROM ${RUST_BUILDER_IMAGE} AS builder
ARG CARGO_BUILD_JOBS=1
ARG CARGO_REGISTRY_MIRROR=crates-io
ARG CARGO_HTTP_MULTIPLEXING=false
ENV CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup
ENV PATH=/usr/local/cargo/bin:${PATH}
RUN if ! command -v cargo >/dev/null 2>&1; then \
      test "$CARGO_REGISTRY_MIRROR" = ustc \
      && sed -i 's#http://deb.debian.org#http://mirrors.ustc.edu.cn#g' /etc/apt/sources.list.d/debian.sources \
      && apt-get update \
      && apt-get install -y --no-install-recommends ca-certificates curl gcc libc6-dev \
      && export RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static \
      && export RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup \
      && curl --fail --show-error --silent --location "$RUSTUP_UPDATE_ROOT/dist/x86_64-unknown-linux-gnu/rustup-init" -o /tmp/rustup-init \
      && chmod +x /tmp/rustup-init \
      && /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain stable \
      && rm -f /tmp/rustup-init \
      && rm -rf /var/lib/apt/lists/*; \
    fi
RUN case "$CARGO_REGISTRY_MIRROR" in \
      crates-io) ;; \
      ustc) printf '[source.crates-io]\nreplace-with = "ustc"\n[source.ustc]\nregistry = "sparse+https://mirrors.ustc.edu.cn/crates.io-index/"\n' > /usr/local/cargo/config.toml ;; \
      *) echo 'Unsupported CARGO_REGISTRY_MIRROR' >&2; exit 2 ;; \
    esac
WORKDIR /build
COPY server/Cargo.toml server/Cargo.lock ./server/
COPY server/src ./server/src
COPY server/migrations ./server/migrations
COPY shared/data ./shared/data
COPY client/assets/data ./client/assets/data
RUN cargo build --release --locked --manifest-path server/Cargo.toml

FROM debian:bookworm-slim
ARG CARGO_REGISTRY_MIRROR=crates-io
RUN if [ "$CARGO_REGISTRY_MIRROR" = ustc ]; then sed -i 's#http://deb.debian.org#http://mirrors.ustc.edu.cn#g' /etc/apt/sources.list.d/debian.sources; fi \
    && apt-get update \
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
