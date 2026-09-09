PACKAGE := cstar
DEPENDENCY_PREFIX_VAR := CSTAR_PREFIX
include ../package.mk

# The pinned runtime. -pthread is unnecessary and the macOS linker rejects it
# through -Xlinker; libcstar.a needs force_load because the proof objects
# reference it in both directions.
CSTAR_PROOF_LIBS := proof_user proof_sl proof_backward proof_backward_sl \
	proof_symexec veriftime common operational list array_core index array
CSTAR_PROOF_OBJECTS := $(patsubst %,$(PACKAGE_DEPS)/lib/cstar-proof/%__lib.o,\
	$(CSTAR_PROOF_LIBS))

# proof/ is this package's own C* proof library, not a cached dependency:
# it is package source, and cstarc compiles it against the cstar_examples
# include root the prepared prefix carries.
CSTAR_HELPERS := $(CURDIR)/builds/x2c_array_helpers__lib.o

PACKAGE_C_FLAGS := --c-include-dir src
PACKAGE_LINK := -L$(PACKAGE_DEPS)/lib \
	-Wl,-force_load,$(PACKAGE_DEPS)/lib/libcstar.a -lsac \
	-Wl,-rpath,$(PACKAGE_DEPS)/lib -lstdc++ -lm \
	$(addprefix -Xlinker ,$(CSTAR_PROOF_OBJECTS) $(CSTAR_HELPERS))

# cstar-verify links the compiler as a library, exactly as tools/x2c-graph
# does, and is rebuilt with the x2c revision that parses the verified unit.
DEV_ARCHIVE := builds/libx2c-dev.a
COMPILER_OBJECTS = $(filter-out $(ROOT)/builds/0/src/main.o,\
	$(wildcard $(ROOT)/builds/0/src/*.o))
TOOL_X_FLAGS := --x-include-dir tools --x-include-dir $(ROOT)/src \
	--c-include-dir $(ROOT)/builds/0/src
TOOL_SOURCES := tools/cstar-verify.x tools/adapter.x

CSTAR_HOME ?= $(PACKAGE_DEPS)
CSTAR_VERIFY := X2C=$(abspath $(X2C)) X2C_PACKAGES=$(abspath $(PACKAGE_ROOT)) \
	CSTAR_HOME=$(CSTAR_HOME) ./builds/cstar-verify

EXAMPLE_PROGRAMS := builds/abs builds/abs-unbounded builds/twice \
	builds/swap builds/swap-unowned builds/clear builds/clear-offbyone \
	builds/fill builds/fill-falseinv builds/scale

.PHONY: examples run verify tool

tool: builds/cstar-verify

build: $(CSTAR_HELPERS)

# cstarc resolves every `#require` against its project root, so it runs in
# the prepared cstar_examples tree and reads this package's source by
# absolute path. The module name of an input outside that root is its stem,
# which is why the initializer is `_cst_x2c_array_helpers_init`.
$(CSTAR_HELPERS): proof/x2c_array_helpers.c proof/x2c_array_helpers.h | builds
	cd $(PACKAGE_DEPS)/share/cstar_examples && \
	  CSTAR_HOME=$(CSTAR_HOME) $(PACKAGE_DEPS)/bin/cstarc verify \
	    --cl=$@ $(CURDIR)/proof/x2c_array_helpers.c

$(DEV_ARCHIVE): | builds
	$(X2C) build --plain --kind static-library --output $@ \
	  $(COMPILER_OBJECTS)

builds/cstar-verify: $(TOOL_SOURCES) $(DEV_ARCHIVE) | builds
	$(X2C) build --plain --build-dir builds/verify-cc --output $@ \
	  $(TOOL_X_FLAGS) $(TOOL_SOURCES) $(DEV_ARCHIVE)

# Every example is an ordinary program: it builds and runs with no package
# archive, no verification runtime, and no proof declarations.
builds/%: examples/%.x | builds
	$(X2C) build --output $@ --build-dir builds/$*-cc \
	  --x-include-dir src $<

examples: $(EXAMPLE_PROGRAMS)

run: $(EXAMPLE_PROGRAMS)
	@for program in $(EXAMPLE_PROGRAMS); do ./$$program || exit 1; done

test: builds/cstar-verify

# The prover examples. Each run starts its own hol_light_server on a free
# port and stops it again; CSTAR_PORT reuses an already running one.
verify: builds/cstar-verify
	$(CSTAR_VERIFY) examples/abs.x
	$(CSTAR_VERIFY) examples/twice.x
	$(CSTAR_VERIFY) examples/swap.x
	$(CSTAR_VERIFY) examples/scale.x
	$(CSTAR_VERIFY) examples/clear.x
	$(CSTAR_VERIFY) examples/fill.x
	@echo "--- the next four must not verify"
	$(CSTAR_VERIFY) examples/abs-unbounded.x; test $$? = 1
	$(CSTAR_VERIFY) examples/swap-unowned.x; test $$? = 3
	$(CSTAR_VERIFY) examples/clear-offbyone.x; test $$? = 3
	$(CSTAR_VERIFY) examples/fill-falseinv.x; test $$? = 3
