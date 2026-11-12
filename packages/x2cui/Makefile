PACKAGE := x2cui
DEPENDENCY_PREFIX_VAR := CUI_PREFIX
include ../package.mk

CUI_INCLUDE := $(CUI_PREFIX)/include

# --c-include-dir is a C-compiler flag. x2c's own collection needs -I to read
# CUI's headers, which declare every type the package's methods take.
PACKAGE_X_FLAGS += -I $(CUI_INCLUDE)
PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(CUI_INCLUDE) \
	-I $(CUI_INCLUDE)
# An Array literal outside a form compiles as a run-time Array; where a C
# pointer is expected, cc only warns, so the warning is an error here.
PACKAGE_C_FLAGS += -Xcc -Werror=incompatible-pointer-types
# CUI's window layer is X11 on Linux, as dependency.json builds it, and
# Cocoa over OpenGL on macOS.
PACKAGE_LINK := $(CUI_PREFIX)/lib/libcui.a
ifeq ($(shell uname -s),Linux)
PACKAGE_LINK += -lX11 -ldl -lm -lpthread
else
PACKAGE_LINK += -Wl,-framework,Cocoa -Wl,-framework,QuartzCore \
	-Wl,-framework,OpenGL
endif

# Each example with files of its own keeps them in a directory beside it.
PACKAGE_X_FLAGS += --x-include-dir examples

.PHONY: run run-interactive run-gallery run-stress web web-check web-serve \
	refused-literal

check: test run refused-literal

# The form refuses an Array literal where CUI writes through the array,
# one with a variable in an element, and a C array of CUI's records.
refused-literal: build | builds
	! $(X2C) translate --out-dir builds/refused $(PACKAGE_X_FLAGS) \
	  tests/refused-literal.x >builds/refused.log 2>&1
	grep -q "CUI writes through this array" builds/refused.log
	grep -q "an element is not a constant" builds/refused.log
	grep -q "records in a collection" builds/refused.log

short-example: builds/todo

example: builds/gallery builds/mail builds/orders

# The gated runs draw off screen and write PNGs. A window needs a
# WindowServer connection, which no gate has.
run: builds/todo builds/mail builds/orders builds/scenes builds/stress
	./builds/todo --shot builds/todo.png
	./builds/mail --shot builds/mail.png
	./builds/orders --shot builds/orders.png
	./builds/stress --frames 30
	./builds/scenes --shots builds/shots
	./builds/scenes --check $(CUI_INCLUDE)/cui/cui.h

run-interactive: builds/todo
	./builds/todo builds/todo.txt

run-gallery: builds/gallery
	./builds/gallery

# The frame rate stops at the display's rate; `stress --no-vsync` lifts it.
run-stress: builds/stress
	./builds/stress

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

# The browser build. Emscripten compiles CUI with its SDL2 window layer,
# the package, and the gallery to 64-bit WebAssembly, and links them with
# x2c's browser runtime (`make wasm-runtime` at the repository root).
WASM_RUNTIME := $(ROOT)/builds/wasm/libx2c.a
WASM_MANIFEST := dependency-wasm.json
WASM_DEPS := CC=emcc AR=emar $(DEPS_TOOL)
WASM_CC := $(CURDIR)/tools/wasm-cc
WASM_CUI = $(shell $(WASM_DEPS) path $(WASM_MANIFEST) prefix)
WASM_LINK := -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1 \
	-sINITIAL_MEMORY=64MB -sMAXIMUM_MEMORY=1GB -sSTACK_SIZE=8MB

web: builds/web/gallery.js builds/web/stress.js builds/web/index.html

# Draws every page of the gallery off screen under Node.
web-check: builds/web/gallery-node.cjs
	node $< --shots builds/web/pages

web-serve: web
	python3 -m http.server 4399 --bind 127.0.0.1 --directory builds/web

builds/web/index.html: web/index.html | builds/web
	cp $< $@

builds/web:
	mkdir -p $@

$(WASM_RUNTIME):
	@echo "missing $@: run 'make wasm-runtime' at the repository root"
	@exit 1

# The link inputs of a browser program: its objects, the package's
# archive, x2c's browser runtime, and CUI's browser archive. The list keeps
# its time while it names the same inputs and none of them is newer, so
# the link runs only after a change. WEB_UNITS names a program's other
# units.
builds/web/gallery.rsp: WEB_UNITS := $(GALLERY_UNITS)
builds/web/gallery.rsp: $(GALLERY_UNITS)

builds/web/%.rsp: examples/%.x \
		$(PACKAGE_CONSUMER_DEPS) $(WASM_MANIFEST) tools/wasm-cc \
		| builds/web
	$(WASM_DEPS) prepare $(WASM_MANIFEST)
	$(X2C) build --kind static-library --cc $(WASM_CC) --ar emar -Os \
	  --output builds/web/libx2cui.a --build-dir builds/web/package \
	  --c-include-dir src --c-include-dir $(WASM_CUI)/include \
	  $(filter %.c,$(PACKAGE_GENERATED)) $(PACKAGE_NATIVE)
	mkdir -p builds/web/$*/obj
	$(X2C) build -c --cc $(WASM_CC) --meta-cc cc -Os \
	  --build-dir builds/web/$* --x-include-dir src \
	  --package-dir .. -I $(WASM_CUI)/include --x-include-dir examples \
	  --c-include-dir src --c-include-dir $(WASM_CUI)/include \
	  $(if $(WEB_UNITS),,--output builds/web/$*/obj/$*.o) \
	  $< $(WEB_UNITS)
	{ find builds/web/$*/obj -name '*.o'; \
	  echo builds/web/libx2cui.a; \
	  echo -Wl,--whole-archive; echo $(WASM_RUNTIME); \
	  echo -Wl,--no-whole-archive; \
	  echo $(WASM_CUI)/lib/libcui.a; } > $@.new
	if cmp -s $@.new $@ && \
	    [ -z "$$(find builds/web/$*/obj builds/web/libx2cui.a \
	               -type f -newer $@)" ]; \
	  then rm -f $@.new; else mv $@.new $@; fi

.PRECIOUS: builds/web/%.rsp

builds/web/%.js: builds/web/%.rsp $(WASM_RUNTIME)
	$(WASM_CC) -Os @$< -o $@ $(WASM_LINK) -sMODULARIZE=1 -sEXPORT_ES6=1 \
	  -sENVIRONMENT=web -sJSPI -sMIN_WEBGL_VERSION=2 \
	  -sMAX_WEBGL_VERSION=2 -sGL_ENABLE_GET_PROC_ADDRESS=1

builds/web/%-node.cjs: builds/web/%.rsp $(WASM_RUNTIME)
	$(WASM_CC) -Os @$< -o $@ $(WASM_LINK) -sENVIRONMENT=node \
	  -sNODERAWFS=1
