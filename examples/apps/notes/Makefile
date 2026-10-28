ROOT := ../../..
X2C ?= $(ROOT)/builds/0/x2c
PROGRAM ?= builds/notes
SQLITE := $(ROOT)/packages/sqlite
DEPS_TOOL := python3 $(ROOT)/packages/tools/deps.py
SQLITE_PREFIX ?= $(shell $(DEPS_TOOL) path $(SQLITE)/dependency.json prefix)

.PHONY: all build run check prepare package clean
all: build

build: package
	mkdir -p $(dir $(PROGRAM))
	$(X2C) build -o $(PROGRAM) --build-dir builds/app \
	  --package-dir $(ROOT)/packages --c-include-dir $(SQLITE)/src \
	  --c-include-dir $(SQLITE_PREFIX)/include notes.x

package:
	$(MAKE) -C $(SQLITE) build

prepare:
	$(MAKE) -C $(SQLITE) prepare

run: build
	cd $(ROOT) && $(abspath $(PROGRAM))

check: build
	python3 tests/test_notes.py $(abspath $(PROGRAM))

clean:
	rm -rf builds
