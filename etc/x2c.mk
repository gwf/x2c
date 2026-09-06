###############################################################################
# x2c.mk - Makefile variables and rules for building x2c programs.
# include this file in your Makefile with:
# include {x2c-dir}/etc/x2c.mk
###############################################################################
SOURCE 		 ?= .
BUILD		   ?= build
include ../etc/build-config.mk
###############################################################################
STAGE       = 0
X2CPATH     = ../builds/$(STAGE)
X2C         = $(X2CPATH)/x2c
INCLUDE     = ../include
LDFLAGS    += -L$(X2CPATH) -lx2c -lm
LDFLAGS    += $(BUILD_LDFLAGS)
CFLAGS     += $(BUILD_CFLAGS)
CFLAGS     += -iquote $(INCLUDE)
X2CFLAGS   += --out-dir $(BUILD)
MAKEFLAGS  += -S

.SUFFIXES: .x .c .h .o .d
.DELETE_ON_ERROR:
.PRECIOUS: $(BUILD)/%.c $(BUILD)/%.d $(BUILD)/%.c.d $(BUILD)/%.h
.PHONY: default clean headers
###############################################################################
# Source files and generated files
X_FILES  = $(wildcard $(SOURCE)/*.x)

# Generated files
C_FILES  = $(patsubst $(SOURCE)/%.x,$(BUILD)/%.c,$(X_FILES))
H_FILES  = $(patsubst $(SOURCE)/%.x,$(BUILD)/%.h,$(X_FILES))
X_DEPS   = $(patsubst $(SOURCE)/%.x,$(BUILD)/%.d,$(X_FILES))
C_DEPS   = $(patsubst $(SOURCE)/%.x,$(BUILD)/%.c.d,$(X_FILES))
###############################################################################
# Default target
_default: default

# Generate all headers first
headers: $(H_FILES)

# create build directory
$(BUILD):
	mkdir -p $(BUILD)

# Translate .x files in one batch invocation: $? passes only the sources
# newer than the stamp, so a clean build is one process (the symbol
# snapshot loads once) and an incremental build retranslates only what
# changed.  Translation output is a function of the compiler binary and
# the symbol snapshot it loads at runtime, so both are prerequisites
# and either changing forces a full retranslation; a missing generated
# .c/.h forces its source back into the batch (self-healing).
ifneq ($(strip $(X_FILES)),)
X2C_TRANSLATE_DEPS = $(X2C) ../etc/symbols.xlisp
MISSING_GENERATED = $(filter-out \
	$(wildcard $(BUILD)/*.c $(BUILD)/*.h),$(C_FILES) $(H_FILES))
MISSING_X = $(sort \
	$(patsubst $(BUILD)/%.c,$(SOURCE)/%.x, \
		$(filter %.c,$(MISSING_GENERATED))) \
	$(patsubst $(BUILD)/%.h,$(SOURCE)/%.x, \
		$(filter %.h,$(MISSING_GENERATED))))

$(BUILD)/.translated: $(X_FILES) $(X2C_TRANSLATE_DEPS) | $(BUILD)
	$(X2C) translate $(X2CFLAGS) \
		$(if $(filter-out $(X_FILES) FORCE-TRANSLATE,$?),$(X_FILES), \
		$(sort $(filter $(X_FILES),$?) $(MISSING_X)))
	@touch $@
$(C_FILES) $(H_FILES): $(BUILD)/.translated

# Included x2c prerequisites live on the generated C/H targets. The stamp
# still owns clean-build batching; this rule retranslates only a unit whose
# discovered prerequisite is newer than its generated C.
$(BUILD)/%.c: $(SOURCE)/%.x
	$(if $(filter-out $(BUILD)/.translated,$?), \
		$(X2C) translate $(X2CFLAGS) $<)

$(BUILD)/%.h: $(BUILD)/%.c

ifneq ($(strip $(MISSING_X)),)
$(BUILD)/.translated: FORCE-TRANSLATE
.PHONY: FORCE-TRANSLATE
FORCE-TRANSLATE:
endif
endif

# compile object files; ensure matching header exists and emit dependency file
$(BUILD)/%.o: $(BUILD)/%.c | $(BUILD)/%.h
	$(CC) $(CFLAGS) -MMD -MP -MF $(BUILD)/$*.c.d -MT $@ -c $< -o $@

-include $(X_DEPS) $(C_DEPS)
