#!/usr/bin/env bash
# bootloader/ -> build/bootloader (U-Boot as a boot.img, installed on boot_b).
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shift
[ -f "${SRC}/bootloader/default.nix" ] || { echo "bootloader/: missing (git submodule update --init)" >&2; exit 1; }
nix-build "${SRC}/bootloader/default.nix" -o "${SRC}/build/bootloader" "$@"
