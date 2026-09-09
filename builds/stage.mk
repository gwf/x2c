###############################################################################
# Multi-stage build template for X2C unified (.x) files
# Run with something like: make -f ../stage.mk -C 0
###############################################################################
include ../../etc/make-command.mk
include ../../etc/build-config.mk
CWD          := $(shell pwd)
DIRECTORY    := $(shell basename $(CWD))
# test if the directory is not a number
ifeq ($(shell echo $(DIRECTORY) | grep -q [0-9]; echo $$?), 1)
stop:
	@echo "This Makefile is not meant to be run in this directory"
	@exit 0
else ifeq ($(DIRECTORY), 0)
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
CC               ?= cc
AR               ?= ar
ARFLAGS          ?= rv
CFLAGS           += $(BUILD_CFLAGS)
CFLAGS           += $(EXTRA_CFLAGS)
X2C_FLAGS        ?=
LDFLAGS          += -lx2c
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
LIB_X_FILES  = $(wildcard $(LIB_SOURCE)/*.x)
LIB_H_FILES  = $(patsubst $(LIB_SOURCE)/%.x,$(LIB_BUILD)/%.h,$(LIB_X_FILES))
LIB_C_FILES  = $(patsubst $(LIB_SOURCE)/%.x,$(LIB_BUILD)/%.c,$(LIB_X_FILES))
LIB_OBJECTS  = $(patsubst $(LIB_SOURCE)/%.x,$(LIB_BUILD)/%.o,$(LIB_X_FILES))
LIB_X_DEPS   = $(patsubst $(LIB_SOURCE)/%.x,$(LIB_BUILD)/%.d,$(LIB_X_FILES))
LIB_C_DEPS   = $(patsubst $(LIB_SOURCE)/%.x,$(LIB_BUILD)/%.c.d,$(LIB_X_FILES))
###############################################################################
# Binary source files and generated files
BIN_X_FILES  = $(wildcard $(BIN_SOURCE)/*.x)
BIN_H_FILES  = $(patsubst $(BIN_SOURCE)/%.x,$(BIN_BUILD)/%.h,$(BIN_X_FILES))
BIN_C_FILES  = $(patsubst $(BIN_SOURCE)/%.x,$(BIN_BUILD)/%.c,$(BIN_X_FILES))
BIN_OBJECTS  = $(patsubst $(BIN_SOURCE)/%.x,$(BIN_BUILD)/%.o,$(BIN_X_FILES))
BIN_X_DEPS   = $(patsubst $(BIN_SOURCE)/%.x,$(BIN_BUILD)/%.d,$(BIN_X_FILES))
BIN_C_DEPS   = $(patsubst $(BIN_SOURCE)/%.x,$(BIN_BUILD)/%.c.d,$(BIN_X_FILES))
###############################################################################
# Default action
target: $(LIBRARY) $(BINARY)

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
# and the symbol snapshot it loads, so both are prerequisites; a missing
# generated .c/.h forces the batch to run.  Imported macro and compile-time
# Lisp sources are inputs to the same translation, so they join the list;
# without them a macro-only edit leaves every generated file untouched.
X2C_TRANSLATE_DEPS = $(X2C_COMPILER) $(ROOT)/etc/symbols.xlisp \
	$(wildcard $(ROOT)/etc/header-symbols.xlisp \
		$(ROOT)/etc/init.xlisp $(ROOT)/etc/compiler-sdk.xlisp \
		$(ROOT)/etc/builtin-macros.xlisp \
		$(ROOT)/etc/lisp-bindings.xlisp) \
	$(wildcard $(LIB_SOURCE)/*.xlisp) \
	$(wildcard $(LIB_SOURCE)/*.xmacro) $(wildcard $(BIN_SOURCE)/*.xmacro)
LIB_MISSING_GENERATED = $(filter-out \
	$(wildcard $(LIB_BUILD)/*.c $(LIB_BUILD)/*.h), \
	$(LIB_C_FILES) $(LIB_H_FILES))
LIB_MISSING_X = $(sort \
	$(patsubst $(LIB_BUILD)/%.c,$(LIB_SOURCE)/%.x, \
		$(filter %.c,$(LIB_MISSING_GENERATED))) \
	$(patsubst $(LIB_BUILD)/%.h,$(LIB_SOURCE)/%.x, \
		$(filter %.h,$(LIB_MISSING_GENERATED))))

$(LIB_BUILD)/.translated: $(LIB_X_FILES) $(X2C_TRANSLATE_DEPS) \
		| $(LIB_BUILD)
	$(X2C_COMPILER) translate $(X2C_FLAGS) --out-dir $(LIB_BUILD) \
		$(LIB_X_FILES)
	@touch $@
$(LIB_C_FILES) $(LIB_H_FILES): $(LIB_BUILD)/.translated

# The stamp owns translation. A clean parallel build may decide that these
# targets are missing before the batch finishes, so their recipes must not
# start overlapping per-file translations after the stamp has produced them.
$(LIB_BUILD)/%.c: $(LIB_SOURCE)/%.x
	@:

$(LIB_BUILD)/%.h: $(LIB_BUILD)/%.c

ifneq ($(strip $(LIB_MISSING_X)),)
$(LIB_BUILD)/.translated: LIB-FORCE-TRANSLATE
.PHONY: LIB-FORCE-TRANSLATE
LIB-FORCE-TRANSLATE:
endif
# compile library object files
$(LIB_BUILD)/%.o: $(LIB_BUILD)/%.c | $(LIB_H_FILES)
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
	$(wildcard $(BIN_BUILD)/*.c $(BIN_BUILD)/*.h), \
	$(BIN_C_FILES) $(BIN_H_FILES))
BIN_MISSING_X = $(sort \
	$(patsubst $(BIN_BUILD)/%.c,$(BIN_SOURCE)/%.x, \
		$(filter %.c,$(BIN_MISSING_GENERATED))) \
	$(patsubst $(BIN_BUILD)/%.h,$(BIN_SOURCE)/%.x, \
		$(filter %.h,$(BIN_MISSING_GENERATED))))

$(BIN_BUILD)/.translated: $(BIN_X_FILES) $(X2C_TRANSLATE_DEPS) \
		| $(BIN_BUILD)
	$(X2C_COMPILER) translate $(X2C_FLAGS) --out-dir $(BIN_BUILD) \
		$(BIN_X_FILES)
	@touch $@
$(BIN_C_FILES) $(BIN_H_FILES): $(BIN_BUILD)/.translated

# See the library rule above: the batch stamp owns every generated file.
$(BIN_BUILD)/%.c: $(BIN_SOURCE)/%.x
	@:

$(BIN_BUILD)/%.h: $(BIN_BUILD)/%.c

ifneq ($(strip $(BIN_MISSING_X)),)
$(BIN_BUILD)/.translated: BIN-FORCE-TRANSLATE
.PHONY: BIN-FORCE-TRANSLATE
BIN-FORCE-TRANSLATE:
endif
# compile binary object files
$(BIN_BUILD)/%.o: $(BIN_BUILD)/%.c | $(LIB_H_FILES)
	$(CC) $(CFLAGS) -iquote $(LIB_BUILD) -iquote $(BIN_BUILD) \
		-MMD -MP -MF $(BIN_BUILD)/$*.c.d -MT $@ -c $< -o $@
# link binary executable
$(BINARY): $(BIN_OBJECTS) $(LIBRARY)
	$(CC) $(BIN_OBJECTS) -L. $(LDFLAGS) -lm -o $(BINARY)
###############################################################################
# clean build directories
clean:
	rm -rf $(LIB_BUILD) $(BIN_BUILD)
# remove all build files
realclean: clean
	rm -rf $(LIBRARY) $(BINARY)
###############################################################################
# Include dependency files
-include $(LIB_X_DEPS) $(LIB_C_DEPS) $(BIN_X_DEPS) $(BIN_C_DEPS)
