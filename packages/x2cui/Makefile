PACKAGE := x2cui
DEPENDENCY_PREFIX_VAR := CUI_PREFIX
include ../package.mk

CUI_INCLUDE := $(CUI_PREFIX)/include

# --c-include-dir is a C-compiler flag. x2c's own collection needs -I to read
# CUI's headers, which declare every type the package's methods take.
PACKAGE_X_FLAGS += -I $(CUI_INCLUDE)
PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(CUI_INCLUDE) \
	-I $(CUI_INCLUDE)
# CUI's window layer on macOS is Cocoa over OpenGL.
PACKAGE_LINK := $(CUI_PREFIX)/lib/libcui.a -Wl,-framework,Cocoa \
	-Wl,-framework,QuartzCore -Wl,-framework,OpenGL

# Each example with files of its own keeps them in a directory beside it.
PACKAGE_X_FLAGS += --x-include-dir examples

.PHONY: run run-interactive run-gallery

check: test run

short-example: builds/todo

example: builds/gallery

# The gated runs draw off screen and write PNGs. A window needs a
# WindowServer connection, which no gate has.
run: builds/todo builds/scenes
	./builds/todo --shot builds/todo.png
	./builds/scenes --shots builds/shots

run-interactive: builds/todo
	./builds/todo

run-gallery: builds/gallery
	./builds/gallery

# Each file under examples/scenes is a unit of its own beside the entry.
SCENE_UNITS := $(wildcard examples/scenes/*.x)

builds/scenes: examples/scenes.x $(SCENE_UNITS) \
		$(PACKAGE_CONSUMER_DEPS) | builds
	$(X2C) build --output $@ --build-dir builds/scenes-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $< $(SCENE_UNITS)

# The gallery's pages are units under examples/gallery.
GALLERY_UNITS := $(wildcard examples/gallery/*.x)

builds/gallery: examples/gallery.x $(GALLERY_UNITS) \
		$(PACKAGE_CONSUMER_DEPS) | builds
	$(X2C) build --output $@ --build-dir builds/gallery-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $< $(GALLERY_UNITS)
