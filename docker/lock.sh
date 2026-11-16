#!/bin/sh
# Regenerate the hash-pinned lock files used by ./Dockerfile.
#   docker/lock.sh             re-resolve, keeping current pins where still valid
#   docker/lock.sh --upgrade   bump everything to the newest allowed versions
# Uses `uv` from PATH, or the uv container image when uv is not installed.
set -eu
cd "$(dirname "$0")"

# Lock for the Python version of the Dockerfile's base image.
PY=$(sed -n 's/^FROM python:\([0-9][0-9.]*\)-.*/\1/p' ../Dockerfile | head -n 1)
[ -n "$PY" ] || { echo "could not read the Python version from ../Dockerfile" >&2; exit 1; }

UV_IMAGE="ghcr.io/astral-sh/uv:0.13.8-python${PY}-trixie-slim"
if command -v uv >/dev/null 2>&1; then
    uv() { command uv "$@"; }
else
    uv() { docker run --rm -u "$(id -u):$(id -g)" -e UV_CACHE_DIR=/tmp/uv-cache \
        -v "$PWD:/work" -w /work --entrypoint uv "$UV_IMAGE" "$@"; }
fi

compile() {
    uv pip compile --quiet --universal --generate-hashes \
        --python-version "$PY" --custom-compile-command "docker/lock.sh" "$@"
}

compile "$@" requirements.in -o requirements.txt
compile "$@" requirements-build.in -c requirements.txt -o requirements-build.txt
compile "$@" requirements-test.in -c requirements.txt -o requirements-test.txt
