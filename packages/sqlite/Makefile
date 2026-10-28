PACKAGE := sqlite
DEPENDENCY_PREFIX_VAR := SQLITE_PREFIX
include ../package.mk

PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(SQLITE_PREFIX)/include
PACKAGE_LINK := --c-include-dir $(PACKAGE_DEPS)/include \
                -L$(PACKAGE_DEPS)/lib -lsqlite3 -lm -pthread

.PHONY: example short-example lisp-example run run-lisp

example: builds/observation-history

short-example: builds/observations

lisp-example: builds/inline-lisp

run: builds/observations builds/observation-history
	./builds/observations
	rm -f builds/observation-history.db
	./builds/observation-history

run-lisp: builds/inline-lisp
	./builds/inline-lisp
