#!/usr/bin/env bash
# bootloader/ -> build/bootloader (U-Boot as a boot.img). Work in progress.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shift
[ -f "${SRC}/bootloader/default.nix" ] || { echo "bootloader/: no build yet (U-Boot port in progress)" >&2; exit 1; }
nix-build "${SRC}/bootloader/default.nix" -o "${SRC}/build/bootloader" "$@"
