#!/usr/bin/env bash
# Meta-repo build entry point for the dubai (Motorola Edge 30, SM7325) port.
#
#   ./build.sh [target...] [-- nix-build args]      default: images
#
# Targets (results are symlinks in build/, logs in build/logs/):
#   kernel      the kernel package (Image.gz, dtbs, modules)   kernel/
#   system      the NixOS system (toplevel)                     userspace/
#   boot        boot.img (kernel + Mobile NixOS stage-1)        userspace/
#   images      boot.img + system.img (ext4 rootfs)             userspace/
#   bootloader  U-Boot as a boot.img (work in progress)         bootloader/
#
# e.g. ./build.sh kernel system boot -- --cores 16 -j 6
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '[build.sh] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

targets=()
while [ $# -gt 0 ]; do
    case "$1" in
        --) shift; break ;;
        -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) targets+=("$1") ;;
    esac
    shift
done
[ ${#targets[@]} -gt 0 ] || targets=(images)

for m in kernel/linux/Makefile userspace/mobile-nixos/default.nix; do
    [ -f "${SRC}/${m}" ] || die "${m%/*} missing: git submodule update --init --recursive --depth 1"
done

mkdir -p "${SRC}/build/logs"
for t in "${targets[@]}"; do
    case "$t" in
        kernel)                   script=buildkernel ;;
        system|boot|images)       script=builduserspace ;;
        bootloader)               script=buildbl ;;
        *) die "unknown target: $t" ;;
    esac
    log "$t -> build/$t (log: build/logs/$t.log)"
    bash "${SRC}/scripts/${script}.sh" "$t" "$@" 2>&1 | tee "${SRC}/build/logs/$t.log"
done
