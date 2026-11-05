#!/bin/bash
# Fetches the Ghost Hour toolchain into .tools/ without sudo or system-wide changes:
# ACME and VICE (from the Ubuntu archive), the C64 ROMs (from the VICE source release), a Python venv.
set -euo pipefail
cd "$(dirname "$0")"

VICE_VERSION=3.7.1
T="$PWD/.tools"
mkdir -p "$T/root"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "== ACME and VICE packages"
(cd "$tmp" && apt-get download acme vice libglew2.2)
for d in "$tmp"/*.deb; do dpkg -x "$d" "$T/root"; done

echo "== C64 and 1541 ROMs, from the VICE $VICE_VERSION source release"
curl -fsSL -o "$tmp/vice.tar.gz" \
    "https://sourceforge.net/projects/vice-emu/files/releases/vice-$VICE_VERSION.tar.gz/download"
tar xzf "$tmp/vice.tar.gz" -C "$tmp" --wildcards "vice-$VICE_VERSION/data/C64/*" "vice-$VICE_VERSION/data/DRIVES/*"
cp --update=none "$tmp/vice-$VICE_VERSION"/data/C64/* "$T/root/usr/share/vice/C64/"
cp --update=none "$tmp/vice-$VICE_VERSION"/data/DRIVES/* "$T/root/usr/share/vice/DRIVES/"

echo "== Python venv"
python3 -m venv "$T/venv"
"$T/venv/bin/pip" -q install pillow imageio-ffmpeg

cat > "$T/env.sh" <<'ENV'
# source me: puts the local C64 toolchain on PATH
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$T/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export PATH="$T/root/usr/bin:$T/venv/bin:$PATH"
export VICE_DIR="$T/root/usr/share/vice"
ENV

echo "Done. Now: make && ./run.sh"
