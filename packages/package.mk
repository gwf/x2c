# Build one x2c package into an archive other programs can link.
#
# A package Makefile sets PACKAGE (and DEPENDENCY_PREFIX_VAR when the
# package has a dependency.json), includes this file, then sets
# PACKAGE_C_FLAGS and PACKAGE_LINK for its native dependency.
# tools/deps.py selects dependency-<os>-<arch>.json, dependency-<os>.json,
# or dependency.json for this host.
#
# Every src/*.x becomes builds/<unit>.h and builds/<unit>.c. The native
# driver compiles those files and src/*.c into builds/lib$(PACKAGE).a,
# retaining objects and dependency state under builds/cc.
# builds/$(PACKAGE).native.rsp holds the native arguments a consumer needs
# besides that archive, one argument per line. A package whose sources
# declare bodyless `meta` prototypes also builds builds/$(PACKAGE).module,
# the native module an import loads so compile-time code can call them.
#
# src/*.c is C the package itself must compile, such as a single-header
# library's instantiation unit. The driver keeps distinct object paths for
# native and generated files even when their basenames match.
#
# src/*.x translates in package mode, so its public names are $(PACKAGE)__*.
# Tests and examples sit outside src and reach them through
# `import "$(PACKAGE)"`, which also supplies their include path and archive.

ifndef PACKAGE
$(error package Makefile must set PACKAGE)
endif

ROOT ?= ../..
X2C ?= $(ROOT)/builds/0/x2c

# Pinned digests live in .sha256 manifests, checked with this, rather than
# as literals inside a recipe. Apple's make 3.81 on x86_64 drops bytes from
# a long continued recipe line, so an embedded 64-character digest can
# reach the shell corrupted and fail a package that is in fact correct.
CHECK_SHA256 = shasum -a 256 -c --quiet --strict
PACKAGE_SUPPORT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Translation flags; PACKAGE_C_FLAGS and PACKAGE_LINK are set per package.
PACKAGE_ROOT ?= ..
PACKAGE_X_FLAGS ?= --x-include-dir src --package-dir $(PACKAGE_ROOT)

# A package whose tests need a pty or a fixture server sets
# PACKAGE_TEST_COMMAND to the wrapper that runs one test program.
PACKAGE_TEST_COMMAND ?=

