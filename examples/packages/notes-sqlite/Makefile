ROOT := ../../..
X2C := $(ROOT)/builds/0/x2c
SQLITE := $(ROOT)/packages/sqlite
DEPS_TOOL := python3 $(ROOT)/packages/tools/deps.py
SQLITE_PREFIX ?= $(shell $(DEPS_TOOL) path $(SQLITE)/dependency.json prefix)
SOURCES := notes-sqlite.x $(ROOT)/examples/apps/notes/service.x \
  $(ROOT)/examples/apps/notes/store.x $(ROOT)/examples/apps/notes/record.x

.PHONY: all build run test prepare packages clean
all: test
build: builds/notes-sqlite
run: builds/notes-sqlite
	cd $(ROOT) && examples/packages/notes-sqlite/builds/notes-sqlite

test: builds/notes-sqlite
	./builds/notes-sqlite --check

prepare:
	$(MAKE) -C $(SQLITE) prepare

packages:
	$(MAKE) -C $(SQLITE) build

builds/notes-sqlite: $(SOURCES) | packages
	mkdir -p builds
	$(X2C) build -o $@ --build-dir builds/app \
	  --package-dir $(ROOT)/examples/packages --package-dir $(ROOT)/packages \
	  --c-include-dir $(SQLITE)/src --c-include-dir $(SQLITE_PREFIX)/include \
	  $(SOURCES)

clean:
	rm -rf builds
