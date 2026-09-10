PACKAGE := torch
DEPENDENCY_PREFIX_VAR := TORCH_PREFIX
include ../package.mk

TORCH_INCLUDE := $(TORCH_PREFIX)/include
TORCH_LIB := $(TORCH_PREFIX)/lib
CXX ?= clang++
SHIM := builds/torch-shim.o

# libtorch is C++ with no stable C++ ABI and no C API. The shim is the one
# C++ translation unit here; it is compiled outside `x2c build`, which only
# compiles src/*.c, and linked as an ordinary object. Every program that
# links it also links the pinned dylibs by rpath: static libtorch is not a
# practical option (whole-archive operator registration, multi-hundred-MB
# binaries), so a torch program is not self-contained.
PACKAGE_C_FLAGS := --c-include-dir src
PACKAGE_LINK := -Xlinker $(CURDIR)/$(SHIM) -L$(TORCH_LIB) \
	-ltorch -ltorch_cpu -lc10 -lc++ -Wl,-rpath,$(TORCH_LIB)

.PHONY: example short-example run verify-python

build: $(SHIM)

$(SHIM): src/torch-shim.cpp src/torch-2.10.h | builds $(DEPENDENCY_PREREQUISITE)
	$(CXX) -std=c++17 -O2 -I$(TORCH_INCLUDE) \
	  -I$(TORCH_INCLUDE)/torch/csrc/api/include -c $< -o $@

$(PACKAGE_ARCHIVE): $(SHIM)

short-example: builds/fit-line

example: builds/fit-line

run: builds/fit-line
	./builds/fit-line

builds/fit-line: examples/fit-line.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/fit-line-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
