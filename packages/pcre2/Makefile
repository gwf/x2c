PACKAGE := pcre2
DEPENDENCY_PREFIX_VAR := PCRE2_PREFIX
include ../package.mk

PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(PCRE2_PREFIX)/include
PACKAGE_LINK := -L$(PACKAGE_DEPS)/lib -lpcre2-posix -lpcre2-8

.PHONY: example short-example lisp-example run run-lisp

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

builds/gallery-imports: ../../examples/power/imports.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/gallery-imports-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
