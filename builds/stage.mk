###############################################################################
# Multi-stage build template for X2C unified (.x) files
# Run with something like: make -f ../stage.mk -C 0
###############################################################################
include ../../etc/make-command.mk
include ../../etc/build-config.mk
DIRECTORY    := $(notdir $(CURDIR))
# Stages are numeric directories; an invalid invocation must fail.
ifeq ($(shell printf '%s\n' "$(DIRECTORY)" | grep -E '^[0-9]+$$'),)
$(error stage.mk requires a numeric stage directory: $(CURDIR))
endif
ifeq ($(DIRECTORY), 0)
	X2C_COMPILER := ../../bin/x2c
else
	PREV := $(shell expr $(DIRECTORY) - 1)
	X2C_COMPILER := ../$(PREV)/x2c
endif
###############################################################################
ROOT             := ../..
# Source directories - using X files from scratch/
BIN_SOURCE       = $(ROOT)/src
LIB_SOURCE       = $(ROOT)/lib
# Build directories
BIN_BUILD        = src
LIB_BUILD        = lib
# Library and binary names
LIBRARY          = libx2c.a
BINARY           = x2c
COMPILER_LIBRARY = libx2c-dev.a
COMMAND_BUILD    = commands/build
BUILD_COMMAND    = libexec/x2c-build
COMMAND_IDENTITY = commands/identity.x
CC               ?= cc
AR               ?= ar
ARFLAGS          ?= rv
# From stage 1 the compiler's own sources build clean: an x2c warning or
# region finding fails translation, and a C compiler warning fails
# compilation. Stage 0 stays lenient because the checked-in bootstrap
# translates it, possibly warning about what the new source fixed, and
# because source installs build it with whatever host C compiler they have.
# Its compiler also links every shipped `meta` function the sources call
# (src/linked-meta.x), so a call that would stage one with the C compiler
# instead fails translation with "this function cannot run at compile time".
ifneq ($(DIRECTORY),0)
STRICT_CFLAGS    = -Werror
STRICT_X2C_FLAGS = --fatal-warnings
STRICT_X2C_ENV   = X2C_CC=false
endif
CFLAGS           += $(BUILD_CFLAGS) $(STRICT_CFLAGS)
# The bootstrap compiles each file from its own directory. Spelling __FILE__
# the same way, as glibc's assert does, lets stage 0 reproduce the bootstrap
# executable, whose identity the interfaces it wrote here carry.
CFLAGS           += -fmacro-prefix-map=$(LIB_BUILD)/=
CFLAGS           += -fmacro-prefix-map=$(BIN_BUILD)/=
CFLAGS           += $(EXTRA_CFLAGS)
X2C_FLAGS        ?=
# A translation batch must finish before the compiles it feeds start, so it
# uses BUILD_JOBS workers rather than the one job x2c assumes under Make.
# A later -j in X2C_FLAGS overrides it.
X2C_TRANSLATE    = $(STRICT_X2C_ENV) $(X2C_COMPILER) translate \
	-j $(BUILD_JOBS) $(STRICT_X2C_FLAGS) $(X2C_FLAGS)
