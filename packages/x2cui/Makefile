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

.PHONY: run run-interactive

check: test run

short-example: builds/todo

# The gated run draws the application off screen and writes a PNG. A window
# needs a WindowServer connection, which no gate has.
run: builds/todo
	./builds/todo --shot builds/todo.png

run-interactive: builds/todo
	./builds/todo
