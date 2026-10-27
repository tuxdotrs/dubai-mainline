#!/usr/bin/env bash
# Runs inside tools/denial/Dockerfile: Denial's CROSS_BUILDING.md, steps 2-8,
# for one Denial revision. Caches live in /cache (HOME), the archive goes to
# /out/denial-linux-arm64-<rev>.tar.gz.
#   denial-cross-build <denial-rev>
set -euo pipefail
REV=${1:?usage: denial-cross-build <denial-rev>}
export HOME=/cache
log() { printf '[denial-cross-build] %s\n' "$*" >&2; }

command -v rustup >/dev/null || rustup-init -y --no-modify-path --default-toolchain none

SRCDIR=/cache/src/denial
if [ ! -d "$SRCDIR/.git" ]; then
    git clone https://github.com/denialwm/denial.git "$SRCDIR"
fi
git -C "$SRCDIR" fetch origin
git -C "$SRCDIR" checkout --force --detach "$REV"
git -C "$SRCDIR" clean -fdx
cd "$SRCDIR"
log "denial $(git rev-parse HEAD)"

# 2. Configure. The sysroot is the container itself: arm64 -dev packages are
# installed multiarch under /usr/lib/aarch64-linux-gnu.
export TARGET_SYSROOT=/
export DENIAL_BUILD_JOBS=${DENIAL_BUILD_JOBS:-$(nproc)}
export DENIAL_USER_CACHE="$HOME/.cache/denial"
export DENIAL_PC_DEPENDENCY_ROOT="$DENIAL_USER_CACHE/pc-dependencies"
export DENIAL_FLUTTER_ENGINE_CACHE_ROOT="$DENIAL_USER_CACHE/flutter-engine"
mkdir -p "$DENIAL_USER_CACHE"
DENIAL_CROSS_WORK="$(mktemp -d "$DENIAL_USER_CACHE/cross-linux-arm64.XXXXXX")"
export DENIAL_CROSS_WORK

# 3. Locked dependencies (network on the first run)
log "bootstrap"
tools/denial-pc bootstrap
log "host engine (prepare-app-build)"
tools/denial-flutter-engine prepare-app-build
rustup target add aarch64-unknown-linux-gnu

# 4. ARM64 Flutter engine
export DENIAL_ENGINE_SOURCE="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/checkout/engine/src"
export DENIAL_HOST_ENGINE_OUT="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/build/out/denial_host_release"
export DENIAL_ARM_ENGINE_ROOT="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/build-arm64"
export DENIAL_ARM_ENGINE_OUT="$DENIAL_ARM_ENGINE_ROOT/out/denial_linux_arm64_release"
export DENIAL_DEPOT_TOOLS="$DENIAL_ENGINE_SOURCE/flutter/third_party/depot_tools"
test -d "$DENIAL_ENGINE_SOURCE"
test -d "$DENIAL_HOST_ENGINE_OUT"
log "arm64 engine"
(
    cd "$DENIAL_ENGINE_SOURCE"
    PATH="$DENIAL_DEPOT_TOOLS/.cipd_bin:$DENIAL_DEPOT_TOOLS:$PATH" \
    DEPOT_TOOLS_UPDATE=0 \
    VPYTHON_VIRTUALENV_ROOT="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/vpython" \
    ./flutter/tools/gn \
        --runtime-mode=release \
        --linux \
        --linux-cpu=arm64 \
        --enable-fontconfig \
        --out-dir="$DENIAL_ARM_ENGINE_ROOT" \
        --target-dir=denial_linux_arm64_release

    PATH="$DENIAL_DEPOT_TOOLS/.cipd_bin:$DENIAL_DEPOT_TOOLS:$PATH" \
    DEPOT_TOOLS_UPDATE=0 \
    VPYTHON_VIRTUALENV_ROOT="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/vpython" \
    /usr/bin/ninja \
        -C "$DENIAL_ARM_ENGINE_OUT" \
        -j "$DENIAL_BUILD_JOBS" \
        libflutter_engine.so \
        libflutter_linux_gtk.so \
        clang_x64/gen_snapshot \
        flutter_patched_sdk \
        flutter/shell/platform/linux:publish_headers_linux
)
file "$DENIAL_ARM_ENGINE_OUT/libflutter_engine.so" | grep -q 'ARM aarch64'
file "$DENIAL_ARM_ENGINE_OUT/clang_x64/gen_snapshot" | grep -q 'x86-64'

