PACKAGE := yyjson
DEPENDENCY_PREFIX_VAR := YYJSON_PREFIX
include ../package.mk

PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(YYJSON_PREFIX)/include
PACKAGE_LINK := -L$(PACKAGE_DEPS)/lib -lyyjson

.PHONY: example short-example lisp-example run run-lisp

example: builds/release-catalog

short-example: builds/service-health

lisp-example: builds/inline-lisp

run: builds/service-health builds/release-catalog
	./builds/service-health
	./builds/release-catalog

run-lisp: builds/inline-lisp
	./builds/inline-lisp
