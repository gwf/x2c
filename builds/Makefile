###############################################################################
# Multi-stage recursive build system for X2C unified (.x) files
# Run with `make N` to build stage N
###############################################################################
include ../etc/make-command.mk
.SUFFIXES:
.PHONY: x2c test selftest stresstest clean
SHELL := /bin/bash -euo pipefail
MAKEFLAGS += -S
PRINT_LINE = @printf '%80s\n' | tr ' ' '\#'

x2c:
	mkdir -p 0
	$(MAKE) -f ../stage.mk -C 0
	$(PRINT_LINE)

test:
	@if [ ! -f 0/x2c ]; then \
		echo "Rebuilding stage 0/x2c prior to testing"; \
		$(MAKE) x2c; \
	else \
		echo "stage 0/x2c already built"; \
	fi
	mkdir -p 1
	$(MAKE) -f ../stage.mk -C 1
	$(PRINT_LINE)

selftest:
	mkdir -p 2
	$(MAKE) test
	$(MAKE) -f ../stage.mk -C 2
	$(PRINT_LINE)

stresstest:
	$(MAKE) clean
	$(MAKE) stage-3-complete

STRESS_STAGES := 0 1 2 3
.PHONY: stage-3-complete $(addprefix compiler-,$(STRESS_STAGES)) \
	$(addprefix commands-,$(STRESS_STAGES))

stage-3-complete: $(addprefix commands-,$(STRESS_STAGES))

compiler-1: compiler-0
compiler-2: compiler-1
compiler-3: compiler-2

$(addprefix compiler-,$(STRESS_STAGES)): compiler-%:
	mkdir -p $*
	$(MAKE) -f ../stage.mk -C $* x2c

# A stage's compiler and runtime are ready before either consumer starts.
$(addprefix commands-,$(STRESS_STAGES)): commands-%: compiler-%
	$(MAKE) -f ../stage.mk -C $* target
	$(PRINT_LINE)

clean:
	rm -rf [0-9]*
