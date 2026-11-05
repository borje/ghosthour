#!/bin/bash
# Build and launch Ghost Hour in VICE.
cd "$(dirname "$0")" || exit 1
source .tools/env.sh
make -s all || exit 1
exec x64sc -default -directory "$VICE_DIR/C64:$VICE_DIR/DRIVES:$VICE_DIR" \
    -autostartprgmode 1 +confirmonexit "$@" build/ghosthour.prg
