###############################################################################
# build-config.mk - Centralized build configuration for debug/optimize modes
# This file defines compiler flags and build settings based on the current mode
###############################################################################

# Default to debug only when the tracked build-mode file is unavailable.
# Resolve repository root relative to this configuration file so includes work
# regardless of the invoking Makefile's location.
BUILD_CONFIG_MK := $(abspath $(lastword $(MAKEFILE_LIST)))
BUILD_CONFIG_DIR := $(dir $(BUILD_CONFIG_MK))
REPO_ROOT := $(abspath $(BUILD_CONFIG_DIR)/..)
BUILD_MODE_FILE := $(REPO_ROOT)/etc/build-mode
BUILD_MODE ?= $(shell cat $(BUILD_MODE_FILE) 2>/dev/null || echo debug)
BUILD_LTO ?= 0

# Define compiler flags for each mode
ifeq ($(BUILD_MODE),debug)
    CFLAGS_DEBUG := -g
    CFLAGS_OPTIMIZE :=
else ifeq ($(BUILD_MODE),optimize)
    CFLAGS_DEBUG :=
    CFLAGS_OPTIMIZE := -O2 #-D'log_debug(...)=/* no-op */'
else
    $(error Unknown build mode: $(BUILD_MODE). Valid modes: debug, optimize)
endif

ifeq ($(BUILD_LTO),1)
    CFLAGS_LTO := -flto
    LDFLAGS_LTO := -flto
else ifeq ($(BUILD_LTO),0)
    CFLAGS_LTO :=
    LDFLAGS_LTO :=
else
    $(error Unknown BUILD_LTO value: $(BUILD_LTO). Valid values: 0, 1)
endif

# Dynamic description based on current mode
BUILD_DESCRIPTION := $(shell \
    if [ "$(BUILD_MODE)" = "debug" ]; then \
        echo "Debug build with symbols and warnings"; \
    else  \
        echo "Optimized build for performance"; \
    fi \
)

# Combined flags for use in Makefiles
BUILD_CFLAGS := -fsigned-char -pthread $(CFLAGS_DEBUG) $(CFLAGS_OPTIMIZE) \
	$(CFLAGS_LTO)
BUILD_LDFLAGS := -pthread $(LDFLAGS_LTO)

# Export for sub-makes
export BUILD_MODE BUILD_LTO BUILD_CFLAGS BUILD_LDFLAGS BUILD_DESCRIPTION
