PACKAGE := yyjson
DEPENDENCY_PREFIX_VAR := YYJSON_PREFIX
include ../package.mk

YYJSON_INCLUDE := $(YYJSON_PREFIX)/include

PACKAGE_C_FLAGS := --c-include-dir src --c-system-dir $(YYJSON_INCLUDE)
PACKAGE_LINK := -L$(PACKAGE_DEPS)/lib -lyyjson

.PHONY: example short-example lisp-example run run-lisp \
	verify-headers

# Nothing links against yyjson until its pinned header has been verified.
$(PACKAGE_ARCHIVE): | verify-headers

example: builds/release-catalog

short-example: builds/service-health

lisp-example: builds/inline-lisp

run: builds/service-health builds/release-catalog
	./builds/service-health
	./builds/release-catalog

run-lisp: builds/inline-lisp
	./builds/inline-lisp

verify-headers: $(DEPENDENCY_PREREQUISITE)
	@test "$$(shasum -a 256 $(YYJSON_INCLUDE)/yyjson.h | cut -d' ' -f1)" = \
	  175867c5493a5df648cec566717fa1c29aa2f6096f5f0cf1efad0b65e1f6d7b3

builds/release-catalog: examples/release-catalog.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/example \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/inline-lisp: examples/inline-lisp.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/inline-lisp-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/service-health: examples/service-health.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/service-health-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
