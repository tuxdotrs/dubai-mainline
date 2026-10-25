#!/usr/bin/env bash
# userspace/ -> build/{system,boot,images}
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
t=$1; shift
case "$t" in
    system) attr=config.system.build.toplevel ;;
    boot)   attr=outputs.android.android-bootimg ;;
    images) attr=outputs.default ;;
esac
nix-build "${SRC}/userspace/default.nix" -A "$attr" -o "${SRC}/build/$t" "$@"
