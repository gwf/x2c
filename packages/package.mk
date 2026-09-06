# Build one x2c package into an archive other programs can link.
#
# A package Makefile sets PACKAGE (and DEPENDENCY_PREFIX_VAR when the
# package has a dependency.json), includes this file, then sets
# PACKAGE_C_FLAGS and PACKAGE_LINK for its native dependency.
#
# Every src/*.x becomes builds/<unit>.h and builds/<unit>.o, and every
# src/*.c becomes builds/native-<unit>.o; all objects become
# builds/lib$(PACKAGE).a. builds/$(PACKAGE).link holds the one line of link
# flags a consumer needs besides that archive.
#
# src/*.c is C the package itself must compile, such as a single-header
# library's instantiation unit. Its object name carries a prefix because a
# package named <name> already generates builds/<name>.c from src/<name>.x.
#
# src/*.x translates in package mode, so its public names are $(PACKAGE)__*.
# Tests and examples sit outside src and reach them through
# `import "$(PACKAGE)"`, which also supplies their include path and archive.

ifndef PACKAGE
$(error package Makefile must set PACKAGE)
endif

ROOT ?= ../..
X2C ?= $(ROOT)/builds/0/x2c

# Translation flags; PACKAGE_C_FLAGS and PACKAGE_LINK are set per package.
PACKAGE_ROOT ?= ..
PACKAGE_X_FLAGS ?= --x-include-dir src --package-dir $(PACKAGE_ROOT)

# A package whose tests need a pty or a fixture server sets
# PACKAGE_TEST_COMMAND to the wrapper that runs one test program.
PACKAGE_TEST_COMMAND ?=

PACKAGE_SOURCES := $(wildcard src/*.x)
PACKAGE_NATIVE := $(wildcard src/*.c)
PACKAGE_HEADERS := $(PACKAGE_SOURCES:src/%.x=builds/%.h)
PACKAGE_OBJECTS := $(PACKAGE_SOURCES:src/%.x=builds/%.o) \
	$(PACKAGE_NATIVE:src/%.c=builds/native-%.o)
PACKAGE_ARCHIVE := builds/lib$(PACKAGE).a
PACKAGE_DEPS := $(CURDIR)/deps
PACKAGE_TESTS := $(wildcard tests/test-*.x)
PACKAGE_TEST_PROGRAMS := $(PACKAGE_TESTS:tests/%.x=builds/%)

.PHONY: all build test clean prepare deps

# Keep the generated C beside its header instead of letting make treat it
# as a deletable intermediate.
.SECONDARY: $(PACKAGE_SOURCES:src/%.x=builds/%.c)

all: test

build: $(PACKAGE_HEADERS) $(PACKAGE_ARCHIVE) builds/$(PACKAGE).link

ifeq ($(wildcard dependency.json),)
prepare:
	@:
else
include ../dependency.mk

$(PACKAGE_SOURCES:src/%.x=builds/%.c) $(PACKAGE_HEADERS) \
  $(PACKAGE_OBJECTS) builds/$(PACKAGE).link: $(DEPENDENCY_MANIFEST)

# dependency.mk owns download, verification, and the shared cache; this
# only exposes the prepared prefix at a stable path inside the package.
PACKAGE_PREFIX := $($(DEPENDENCY_PREFIX_VAR))

prepare: deps

deps:
	@ln -sfn $(PACKAGE_PREFIX) $@
endif

builds/%.c builds/%.h: src/%.x | builds $(DEPENDENCY_PREREQUISITE)
	$(X2C) translate --out-dir builds $(PACKAGE_X_FLAGS) $<

builds/%.o: builds/%.c | $(DEPENDENCY_PREREQUISITE)
	$(X2C) build --compile-only --output $@ --build-dir builds/cc \
	  $(PACKAGE_C_FLAGS) $<

builds/native-%.o: src/%.c | builds $(DEPENDENCY_PREREQUISITE)
	$(X2C) build --compile-only --output $@ --build-dir builds/cc \
	  $(PACKAGE_C_FLAGS) $<

# A consumer resolves the package through both files, so the archive carries
# the link line as a prerequisite; otherwise `make run` on a clean builds/
# fails with "package is not built".
$(PACKAGE_ARCHIVE): $(PACKAGE_OBJECTS) builds/$(PACKAGE).link
	$(X2C) build --kind static-library --output $@ $(PACKAGE_OBJECTS)

builds/$(PACKAGE).link: Makefile | builds
	@printf '%s\n' '$(PACKAGE_LINK)' >$@

# --package-dir reads builds/$(PACKAGE).link, so a consumer never repeats
# PACKAGE_LINK; passing it again links the dependency twice.
builds/test-%: tests/test-%.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/$* \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) \
	  --x-include-dir $(ROOT)/unittest \
	  $< $(ROOT)/unittest/test-support.x

# The test programs need only the archive, but a package whose tests passed
# has to be usable by a consumer, and that needs the .link file too.
test: build $(PACKAGE_TEST_PROGRAMS)
	@for program in $(PACKAGE_TEST_PROGRAMS); do \
	  $(PACKAGE_TEST_COMMAND) ./$$program || exit 1; \
	done

builds:
	mkdir -p $@

clean:
	rm -rf builds deps

-include $(PACKAGE_SOURCES:src/%.x=builds/%.d)