# 5. Flutter cross-build view
export DENIAL_ENGINE_VIEW="$DENIAL_CROSS_WORK/engine-view"
export DENIAL_ARM_ENGINE_VIEW="$DENIAL_ENGINE_VIEW/out/denial_linux_arm64_release"
mkdir -p "$DENIAL_ENGINE_VIEW/out" "$DENIAL_ARM_ENGINE_VIEW"
ln -s "$DENIAL_ENGINE_SOURCE/flutter" "$DENIAL_ENGINE_VIEW/flutter"
ln -s "$DENIAL_HOST_ENGINE_OUT" "$DENIAL_ENGINE_VIEW/out/denial_host_release"
for path in "$DENIAL_ARM_ENGINE_OUT"/*; do
    name="${path##*/}"
    test "$name" = gen_snapshot && continue
    ln -s "$path" "$DENIAL_ARM_ENGINE_VIEW/$name"
done
ln -s "$DENIAL_ARM_ENGINE_OUT/clang_x64/gen_snapshot" "$DENIAL_ARM_ENGINE_VIEW/gen_snapshot"

# 6. ARM64 shell
export DENIAL_FLUTTER="$DENIAL_PC_DEPENDENCY_ROOT/flutter/bin/flutter"
export DENIAL_SHELL_ASSEMBLY="$DENIAL_CROSS_WORK/shell-assembly"
log "arm64 shell"
(
    cd dart_shell
    "$DENIAL_FLUTTER" pub get
    "$DENIAL_FLUTTER" assemble \
        --local-engine-src-path="$DENIAL_ENGINE_VIEW" \
        --local-engine=denial_linux_arm64_release \
        --local-engine-host=denial_host_release \
        --suppress-analytics \
        --resource-pool-size="$DENIAL_BUILD_JOBS" \
        --output="$DENIAL_SHELL_ASSEMBLY" \
        -dTargetFile=lib/main.dart \
        -dBuildMode=release \
        -dTargetPlatform=linux-arm64 \
        -dDartObfuscation=false \
        -dTrackWidgetCreation=true \
        -dTreeShakeIcons=true \
        release_bundle_linux-arm64_assets
)
file "$DENIAL_SHELL_ASSEMBLY/lib/libapp.so" | grep -q 'ARM aarch64'

# 6b. The standalone Flutter apps (Settings/Welcome, Polkit dialog), assembled
# like the shell; Denial's nix/native-flutter-app.nix does this for x86-64.
for app in settings_app polkit_app; do
    log "arm64 $app"
    (
        cd "$app"
        "$DENIAL_FLUTTER" pub get
        "$DENIAL_FLUTTER" assemble \
            --local-engine-src-path="$DENIAL_ENGINE_VIEW" \
            --local-engine=denial_linux_arm64_release \
            --local-engine-host=denial_host_release \
            --suppress-analytics \
            --resource-pool-size="$DENIAL_BUILD_JOBS" \
            --output="$DENIAL_CROSS_WORK/$app-assembly" \
            -dTargetFile=lib/main.dart \
            -dBuildMode=release \
            -dTargetPlatform=linux-arm64 \
            -dDartObfuscation=false \
            -dTrackWidgetCreation=true \
            -dTreeShakeIcons=true \
            release_bundle_linux-arm64_assets
    )
    file "$DENIAL_CROSS_WORK/$app-assembly/lib/libapp.so" | grep -q 'ARM aarch64'
done

# 7. Rust compositor
export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_SYSROOT_DIR="$TARGET_SYSROOT"
export PKG_CONFIG_LIBDIR="$TARGET_SYSROOT/usr/lib/pkgconfig:$TARGET_SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$TARGET_SYSROOT/usr/lib64/pkgconfig:$TARGET_SYSROOT/usr/share/pkgconfig"
export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
export AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
export CFLAGS_aarch64_unknown_linux_gnu="--sysroot=$TARGET_SYSROOT"
export CXXFLAGS_aarch64_unknown_linux_gnu="--sysroot=$TARGET_SYSROOT"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C link-arg=--sysroot=$TARGET_SYSROOT -C link-arg=-Wl,-rpath-link,$TARGET_SYSROOT/usr/lib -C link-arg=-Wl,-rpath-link,$TARGET_SYSROOT/lib"
export CARGO_TARGET_DIR="$DENIAL_USER_CACHE/cross-rust"
# denial-pc bootstrap fetched the compositor's crates; the app runner has its own lock
cargo fetch --manifest-path native_app/Cargo.toml --locked
export CARGO_NET_OFFLINE=true
pkg-config --exists libdrm gbm egl libinput libseat libudev xkbcommon
log "compositor"
(
    cd compositor
    cargo build --locked --offline --release \
        --target aarch64-unknown-linux-gnu \
        --features flutter \
        --bin deniald --bin denialctl \
        --jobs "$DENIAL_BUILD_JOBS"
    cargo build --locked --offline --release \
        --target aarch64-unknown-linux-gnu \
        -p denial-portal \
        --jobs "$DENIAL_BUILD_JOBS"
    cargo build --locked --offline --release \
        --target aarch64-unknown-linux-gnu \
        -p denial-polkit-agent \
        --jobs "$DENIAL_BUILD_JOBS"
)
log "app runner"
cargo build --manifest-path native_app/Cargo.toml --locked --offline --release \
    --target aarch64-unknown-linux-gnu \
    --jobs "$DENIAL_BUILD_JOBS"

