#!/bin/bash
# Build and launch the NES version of Ghost Hour in FCEUX.
cd "$(dirname "$0")" || exit 1
source .tools/env.sh
make -s all || exit 1
exec fceux "$@" build/ghosthour.nes
