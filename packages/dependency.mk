# Shared integration dependency cache.

ifndef DEPENDENCY_PREFIX_VAR
$(error package Makefile must set DEPENDENCY_PREFIX_VAR)
endif

DEPENDENCY_MANIFEST ?= dependency.json
DEPS_TOOL ?= python3 $(ROOT)/packages/tools/deps.py
DEPENDENCY_CACHE_PREFIX := $(shell \
	$(DEPS_TOOL) path $(DEPENDENCY_MANIFEST) prefix)

ifeq ($($(DEPENDENCY_PREFIX_VAR)),)
$(eval $(DEPENDENCY_PREFIX_VAR) := $(DEPENDENCY_CACHE_PREFIX))
DEPENDENCY_PREREQUISITE := prepare
else
DEPENDENCY_PREREQUISITE :=
endif

.PHONY: prepare verify-dependency dependency-path

prepare:
	$(DEPS_TOOL) prepare $(DEPENDENCY_MANIFEST)

ifeq ($(DEPENDENCY_PREREQUISITE),prepare)
verify-dependency: $(DEPENDENCY_PREREQUISITE)
	$(DEPS_TOOL) verify $(DEPENDENCY_MANIFEST)
else
verify-dependency:
	@:
endif

dependency-path:
	@$(DEPS_TOOL) path $(DEPENDENCY_MANIFEST) prefix
