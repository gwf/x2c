PACKAGE := raylib
DEPENDENCY_PREFIX_VAR := RAYLIB_PREFIX
include ../package.mk

RAYLIB_INCLUDE := $(RAYLIB_PREFIX)/include
RAYLIB_LIBRARY := $(RAYLIB_PREFIX)/lib/libraylib.a

# --c-system-dir is a C-compiler flag. x2c's own symbol collection needs -I
# to read raylib.h; without it Vector2 is not a type and neither src/raylib.x
# nor a consumer that names a raylib type parses.
PACKAGE_X_FLAGS += -I $(RAYLIB_INCLUDE)
PACKAGE_C_FLAGS := --c-include-dir src --c-system-dir $(RAYLIB_INCLUDE) \
	-I $(RAYLIB_INCLUDE)
PACKAGE_LINK := $(RAYLIB_LIBRARY) -l pthread

SHORT_PNG := builds/climate-trends.png
SHEET_PNG := builds/texture-sheet.png
SHORT_SHA256 := 6b84cd531131f426a66df4df7bc80bf9c63f466ee3d508a62dbae25206233894
SHEET_SHA256 := 191db3d0b232681db4aa9822863efcfd6771d03908e9c33a45087d475414a54b

# The windowed profile. `make run-interactive` prepares it, rebuilds the
# package against it, and opens a real window; nothing else uses it, because
# a window needs a WindowServer connection and no gate has one. The two
# profiles are separate cache entries and neither disturbs the other.
DESKTOP_MANIFEST := dependency-desktop.json
DESKTOP_PREFIX = $(shell $(DEPS_TOOL) path $(DESKTOP_MANIFEST) prefix)
DESKTOP_FRAMEWORKS := -Wl,-framework,OpenGL -Wl,-framework,Cocoa \
	-Wl,-framework,IOKit -Wl,-framework,CoreVideo

.PHONY: example short-example run verify verify-headers \
	prepare-desktop run-interactive

example: builds/texture-sheet

short-example: builds/climate-trends

run: builds/climate-trends builds/texture-sheet
	./builds/climate-trends
	./builds/texture-sheet

# PNG signature, IHDR length and tag, then width and height big-endian.
verify: verify-headers run test builds/live-chart
	@test "$$(od -An -tx1 -N24 $(SHORT_PNG) | tr -d '[:space:]')" = \
	  "89504e470d0a1a0a0000000d49484452000005a000000280"
	@test "$$(od -An -tx1 -N24 $(SHEET_PNG) | tr -d '[:space:]')" = \
	  "89504e470d0a1a0a0000000d494844520000038400000258"
	@test "$$(shasum -a 256 $(SHORT_PNG) | cut -d' ' -f1)" = \
	  "$(SHORT_SHA256)"
	@test "$$(shasum -a 256 $(SHEET_PNG) | cut -d' ' -f1)" = \
	  "$(SHEET_SHA256)"
	@file $(SHORT_PNG) $(SHEET_PNG)

verify-headers: $(DEPENDENCY_PREREQUISITE)
	@test "$$(shasum -a 256 $(RAYLIB_INCLUDE)/raylib.h | cut -d' ' -f1)" = \
	  047e7255f93f8c34039cab906ad76136706b5c7b4c5b5b065d84141963ee9b6b
	@test "$$(shasum -a 256 $(RAYLIB_INCLUDE)/raymath.h | cut -d' ' -f1)" = \
	  2b8b88f5b3f748e3cf8bdbfb8b7da23a76c755dc40f9c6e455bfc09b3669d028

# live-chart keeps the larger shared chart for the explicit windowed demo.
CHART := examples/chart.x
PACKAGE_X_FLAGS += --x-include-dir examples

builds/climate-trends: examples/climate-trends.x examples/fonts/Lato-Regular.ttf \
  $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/climate-trends-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/texture-sheet: examples/texture-sheet.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/texture-sheet-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

prepare-desktop:
	$(DEPS_TOOL) prepare $(DESKTOP_MANIFEST)

# Rebuilt in place against the desktop prefix, so the archive left behind is
# the windowed one; `make build` puts the gated profile back.
run-interactive: prepare-desktop
	$(MAKE) clean-builds
	$(MAKE) builds/live-chart \
	  RAYLIB_PREFIX=$(DESKTOP_PREFIX) \
	  PACKAGE_LINK="$(DESKTOP_PREFIX)/lib/libraylib.a $(DESKTOP_FRAMEWORKS)"
	./builds/live-chart

clean-builds:
	rm -rf builds

builds/live-chart: examples/live-chart.x $(CHART) $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/live-chart-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $< $(CHART)
