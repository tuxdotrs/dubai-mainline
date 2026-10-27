#!/usr/bin/env bash
# Denial (Wayland compositor) for ARM64 -> build/denial/denial-linux-arm64-<rev>.tar.gz
# Cross-built in docker (userspace/denial/cross-build/); caches in ~/.cache/denial-docker.
# The revision is the one userspace/denial/source.nix pins.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shift
command -v docker >/dev/null || { echo "builddenial: docker is required" >&2; exit 1; }
REV=$(sed -n 's/^ *rev = "\([0-9a-f]\{40\}\)";.*/\1/p' "${SRC}/userspace/denial/source.nix")
[ -n "$REV" ] || { echo "builddenial: no rev in userspace/denial/source.nix" >&2; exit 1; }
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/denial-docker"
mkdir -p "$CACHE" "${SRC}/build/denial"
docker build -t dubai-denial-build "${SRC}/userspace/denial/cross-build"
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$CACHE:/cache" -v "${SRC}/build/denial:/out" \
    dubai-denial-build "$REV"
