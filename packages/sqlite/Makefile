PACKAGE := sqlite
DEPENDENCY_PREFIX_VAR := SQLITE_PREFIX
include ../package.mk

SQLITE_INCLUDE := $(SQLITE_PREFIX)/include
PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(SQLITE_INCLUDE)
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
	@cd $(SQLITE_INCLUDE) && $(CHECK_SHA256) $(CURDIR)/headers.sha256

builds/observations: examples/observations.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/observations-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/observation-history: examples/observation-history.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/observation-history-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/inline-lisp: examples/inline-lisp.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/inline-lisp-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
