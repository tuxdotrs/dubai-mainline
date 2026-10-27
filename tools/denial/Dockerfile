# Build environment for Denial's ARM64 cross-build (its CROSS_BUILDING.md):
# x86-64 Debian with an arm64 multiarch sysroot for the Rust compositor. The
# Flutter engine brings its own clang and sysroot through gclient.
FROM debian:trixie

RUN dpkg --add-architecture arm64 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git jq ninja-build pkg-config python3 \
      unzip xz-utils zip file binutils util-linux procps \
      build-essential clang libclang-dev \
      gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
      libgtk-3-dev libfontconfig-dev \
      libdrm-dev:arm64 libgbm-dev:arm64 libegl-dev:arm64 libgles-dev:arm64 \
      libinput-dev:arm64 libseat-dev:arm64 libudev-dev:arm64 \
      libxkbcommon-dev:arm64 libfontconfig-dev:arm64 libgtk-3-dev:arm64 \
      libpam0g-dev:arm64 libpulse-dev:arm64 libddcutil-dev:arm64 \
      libpolkit-gobject-1-dev:arm64 libpolkit-agent-1-dev:arm64 \
      libglib2.0-dev:arm64 libwayland-dev:arm64 \
      libsystemd-dev:arm64 \
 && rm -rf /var/lib/apt/lists/*

# rustup into /opt so any --user can use it; the toolchain itself comes from
# Denial's rust-toolchain.toml on first use (into $RUSTUP_HOME on the cache).
ENV CARGO_HOME=/cache/cargo RUSTUP_HOME=/cache/rustup PATH=/cache/cargo/bin:/opt/rustup-init:$PATH
RUN mkdir -p /opt/rustup-init \
 && curl -fsSL https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init \
      -o /opt/rustup-init/rustup-init \
 && chmod 755 /opt/rustup-init/rustup-init

COPY cross-build.sh /usr/local/bin/denial-cross-build
ENTRYPOINT ["/usr/local/bin/denial-cross-build"]
