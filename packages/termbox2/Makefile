PACKAGE := termbox2
DEPENDENCY_PREFIX_VAR := TERMBOX2_PREFIX
include ../package.mk

TERMBOX2_INCLUDE := $(TERMBOX2_PREFIX)/include
PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(TERMBOX2_INCLUDE)
# glibc needs wcwidth plus the BSD declarations used by the x2c runtime.
ifeq ($(shell uname -s),Linux)
PACKAGE_C_FLAGS += -D _GNU_SOURCE
endif
# termbox2 is a single header; src/termbox2.c is already in the archive.
PACKAGE_LINK :=
PACKAGE_TEST_COMMAND := expect tests/run-test.expect

.PHONY: example short-example run run-interactive run-life-interactive

example: builds/incident-filter

short-example: builds/game-of-life

run: builds/game-of-life builds/incident-filter
	@expect tests/run-life.expect
	@expect tests/run-application.expect

run-life-interactive: builds/game-of-life
	./builds/game-of-life

run-interactive: builds/incident-filter
	./builds/incident-filter

builds/incident-filter: examples/incidents.log

# The termbox suite needs the deterministic tty and signal helper, which is
# test-only C and therefore stays out of the package archive.
builds/test-termbox: tests/test-termbox.x tests/terminal-test-helper.c \
		tests/terminal-test-helper.h $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/termbox \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) --c-include-dir tests \
	  --x-include-dir $(ROOT)/unittest \
	  $< tests/terminal-test-helper.c $(ROOT)/unittest/test-support.x
