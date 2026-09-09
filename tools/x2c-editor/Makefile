X2C_ROOT ?= ../..
X2C ?= $(X2C_ROOT)/builds/0/x2c
BUILD ?= builds
DEV_ARCHIVE := $(BUILD)/libx2c-dev.a
COMPILER_OBJECTS = $(filter-out $(X2C_ROOT)/builds/0/src/main.o,\
	$(wildcard $(X2C_ROOT)/builds/0/src/*.o))

.PHONY: all test clean

all: $(BUILD)/x2c-editor-worker

$(BUILD):
	@mkdir -p $@

$(DEV_ARCHIVE): $(COMPILER_OBJECTS) | $(BUILD)
	@$(X2C) build --plain --kind static-library --output $@ \
		$(COMPILER_OBJECTS)

$(BUILD)/x2c-editor-worker: worker.x $(DEV_ARCHIVE)
	@$(X2C) build --plain --build-dir $(BUILD)/worker-cc --output $@ \
		--x-include-dir $(X2C_ROOT)/src \
		--c-include-dir $(X2C_ROOT)/builds/0/src worker.x $(DEV_ARCHIVE)

test: all
	@X2C_EDITOR_WORKER="$(abspath $(BUILD)/x2c-editor-worker)" \
		node --test tests/worker.test.js

clean:
	@rm -rf $(BUILD)