# 8. Payload
export DENIAL_PAYLOAD="$DENIAL_CROSS_WORK/payload"
export DENIAL_RUST_RELEASE="$CARGO_TARGET_DIR/aarch64-unknown-linux-gnu/release"
install -d "$DENIAL_PAYLOAD/bin" "$DENIAL_PAYLOAD/bundle/lib" "$DENIAL_PAYLOAD/bundle/data/flutter_assets"
install -m755 "$DENIAL_RUST_RELEASE/deniald" "$DENIAL_PAYLOAD/bin/deniald"
install -m755 "$DENIAL_RUST_RELEASE/denialctl" "$DENIAL_PAYLOAD/bin/denialctl"
install -m755 "$DENIAL_RUST_RELEASE/denial-portal" "$DENIAL_PAYLOAD/bin/denial-portal"
install -m755 "$DENIAL_ARM_ENGINE_OUT/libflutter_engine.so" "$DENIAL_PAYLOAD/bundle/lib/libflutter_engine.so"
install -m755 "$DENIAL_SHELL_ASSEMBLY/lib/libapp.so" "$DENIAL_PAYLOAD/bundle/lib/libapp.so"
install -m644 "$DENIAL_ARM_ENGINE_OUT/icudtl.dat" "$DENIAL_PAYLOAD/bundle/data/icudtl.dat"
cp -a "$DENIAL_SHELL_ASSEMBLY/flutter_assets/." "$DENIAL_PAYLOAD/bundle/data/flutter_assets/"
install -m644 packaging/arch/outputs.conf "$DENIAL_PAYLOAD/outputs.conf"
install -m755 "$DENIAL_RUST_RELEASE/denial-polkit-agent" "$DENIAL_PAYLOAD/bin/denial-polkit-agent"
# apps/<name>/: the denial-app runner named after the app, its AOT bundle; the
# engine and ICU data are the shell bundle's (the package links them)
for pair in settings_app:denial-settings polkit_app:denial-polkit-dialog; do
    app=${pair%%:*} name=${pair#*:}
    install -d "$DENIAL_PAYLOAD/apps/$name/lib" "$DENIAL_PAYLOAD/apps/$name/data/flutter_assets"
    install -m755 "$DENIAL_RUST_RELEASE/denial-app" "$DENIAL_PAYLOAD/apps/$name/$name"
    install -m755 "$DENIAL_CROSS_WORK/$app-assembly/lib/libapp.so" "$DENIAL_PAYLOAD/apps/$name/lib/libapp.so"
    cp -a "$DENIAL_CROSS_WORK/$app-assembly/flutter_assets/." "$DENIAL_PAYLOAD/apps/$name/data/flutter_assets/"
done
for f in bin/deniald bin/denialctl bin/denial-portal bin/denial-polkit-agent \
    bundle/lib/libflutter_engine.so bundle/lib/libapp.so \
    apps/denial-settings/denial-settings apps/denial-settings/lib/libapp.so \
    apps/denial-polkit-dialog/denial-polkit-dialog apps/denial-polkit-dialog/lib/libapp.so; do
    file "$DENIAL_PAYLOAD/$f" | grep -q 'ARM aarch64' || { log "not aarch64: $f"; exit 1; }
done
(cd "$DENIAL_PAYLOAD" && find bin bundle apps -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)

OUT="/out/denial-linux-arm64-${REV}.tar.gz"
tar -C "$DENIAL_CROSS_WORK" -czf "$OUT" payload
rm -rf "$DENIAL_CROSS_WORK"
log "done: $OUT"
