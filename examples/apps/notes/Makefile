ROOT := ../../..
X2C ?= $(ROOT)/builds/0/x2c
PROGRAM ?= builds/notes
SQLITE := $(ROOT)/packages/sqlite

.PHONY: all build run check prepare package clean
all: build

build: package
	mkdir -p $(dir $(PROGRAM))
	$(X2C) build -o $(PROGRAM) --build-dir builds/app \
	  --package-dir $(ROOT)/packages notes.x

package:
	$(MAKE) -C $(SQLITE) build

prepare:
	$(MAKE) -C $(SQLITE) prepare

run: build
	cd $(ROOT) && $(abspath $(PROGRAM)) --store $(abspath notes.db)

check: build
	python3 tests/test_notes.py $(abspath $(PROGRAM))

clean:
	rm -rf builds
