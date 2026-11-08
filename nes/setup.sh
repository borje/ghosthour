#!/bin/bash
# Fetches the NES toolchain into nes/.tools/ without sudo or system-wide changes:
# cc65 (ca65 assembler, ld65 linker) and the FCEUX emulator with the libraries it needs,
# all from the Ubuntu archive. The asset tools use the C64 Python venv (../.tools/venv),
# so run ../setup.sh first.
set -euo pipefail
cd "$(dirname "$0")"

T="$PWD/.tools"
mkdir -p "$T/root" "$T/fceux-home"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "== cc65 and FCEUX packages"
(cd "$tmp" && apt-get download cc65 fceux \
    libqt5core5t64 libqt5gui5t64 libqt5widgets5t64 libqt5dbus5t64 libqt5network5t64 libqt5svg5 \
    liblua5.1-0 libminizip1t64 libopengl0 libsdl2-2.0-0 libdouble-conversion3 libmd4c0 \
    libpcre2-16-0 libb2-1 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 \
    libxcb-xinerama0 libxcb-xinput0 libxcb-xkb1 libxkbcommon-x11-0 libxcb-util1)
for d in "$tmp"/*.deb; do dpkg -x "$d" "$T/root"; done

[ -x ../.tools/venv/bin/python ] || echo "Note: the Python venv is missing, run ../setup.sh too."

cat > "$T/env.sh" <<'ENV'
# source me: puts the local NES toolchain on PATH
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$T/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export QT_PLUGIN_PATH="$T/root/usr/lib/x86_64-linux-gnu/qt5/plugins"
export PATH="$T/root/usr/bin:$T/root/usr/games:$T/../../.tools/venv/bin:$PATH"
export FCEUX_HOME="$T/fceux-home"
ENV

echo "Done. Now: make && ./run.sh"
