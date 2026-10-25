#!/usr/bin/env bash
# kernel/ -> build/kernel. Evaluated through the userspace config so it is the
# exact package the system and boot.img use (cross-compiled from x86_64).
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shift  # target name
nix-build -E "(import ${SRC}/userspace/default.nix {}).config.mobile.boot.stage-1.kernel.package" \
    -o "${SRC}/build/kernel" "$@"
