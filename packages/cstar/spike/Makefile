# Milestone 1 feasibility spike for C* verification. Not part of any
# aggregate check; needs the pinned C* 0.5.7 release and a cstar_examples
# checkout whose proof libraries were built by `cstarc verify` once.
#
#   CSTAR_HOME=~/.cstar CSTAR_EXAMPLES=~/src/cstar_examples make run
#
X2C ?= ../../../builds/0/x2c
CSTAR_HOME ?= $(HOME)/.cstar
CSTAR_EXAMPLES ?= $(HOME)/src/cstar_examples

VERIF := $(CSTAR_EXAMPLES)/_verif
PROOF_OBJECTS := $(VERIF)/proof/proof_user__lib.o \
  $(VERIF)/proof/proof_sl__lib.o $(VERIF)/proof/proof_backward__lib.o \
  $(VERIF)/proof/proof_backward_sl__lib.o \
  $(VERIF)/proof/proof_symexec__lib.o \
  $(VERIF)/userlib/qcp/veriftime__lib.o
LINK := -L$(CSTAR_HOME)/lib -Wl,-force_load,$(CSTAR_HOME)/lib/libcstar.a \
  -lsac -Wl,-rpath,$(CSTAR_HOME)/lib -lm -lstdc++ \
  $(addprefix -Xlinker ,$(PROOF_OBJECTS))

ROOT := ../../..
DEV_ARCHIVE := $(ROOT)/tools/x2c-graph/builds/libx2c-dev.a

.PHONY: build run extract clean

build: builds/abs.proof builds/cstar-extract builds/annotated

builds/abs.proof: abs.proof.x cstar-shim.h
	$(X2C) build --plain --output $@ --build-dir builds/abs \
	  --c-include-dir . $(LINK) $<

# Expects a running `hol_light_server` (`cstarc server`). Exit codes:
# 0 verified, 1 obligations remain, 2 incomplete.
run: builds/abs.proof
	CSTAR_HOME=$(CSTAR_HOME) ./builds/abs.proof
	CSTAR_HOME=$(CSTAR_HOME) ./builds/abs.proof --stop-early; test $$? = 2
	CSTAR_HOME=$(CSTAR_HOME) ./builds/abs.proof --unbounded; test $$? = 1

# Annotation extraction: the annotated program keeps its behavior, the
# extractor reads the records and proves body correspondence, and a
# variant with an outer decorator is refused.
builds/annotated: extract/abs.x extract/cstar.xmacro extract/cstar-annotations.x
	$(X2C) build --plain --output $@ --build-dir builds/annotated-build \
	  extract/abs.x extract/cstar-annotations.x

$(DEV_ARCHIVE):
	$(MAKE) -C $(ROOT)/tools/x2c-graph builds/libx2c-dev.a

builds/cstar-extract: extract/cstar-extract.x $(DEV_ARCHIVE)
	$(X2C) build --plain --output $@ --build-dir builds/extract \
	  --x-include-dir extract --x-include-dir $(ROOT)/src \
	  --c-include-dir $(ROOT)/builds/0/src $< $(DEV_ARCHIVE)

extract: builds/annotated builds/cstar-extract
	./builds/annotated
	cd extract && X2C_ROOT=$(abspath $(ROOT)) ../builds/cstar-extract abs.x
	cd extract && X2C_ROOT=$(abspath $(ROOT)) \
	  ../builds/cstar-extract abs-mismatch.x >/dev/null; test $$? = 1

clean:
	rm -rf builds
