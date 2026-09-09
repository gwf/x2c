X2C_ROOT := x2c
X2C := $(X2C_ROOT)/builds/0/x2c
BUILD := builds
DEV_ARCHIVE := $(BUILD)/libx2c-dev.a
COMPILER_OBJECTS = $(filter-out $(X2C_ROOT)/builds/0/src/main.o,\
	$(wildcard $(X2C_ROOT)/builds/0/src/*.o))
X_FLAGS := --x-include-dir . --x-include-dir $(X2C_ROOT)/src \
	--c-include-dir $(X2C_ROOT)/builds/0/src
SRC_SOURCES := $(sort $(wildcard $(X2C_ROOT)/src/*.x))
LIB_SOURCES := $(sort $(filter-out $(X2C_ROOT)/lib/x2c.x,\
	$(wildcard $(X2C_ROOT)/lib/*.x)))
X2C_SOURCES := $(SRC_SOURCES) $(LIB_SOURCES)
DATASET_DIR ?= $(BUILD)/datasets

.PHONY: all clean datasets run test x2c-build

all: $(BUILD)/x2c-graph

x2c-build:
	@$(MAKE) --no-print-directory -s -C $(X2C_ROOT) build 1>&2

$(BUILD):
	@mkdir -p $@

$(DEV_ARCHIVE): x2c-build | $(BUILD)
	@$(X2C) build --plain --kind static-library --output $@ \
		$(COMPILER_OBJECTS)

$(BUILD)/x2c-graph: x2c-graph.x flows.x lifetime.x loop-allocations.x \
		targets.x $(DEV_ARCHIVE)
	@$(X2C) build --plain --build-dir $(BUILD)/graph-cc \
		--output $@ $(X_FLAGS) x2c-graph.x flows.x lifetime.x \
		loop-allocations.x targets.x $(DEV_ARCHIVE)

$(BUILD)/ast-parity: tests/ast-parity.x $(DEV_ARCHIVE)
	@$(X2C) build --plain --build-dir $(BUILD)/ast-parity-cc \
		--output $@ $(X_FLAGS) tests/ast-parity.x \
		$(DEV_ARCHIVE)

run: $(BUILD)/x2c-graph
	@$(BUILD)/x2c-graph digest $(X2C_SOURCES)
	@$(BUILD)/x2c-graph architecture $(X2C_SOURCES)
	@$(BUILD)/x2c-graph between src/compiler.x src/macros.x \
		$(X2C_SOURCES)
	@$(BUILD)/x2c-graph field Compiler conforms $(X2C_SOURCES)
	@$(BUILD)/x2c-graph field-sites Compiler conforms $(X2C_SOURCES)
	@$(BUILD)/x2c-graph sites Sym_seed_var_tags $(X2C_SOURCES)
	@$(BUILD)/x2c-graph sites _package_merge $(X2C_SOURCES)
	@$(BUILD)/x2c-graph sites Compiler_generate_protocol_adapters \
		$(X2C_SOURCES)
	@$(BUILD)/x2c-graph lifetime-escapes $(X2C_SOURCES)
	@$(BUILD)/x2c-graph flows List_replace Compiler_bind_syntax \
		$(X2C_SOURCES)
	@$(BUILD)/x2c-graph compare Compiler_parse_top_level \
		Compiler_expand_macro_invocation_node \
		_install_declarator_node _finish_function Sym_push_scope \
		Compiler_record_declaration_visibility \
		Compiler_resolve_expression Compiler_finish_return_statement \
		Compiler_publish_protocol_node -- $(X2C_SOURCES)

datasets: $(BUILD)/x2c-graph
	@$(BUILD)/x2c-graph datasets $(DATASET_DIR) \
		$(SRC_SOURCES) -- $(LIB_SOURCES)

test: $(BUILD)/x2c-graph $(BUILD)/ast-parity
	@sh tests/run.sh

clean:
	@rm -rf $(BUILD)
