# Ghost Hour NES build. The local toolchain is set up by ./setup.sh.
SHELL   := /bin/bash
TOOLS   := source .tools/env.sh &&
PY_SRC  := $(wildcard tools/*.py) $(wildcard ../tools/*.py)
ROM     := build/ghosthour.nes
GEN     := build/chr_in.bin build/chr_out.bin build/chr_spr.bin build/gen_const.inc build/gen_data.inc

all: $(ROM)

$(GEN) &: $(PY_SRC)
	mkdir -p build
	$(TOOLS) python tools/check_map.py
	$(TOOLS) python tools/build_assets.py build

build/main.o: src/main.s $(GEN)
	$(TOOLS) ca65 -I build --bin-include-dir build -g -o $@ src/main.s

$(ROM): build/main.o src/unrom.cfg
	$(TOOLS) ld65 -C src/unrom.cfg -o $@ --dbgfile build/ghosthour.dbg -Ln build/labels.txt build/main.o

run: all
	./run.sh

clean:
	rm -rf build

.PHONY: all run clean
