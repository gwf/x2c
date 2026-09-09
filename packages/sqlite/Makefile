PACKAGE := sqlite
DEPENDENCY_PREFIX_VAR := SQLITE_PREFIX
include ../package.mk

SQLITE_INCLUDE := $(SQLITE_PREFIX)/include
PACKAGE_C_FLAGS := --c-include-dir src --c-system-dir $(SQLITE_INCLUDE)
PACKAGE_LINK := -L$(PACKAGE_DEPS)/lib -lsqlite3 -lm -pthread

.PHONY: example short-example lisp-example run run-lisp verify-headers

$(PACKAGE_ARCHIVE): | verify-headers

example: builds/observation-history

short-example: builds/observations

lisp-example: builds/inline-lisp

run: builds/observations builds/observation-history
	./builds/observations
	rm -f builds/observation-history.db
	./builds/observation-history

run-lisp: builds/inline-lisp
	./builds/inline-lisp

verify-headers: $(DEPENDENCY_PREREQUISITE)
	@test "$$(shasum -a 256 $(SQLITE_INCLUDE)/sqlite3.h | cut -d' ' -f1)" = \
	  919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d
	@test "$$(shasum -a 256 $(SQLITE_INCLUDE)/sqlite3ext.h | cut -d' ' -f1)" = \
	  ac9645e5c9ff0cf176efdd6e75cb5e98f46295d38e02db5c4d208826a39ab4be

builds/observations: examples/observations.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/observations-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/observation-history: examples/observation-history.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/observation-history-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/inline-lisp: examples/inline-lisp.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/inline-lisp-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
