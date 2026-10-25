#!/usr/bin/env bash
# Build entry point for the dubai (Motorola Edge 30) Mobile NixOS port.
#
#   ./build.sh [target...]        default: images
#
# Targets (results are symlinks in build/, logs in build/logs/):
#   kernel   the kernel package (Image.gz, dtbs, modules)  from kernel/
#   system   the NixOS system (toplevel), for nix copy + switch-to-configuration
#   boot     boot.img (kernel + stage-1), for boot_a/boot_b
#   images   boot.img + system.img (ext4 rootfs for userdata)
#
# Extra nix-build arguments go after `--`, e.g. ./build.sh kernel -- --cores 16
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${SRC}/build"

log() { printf '[build.sh] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

targets=()
while [ $# -gt 0 ]; do
    case "$1" in
        --) shift; break ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) targets+=("$1") ;;
    esac
    shift
done
[ ${#targets[@]} -gt 0 ] || targets=(images)

for m in kernel/linux/Makefile mobile-nixos/default.nix; do
    [ -f "${SRC}/${m}" ] || die "${m%%/*}/ missing: git submodule update --init --depth 1"
done

mkdir -p "${OUT}/logs"
for t in "${targets[@]}"; do
    case "$t" in
        kernel) attr=(-E "(import ${SRC}/default.nix {}).config.mobile.boot.stage-1.kernel.package") ;;
        system) attr=("${SRC}/default.nix" -A config.system.build.toplevel) ;;
        boot)   attr=("${SRC}/default.nix" -A outputs.android.android-bootimg) ;;
        images) attr=("${SRC}/default.nix" -A outputs.default) ;;
        *) die "unknown target: $t" ;;
    esac
    log "$t -> build/$t (log: build/logs/$t.log)"
    nix-build "${attr[@]}" -o "${OUT}/$t" "$@" 2>&1 | tee "${OUT}/logs/$t.log"
done
