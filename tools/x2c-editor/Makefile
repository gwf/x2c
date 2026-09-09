X2C_ROOT ?= ../..
X2C ?= $(X2C_ROOT)/builds/0/x2c
BUILD ?= builds

.PHONY: all test clean FORCE

all: $(BUILD)/x2c-editor-worker

$(BUILD):
	@mkdir -p "$@"

# Preserve the old worker path without another compiler archive or executable.
$(BUILD)/x2c-editor-worker: FORCE | $(BUILD)
	@printf '%s\n' '#!/bin/sh' 'exec "$(abspath $(X2C))" editor "$$@"' >"$@"
	@chmod +x "$@"

test: all
	@X2C_EDITOR_COMPILER="$(abspath $(X2C))" \
		node --test tests/worker.test.js
	@X2C_EDITOR_WORKER="$(abspath $(BUILD)/x2c-editor-worker)" \
		node --test tests/worker.test.js

clean:
	@rm -rf "$(BUILD)"
