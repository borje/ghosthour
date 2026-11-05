# Ghost Hour build. The local toolchain is set up by `source .tools/env.sh`.
SHELL   := /bin/bash
TOOLS   := source .tools/env.sh &&
PY_SRC  := $(wildcard tools/*.py)
PRG     := build/ghosthour.prg
D64     := build/ghosthour.d64

all: $(D64)

build/gen.asm: $(PY_SRC)
	mkdir -p build
	$(TOOLS) python tools/check_map.py
	$(TOOLS) python tools/build_assets.py build

$(PRG): src/main.asm build/gen.asm
	$(TOOLS) acme src/main.asm
	@$(TOOLS) python tools/report_size.py

$(D64): $(PRG)
	$(TOOLS) c1541 -silent on -format "ghost hour,gh" d64 $(D64) -write $(PRG) "ghost hour" >/dev/null

debug: build/gen.asm
	$(TOOLS) acme -DDEBUG=1 -f cbm -o build/ghosthour_debug.prg src/main.asm 2>&1 | grep -v "Output file already chosen" || true

run: all
	./run.sh

clean:
	rm -rf build

.PHONY: all run clean debug
