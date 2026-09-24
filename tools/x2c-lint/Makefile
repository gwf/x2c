ROOT := ../..
X2C := $(ROOT)/builds/0/x2c
BUILD := $(ROOT)/builds/0/lint
ARCHIVE := $(ROOT)/builds/0/libx2c-dev.a
IDENTITY := $(ROOT)/builds/0/commands/identity.x
SOURCES := x2c-lint.x lint.x tokens.x declarations.x

.PHONY: all compiler test clean

all: $(BUILD)/x2c-lint

# `make commands` rebuilds the compiler, archives its objects, and records
# its identity; the tool links that archive as the external commands do.
compiler:
	@$(MAKE) --no-print-directory -s -C $(ROOT) commands 1>&2

$(ARCHIVE) $(IDENTITY): compiler

$(BUILD)/x2c-lint: $(SOURCES) $(ARCHIVE) $(IDENTITY)
	@mkdir -p $(BUILD)
	@$(X2C) build --plain --build-dir $(BUILD)/cc --output $@ \
		--x-include-dir . --x-include-dir $(ROOT)/src \
		--c-include-dir $(ROOT)/builds/0/src \
		$(SOURCES) $(IDENTITY) $(ARCHIVE)

test: $(BUILD)/x2c-lint
	@sh tests/run.sh $(BUILD)/x2c-lint

clean:
	@rm -rf $(BUILD)