PACKAGE_SOURCES := $(wildcard src/*.x)
PACKAGE_NATIVE := $(wildcard src/*.c)
PACKAGE_HEADERS := $(PACKAGE_SOURCES:src/%.x=builds/%.h)
PACKAGE_GENERATED := $(PACKAGE_SOURCES:src/%.x=builds/%.c)
PACKAGE_ARCHIVE := builds/lib$(PACKAGE).a
PACKAGE_RESPONSE := builds/$(PACKAGE).native.rsp
PACKAGE_MODULE := builds/$(PACKAGE).module
PACKAGE_DEPS := $(CURDIR)/deps
PACKAGE_TESTS := $(wildcard tests/test-*.x)
PACKAGE_TEST_PROGRAMS := $(PACKAGE_TESTS:tests/%.x=builds/%)

.PHONY: all build test clean prepare deps bundle verify-pins
# Native action fingerprints own header, tool, and option reuse.
.PHONY: package-build-force

# Keep the generated C beside its header instead of letting make treat it
# as a deletable intermediate.
.SECONDARY: $(PACKAGE_SOURCES:src/%.x=builds/%.c)

all: test

package-build-force:

build: $(PACKAGE_HEADERS) $(PACKAGE_ARCHIVE) $(PACKAGE_RESPONSE) \
  $(PACKAGE_MODULE)

BUNDLE_DIR ?= builds/bundle
bundle: build
	"$(X2C)" script "$(PACKAGE_SUPPORT)tools/bundle" --package "$(PACKAGE)" \
	  --compiler "$(X2C)" --manifest "$(DEPENDENCY_MANIFEST)" \
	  --prefix "$(PACKAGE_PREFIX)" --output "$(BUNDLE_DIR)"

ifeq ($(wildcard dependency.json),)
prepare:
	@:
else
include $(PACKAGE_SUPPORT)dependency.mk

$(PACKAGE_SOURCES:src/%.x=builds/%.c) $(PACKAGE_HEADERS) \
  $(PACKAGE_ARCHIVE) $(PACKAGE_RESPONSE): $(DEPENDENCY_MANIFEST)

# dependency.mk owns download, verification, and the shared cache; this
# only exposes the prepared prefix at a stable path inside the package.
PACKAGE_PREFIX := $($(DEPENDENCY_PREFIX_VAR))

prepare: deps

deps:
	@ln -sfn $(PACKAGE_PREFIX) $@

# Nothing links against the dependency until its pinned public headers
# (headers-<os>.sha256 or headers.sha256) and license texts are verified.
PACKAGE_HEADER_PINS := $(firstword \
  $(wildcard headers-$(shell uname -s | tr A-Z a-z).sha256 headers.sha256))

$(PACKAGE_ARCHIVE): | verify-pins

verify-pins: $(DEPENDENCY_PREREQUISITE)
ifneq ($(PACKAGE_HEADER_PINS),)
	@cd $(PACKAGE_PREFIX)/include && \
	  $(CHECK_SHA256) $(CURDIR)/$(PACKAGE_HEADER_PINS)
endif
ifneq ($(wildcard licenses.sha256),)
	@$(CHECK_SHA256) licenses.sha256
endif
endif

builds/%.c builds/%.h: src/%.x | builds $(DEPENDENCY_PREREQUISITE)
	"$(X2C)" translate --out-dir builds $(PACKAGE_X_FLAGS) $<

# A consumer resolves the package through both files, so the archive carries
# the response file as a prerequisite; otherwise `make run` on a clean
# builds/ fails with "package is not built".
$(PACKAGE_ARCHIVE): $(PACKAGE_GENERATED) $(PACKAGE_NATIVE) \
  $(PACKAGE_RESPONSE) package-build-force | $(DEPENDENCY_PREREQUISITE)
	"$(X2C)" build --kind static-library --output $@ --build-dir builds/cc \
	  $(PACKAGE_C_FLAGS) $(PACKAGE_GENERATED) $(PACKAGE_NATIVE)

# The interfaces translation wrote record each of the package's own native
# `meta` prototypes; without one there is no module to build.
$(PACKAGE_MODULE): $(PACKAGE_GENERATED) package-build-force \
  | $(DEPENDENCY_PREREQUISITE)
	@if grep -qs 'native-meta "$(PACKAGE)__' \
	    $(PACKAGE_SOURCES:src/%.x=builds/%.xi); then \
	  "$(X2C)" build --kind meta-module --output $@ \
	    --build-dir builds/module $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) \
	    $(PACKAGE_LINK) $(PACKAGE_SOURCES) $(PACKAGE_NATIVE); \
	else rm -f $@; fi

# One argument per line, the response-file form the compiler reads.
$(PACKAGE_RESPONSE): Makefile | builds
	@printf '%s\n' $(PACKAGE_LINK) >$@

# --package-dir reads builds/$(PACKAGE).native.rsp, so a consumer never
# repeats PACKAGE_LINK; passing it again links the dependency twice.
builds/test-%: tests/test-%.x $(PACKAGE_ARCHIVE) | builds
	"$(X2C)" build --output $@ --build-dir builds/$* \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) \
	  --x-include-dir $(ROOT)/unittest \
	  $< $(ROOT)/unittest/test-support.x

builds/%: examples/%.x $(PACKAGE_ARCHIVE) | builds
	"$(X2C)" build --output $@ --build-dir builds/$*-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

# The test programs need only the archive, but a package whose tests passed
# has to be usable by a consumer, and that needs the response file too.
test: build $(PACKAGE_TEST_PROGRAMS)
	@for program in $(PACKAGE_TEST_PROGRAMS); do \
	  $(PACKAGE_TEST_COMMAND) ./$$program || exit 1; \
	done

builds:
	mkdir -p $@

clean:
	rm -rf builds deps

-include $(PACKAGE_SOURCES:src/%.x=builds/%.d)
