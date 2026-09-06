ROOT := ../../..
X2C := $(ROOT)/builds/0/x2c
PACKAGES := $(ROOT)/packages
CURL_DIR := $(PACKAGES)/libcurl
JSON_DIR := $(PACKAGES)/yyjson
DEPS_TOOL := python3 $(PACKAGES)/tools/deps.py
CURL_PREFIX ?= $(abspath $(CURL_DIR)/deps)
YYJSON_PREFIX ?= $(shell $(DEPS_TOOL) path $(JSON_DIR)/dependency.json prefix)

# The two packages arrive through --package-dir: an import pulls in each
# archive, its generated header, and its own link line. This directory is
# listed first and its program is named after it, so the compiler treats
# this program as the consumer it is instead of looking for an archive
# named after the enclosing packages directory.
COMMON := --package-dir $(ROOT)/examples/packages --package-dir $(PACKAGES) \
	--c-system-dir $(CURL_PREFIX)/include \
	--c-system-dir $(YYJSON_PREFIX)/include

.PHONY: all build run test prepare packages clean

all: test

build: builds/releases

run: builds/releases
	./builds/releases

test: builds/releases
	python3 tools/run-fixture.py builds/releases

prepare:
	$(MAKE) -C $(CURL_DIR) prepare
	$(MAKE) -C $(JSON_DIR) prepare

builds/releases: http-json-releases.x | builds packages
	$(X2C) build --output $@ --build-dir builds/app $(COMMON) $<

packages:
	$(MAKE) -C $(CURL_DIR) build
	$(MAKE) -C $(JSON_DIR) build

builds:
	mkdir -p $@

clean:
	rm -rf builds
