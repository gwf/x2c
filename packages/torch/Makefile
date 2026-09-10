PACKAGE := torch
DEPENDENCY_PREFIX_VAR := TORCH_PREFIX

# generated/ holds the tier-1 operator bindings tools/gen-ops.py produces
# from the pinned schema; both translation and compilation read it.
PACKAGE_X_FLAGS := --x-include-dir src --x-include-dir generated \
	--package-dir ..
include ../package.mk

TORCH_INCLUDE := $(TORCH_PREFIX)/include
TORCH_LIB := $(TORCH_PREFIX)/lib
CXX ?= clang++
SHIM := builds/torch-shim.o
OPS := builds/xt_ops.o
CXX_FLAGS := -std=c++17 -O2 -I$(TORCH_INCLUDE) \
	-I$(TORCH_INCLUDE)/torch/csrc/api/include -Isrc -Igenerated

# libtorch is C++ with no stable C++ ABI and no C API. The shim and the
# generated bindings are the two C++ translation units here; they are
# compiled outside `x2c build`, which only compiles src/*.c, and linked as
# ordinary objects. Every program that links them also links the pinned
# dylibs by rpath: static libtorch is not a practical option (whole-archive
# operator registration, multi-hundred-MB binaries), so a torch program is
# not self-contained.
PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir generated
PACKAGE_LINK := -Xlinker $(CURDIR)/$(SHIM) -Xlinker $(CURDIR)/$(OPS) \
	-L$(TORCH_LIB) \
	-ltorch -ltorch_cpu -lc10 -lc++ -Wl,-rpath,$(TORCH_LIB)
NATIVE := $(SHIM) $(OPS)

.PHONY: example short-example run verify-python gen-ops verify-ops

build: $(NATIVE)

$(SHIM): src/torch-shim.cpp src/torch-2.10.h | builds $(DEPENDENCY_PREREQUISITE)
	$(CXX) $(CXX_FLAGS) -c $< -o $@

# generated/xt_ops.cpp is an output of tools/gen-ops.py, checked in beside
# the schema it came from; `make gen-ops` rewrites it and src/torch-ops.x.
$(OPS): generated/xt_ops.cpp generated/xt_ops.h generated/xt_ops_support.h \
    src/torch-2.10.h | builds $(DEPENDENCY_PREREQUISITE)
	$(CXX) $(CXX_FLAGS) -c $< -o $@

gen-ops:
	python3 tools/gen-ops.py

# Programs link the native objects directly through PACKAGE_LINK, so a
# shim change has to relink them; the archive alone does not carry it.
$(PACKAGE_ARCHIVE): $(NATIVE)
$(PACKAGE_TEST_PROGRAMS): $(NATIVE)

short-example: builds/fit-line

example: builds/mlp

run: builds/fit-line builds/mlp
	./builds/fit-line
	./builds/mlp

builds/fit-line: examples/fit-line.x $(PACKAGE_ARCHIVE) $(NATIVE) | builds
	$(X2C) build --output $@ --build-dir builds/fit-line-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/mlp: examples/mlp.x $(PACKAGE_ARCHIVE) $(NATIVE) | builds
	$(X2C) build --output $@ --build-dir builds/mlp-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

# The Python agreement checks are not part of `test`: they need an
# installed CPython with the pinned torch wheel.
TORCH_PYTHON ?= /Users/gary/Git/Bonsai-demo/.venv/bin/python

verify-python: builds/checkpoint-roundtrip
	TORCH_PYTHON="$(TORCH_PYTHON)" python3 tests/verify-python.py

verify-ops: builds/verify-ops
	TORCH_PYTHON="$(TORCH_PYTHON)" python3 tests/verify-ops.py

builds/checkpoint-roundtrip: tests/checkpoint-roundtrip.x $(PACKAGE_ARCHIVE) \
  $(NATIVE) | builds
	$(X2C) build --output $@ --build-dir builds/checkpoint-roundtrip-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/verify-ops: tests/verify-ops.x $(PACKAGE_ARCHIVE) $(NATIVE) | builds
	$(X2C) build --output $@ --build-dir builds/verify-ops-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