# A native module binds to the compiler's own runtime, so the compiler links
# the whole runtime archive, and a Linux executable exports its functions
# only when asked.
UNAME_S          := $(shell uname -s)
RUNTIME_LINK     = -lx2c
ifeq ($(UNAME_S),Darwin)
RUNTIME_LINK     = -Wl,-force_load,$(LIBRARY)
endif
ifeq ($(UNAME_S),Linux)
RUNTIME_LINK     = -Wl,--whole-archive -lx2c -Wl,--no-whole-archive
LDFLAGS          += -rdynamic
endif
LDFLAGS          += $(RUNTIME_LINK)
LDFLAGS          += $(BUILD_LDFLAGS)
MAKEFLAGS        += -S
###############################################################################
.SUFFIXES: # Disable built-in suffix rules
.SUFFIXES: .x .h .o .d
.DELETE_ON_ERROR:
.PRECIOUS: $(LIB_BUILD)/%.c $(LIB_BUILD)/%.d $(LIB_BUILD)/%.c.d
.PRECIOUS: $(BIN_BUILD)/%.c $(BIN_BUILD)/%.d $(BIN_BUILD)/%.c.d
###############################################################################
# Library source files and generated files
LIB_X_FILES  = $(shell $(ROOT)/tools/sources.sh --root $(ROOT) --area lib)
LIB_X_NAMES  = $(sort $(notdir $(LIB_X_FILES)))
LIB_H_FILES  = $(patsubst %.x,$(LIB_BUILD)/%.h,$(LIB_X_NAMES))
LIB_C_FILES  = $(patsubst %.x,$(LIB_BUILD)/%.c,$(LIB_X_NAMES))
LIB_XI_FILES = $(patsubst %.x,$(LIB_BUILD)/%.xi,$(LIB_X_NAMES))
LIB_OBJECTS  = $(patsubst %.x,$(LIB_BUILD)/%.o,$(LIB_X_NAMES))
LIB_X_DEPS   = $(patsubst %.x,$(LIB_BUILD)/%.d,$(LIB_X_NAMES))
LIB_C_DEPS   = $(patsubst %.x,$(LIB_BUILD)/%.c.d,$(LIB_X_NAMES))
###############################################################################
# Binary source files and generated files
BIN_X_FILES  = $(shell $(ROOT)/tools/sources.sh --root $(ROOT))
# Components are independent units; keep their unique artifact names flat.
BIN_X_NAMES  = $(sort $(notdir $(BIN_X_FILES)))
# Module members trigger the batch but are not separate translation units.
BIN_X_INPUTS := $(shell find $(BIN_SOURCE) -type f -name '*.x')
BIN_H_FILES  = $(patsubst %.x,$(BIN_BUILD)/%.h,$(BIN_X_NAMES))
BIN_C_FILES  = $(patsubst %.x,$(BIN_BUILD)/%.c,$(BIN_X_NAMES))
BIN_XI_FILES = $(patsubst %.x,$(BIN_BUILD)/%.xi,$(BIN_X_NAMES))
BIN_OBJECTS  = $(patsubst %.x,$(BIN_BUILD)/%.o,$(BIN_X_NAMES))
BIN_X_DEPS   = $(patsubst %.x,$(BIN_BUILD)/%.d,$(BIN_X_NAMES))
BIN_C_DEPS   = $(patsubst %.x,$(BIN_BUILD)/%.c.d,$(BIN_X_NAMES))
###############################################################################
# Default action
target: $(LIBRARY) $(BINARY) $(BUILD_COMMAND)

# Generate all headers first
headers: $(LIB_H_FILES) $(BIN_H_FILES)

# create library build directory
$(LIB_BUILD):
	mkdir -p $(LIB_BUILD)
