PACKAGE := pcre2
DEPENDENCY_PREFIX_VAR := PCRE2_PREFIX
include ../package.mk

PCRE2_INCLUDE := $(PCRE2_PREFIX)/include
PACKAGE_C_FLAGS := --c-include-dir src --c-system-dir $(PCRE2_INCLUDE)
PACKAGE_LINK := -L$(PACKAGE_DEPS)/lib -lpcre2-posix -lpcre2-8

.PHONY: example short-example lisp-example run run-lisp \
	verify-headers

# Nothing links against PCRE2 until its pinned headers have been verified.
$(PACKAGE_ARCHIVE): | verify-headers

example: builds/request-report

short-example: builds/parse-log

lisp-example: builds/inline-lisp

run: builds/parse-log builds/request-report builds/gallery-imports
	./builds/parse-log
	./builds/request-report
	python3 ../../tools/check-gallery-examples.py
	./builds/gallery-imports > builds/gallery-imports.stdout
	diff -u ../../examples/expected/power-imports.stdout builds/gallery-imports.stdout

run-lisp: builds/inline-lisp
	./builds/inline-lisp

verify-headers: $(DEPENDENCY_PREREQUISITE)
	@test "$$(shasum -a 256 $(PCRE2_INCLUDE)/pcre2.h | cut -d' ' -f1)" = \
	  20d70c58a3b1f205836ceade32af6179a887f24749b8036620f079919d37b11e
	@test "$$(shasum -a 256 $(PCRE2_INCLUDE)/pcre2posix.h | cut -d' ' -f1)" = \
	  4e3f99d21b10f3168fa562c6345e2b387a1a83f8bd2a35784b2832f4dc4d9444

builds/request-report: examples/request-report.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/request \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/inline-lisp: examples/inline-lisp.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/inline-lisp-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/parse-log: examples/parse-log.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/parse-log-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/gallery-imports: ../../examples/power/imports.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/gallery-imports-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