# Translate library .x files in one batch invocation, always passing every
# source.  A unit's generated C depends on the declarations of every unit
# it includes, as its own .d records, so retranslating just the edited .x
# leaves its dependents holding C generated against the previous shape of
# a shared struct.  That mixed-generation build links and then fails at
# runtime.  Translation output is also a function of the compiler binary
# and the runtime declarations it replays from the library batch, so the
# compiler and every library source are prerequisites; a missing generated
# .c/.h/.xi forces the batch to run.  Imported macro and compile-time Lisp
# sources are inputs to the same translation, so they join the list;
# without them a macro-only edit leaves every generated file untouched.
# Each batch writes a .xi interface beside every unit's C; the library batch
# produces lib/x2c.xi, which later batches and stages replay as the prelude.
X2C_TRANSLATE_DEPS = $(X2C_COMPILER) $(shell find $(LIB_SOURCE) -name '*.x') \
	$(wildcard $(ROOT)/etc/init.xlisp $(ROOT)/etc/compiler-sdk.xlisp \
		$(ROOT)/etc/lisp-bindings.xlisp \
		$(ROOT)/etc/lisp-values.xlisp) \
	$(wildcard $(LIB_SOURCE)/*.xlisp) \
	$(wildcard $(ROOT)/etc/*.x)
LIB_MISSING_GENERATED = $(filter-out \
	$(wildcard $(LIB_BUILD)/*.c $(LIB_BUILD)/*.h $(LIB_BUILD)/*.xi), \
	$(LIB_C_FILES) $(LIB_H_FILES) $(LIB_XI_FILES))

$(LIB_BUILD)/.translated: $(X2C_TRANSLATE_DEPS) | $(LIB_BUILD)
	$(X2C_TRANSLATE) --out-dir $(LIB_BUILD) \
		$(LIB_X_FILES)
	@touch $@
$(LIB_C_FILES) $(LIB_H_FILES): $(LIB_BUILD)/.translated

# The stamp owns translation. A clean parallel build may decide that these
# targets are missing before the batch finishes, so their recipes must not
# start overlapping per-file translations after the stamp has produced them.
$(LIB_BUILD)/%.c:
	@:

$(LIB_BUILD)/%.h: $(LIB_BUILD)/%.c

ifneq ($(strip $(LIB_MISSING_GENERATED)),)
$(LIB_BUILD)/.translated: LIB-FORCE-TRANSLATE
.PHONY: LIB-FORCE-TRANSLATE
LIB-FORCE-TRANSLATE:
endif
# compile library object files
$(LIB_BUILD)/%.o: $(LIB_BUILD)/%.c | $(LIB_H_FILES) $(LIB_BUILD)/.module-headers
	$(CC) $(CFLAGS) -iquote $(LIB_BUILD) -MMD -MP \
		-MF $(LIB_BUILD)/$*.c.d -MT $@ -c $< -o $@

# create library archive
$(LIBRARY): $(LIB_OBJECTS)
	$(RM) $@
	$(AR) $(ARFLAGS) $@ $^
###############################################################################
# create binary build directory
$(BIN_BUILD):
	mkdir -p $(BIN_BUILD)
# Translate binary .x files in one batch invocation (see library note).
BIN_MISSING_GENERATED = $(filter-out \
	$(wildcard $(BIN_BUILD)/*.c $(BIN_BUILD)/*.h $(BIN_BUILD)/*.xi), \
	$(BIN_C_FILES) $(BIN_H_FILES) $(BIN_XI_FILES))

$(BIN_BUILD)/.translated: $(BIN_X_INPUTS) $(X2C_TRANSLATE_DEPS) \
		| $(BIN_BUILD)
	$(X2C_TRANSLATE) --out-dir $(BIN_BUILD) \
		$(BIN_X_FILES)
	@touch $@
$(BIN_C_FILES) $(BIN_H_FILES): $(BIN_BUILD)/.translated

# See the library rule above: the batch stamp owns every generated file.
$(BIN_BUILD)/%.c:
	@:

$(BIN_BUILD)/%.h: $(BIN_BUILD)/%.c

ifneq ($(strip $(BIN_MISSING_GENERATED)),)
$(BIN_BUILD)/.translated: BIN-FORCE-TRANSLATE
.PHONY: BIN-FORCE-TRANSLATE
BIN-FORCE-TRANSLATE:
endif
# Preserve source include paths while retaining flat generated artifacts.
define module_headers
$(1)/.module-headers: $(3)
	@find $(1) -mindepth 2 -name '*.h' -delete
	@for source in $(4); do \
		relative=$$$${source#$(2)/}; \
		case "$$$$relative" in */*) \
			name=$$$${relative##*/}; directory=$$$${relative%/*}; \
			mkdir -p "$(1)/$$$$directory"; \
			printf '#include "../%s.h"\n' "$$$${name%.x}" > "$(1)/$$$${relative%.x}.h" ;; \
		esac; \
	done
	@touch $$@
endef
$(eval $(call module_headers,$(LIB_BUILD),$(LIB_SOURCE),$(LIB_H_FILES),$(LIB_X_FILES)))
$(eval $(call module_headers,$(BIN_BUILD),$(BIN_SOURCE),$(BIN_H_FILES),$(BIN_X_FILES)))

# compile binary object files
$(BIN_BUILD)/%.o: $(BIN_BUILD)/%.c | $(LIB_H_FILES) $(LIB_BUILD)/.module-headers $(BIN_BUILD)/.module-headers
	$(CC) $(CFLAGS) -iquote $(LIB_BUILD) -iquote $(BIN_BUILD) \
		-MMD -MP -MF $(BIN_BUILD)/$*.c.d -MT $@ -c $< -o $@
# link binary executable
$(BINARY): $(BIN_OBJECTS) $(LIBRARY)
	$(CC) $(BIN_OBJECTS) -L. $(LDFLAGS) -lm -o $(BINARY)
###############################################################################
# The build command cannot build itself. Translate it with this stage's newly
# linked compiler, then use the same native flags and archives as the driver.
# Other commands reuse this archive and embedded identity from the root Makefile.
COMMAND_X_FILES = $(wildcard $(ROOT)/commands/build/*.x) $(COMMAND_IDENTITY)
COMMAND_STEMS = $(notdir $(basename $(COMMAND_X_FILES)))
COMMAND_C_FILES = $(addprefix $(COMMAND_BUILD)/,$(addsuffix .c,$(COMMAND_STEMS)))
COMMAND_H_FILES = $(COMMAND_C_FILES:.c=.h)
COMMAND_XI_FILES = $(COMMAND_C_FILES:.c=.xi)
COMMAND_OBJECTS = $(COMMAND_C_FILES:.c=.o)
COMMAND_X_DEPS = $(COMMAND_C_FILES:.c=.d)
COMMAND_C_DEPS = $(COMMAND_C_FILES:.c=.c.d)
COMMAND_MISSING_GENERATED = $(filter-out \
	$(wildcard $(COMMAND_BUILD)/*.c $(COMMAND_BUILD)/*.h $(COMMAND_BUILD)/*.xi), \
	$(COMMAND_C_FILES) $(COMMAND_H_FILES) $(COMMAND_XI_FILES))

$(COMPILER_LIBRARY): $(filter-out $(BIN_BUILD)/main.o,$(BIN_OBJECTS)) ../stage.mk
	$(RM) $@
	$(AR) $(ARFLAGS) $@ $(filter-out $(BIN_BUILD)/main.o,$(BIN_OBJECTS))

$(COMMAND_IDENTITY): $(BINARY)
	@mkdir -p commands
	@set -e; identity=`./$(BINARY) env identity`; \
	  printf 'String x2c_embedded_identity(void) => "%s";\n' \
	    "$$identity" > $@.tmp; \
	  if ! cmp -s $@.tmp $@; then mv $@.tmp $@; \
	  else rm $@.tmp; fi

$(COMMAND_BUILD):
	mkdir -p $@

$(COMMAND_BUILD)/.translated: $(BINARY) $(COMMAND_X_FILES) $(BIN_X_INPUTS) \
		$(LIB_X_FILES) $(X2C_TRANSLATE_DEPS) ../stage.mk | $(COMMAND_BUILD)
	$(STRICT_X2C_ENV) ./$(BINARY) translate -j $(BUILD_JOBS) \
		$(STRICT_X2C_FLAGS) $(X2C_FLAGS) --out-dir $(COMMAND_BUILD) \
		--x-include-dir $(ROOT) --x-include-dir $(BIN_SOURCE) \
		$(COMMAND_X_FILES)
	@touch $@

$(COMMAND_C_FILES) $(COMMAND_H_FILES): $(COMMAND_BUILD)/.translated

ifneq ($(strip $(COMMAND_MISSING_GENERATED)),)
$(COMMAND_BUILD)/.translated: COMMAND-FORCE-TRANSLATE
.PHONY: COMMAND-FORCE-TRANSLATE
COMMAND-FORCE-TRANSLATE:
endif

$(COMMAND_OBJECTS): $(COMMAND_BUILD)/.translated

$(COMMAND_BUILD)/%.o: $(COMMAND_BUILD)/%.c | $(COMMAND_H_FILES) $(BIN_H_FILES) $(LIB_H_FILES) $(BIN_BUILD)/.module-headers $(LIB_BUILD)/.module-headers
	$(CC) $(CFLAGS) -iquote $(COMMAND_BUILD) -iquote $(BIN_BUILD) \
		-iquote $(LIB_BUILD) -iquote $(ROOT)/include/x2c \
		-MMD -MP -MF $(COMMAND_BUILD)/$*.c.d -MT $@ -c $< -o $@

$(BUILD_COMMAND): $(COMMAND_OBJECTS) $(COMPILER_LIBRARY) $(LIBRARY)
	@mkdir -p libexec
	$(CC) $(COMMAND_OBJECTS) $(COMPILER_LIBRARY) -L. $(LDFLAGS) -lm -o $@
###############################################################################
# clean build directories
clean:
	rm -rf $(LIB_BUILD) $(BIN_BUILD) commands libexec
# remove all build files
realclean: clean
	rm -rf $(LIBRARY) $(BINARY) $(COMPILER_LIBRARY)
###############################################################################
# Include dependency files
-include $(LIB_X_DEPS) $(LIB_C_DEPS) $(BIN_X_DEPS) $(BIN_C_DEPS) \
	$(COMMAND_X_DEPS) $(COMMAND_C_DEPS)
