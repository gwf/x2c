PACKAGE := termbox2
DEPENDENCY_PREFIX_VAR := TERMBOX2_PREFIX
include ../package.mk

TERMBOX2_INCLUDE := $(TERMBOX2_PREFIX)/include
PACKAGE_C_FLAGS := --c-include-dir src --c-system-dir $(TERMBOX2_INCLUDE)
# glibc exposes wcwidth only with an X/Open feature level.
ifeq ($(shell uname -s),Linux)
PACKAGE_C_FLAGS += -D _XOPEN_SOURCE=700
endif
# termbox2 is a single header; src/termbox2.c is already in the archive.
PACKAGE_LINK :=
PACKAGE_TEST_COMMAND := expect tests/run-test.expect

HEADER := $(TERMBOX2_INCLUDE)/termbox2.h
HEADER_SHA256 := \
	ef63b6bd6e3a1c8ad339b7aa0bf52dc21f3e92bd886264ebe588ab86ccd1e5d1
RELEASE_LICENSE_SHA256 := \
	de32c2a6efe313c76fb56692a54a8b544ed31cc9ca04a052e134844740a0bb1e
HEADER_LICENSE_SHA256 := \
	23190431e232877cc40c6d39af50c58719402c4a76404e41b73358a08ef405fa

.PHONY: example short-example run run-interactive run-life-interactive \
	verify-profile

# Nothing links against termbox2 until its pinned header and licenses have
# been verified.
$(PACKAGE_ARCHIVE): | verify-profile

example: builds/incident-filter

short-example: builds/game-of-life

run: builds/game-of-life builds/incident-filter
	@expect tests/run-life.expect
	@expect tests/run-application.expect

run-life-interactive: builds/game-of-life
	./builds/game-of-life

run-interactive: builds/incident-filter
	./builds/incident-filter

verify-profile: $(DEPENDENCY_PREREQUISITE)
	@test -f "$(HEADER)" || { \
	  echo "missing $(HEADER)" >&2; \
	  exit 2; \
	}
	@test "$$(shasum -a 256 "$(HEADER)" | cut -d' ' -f1)" = \
	  "$(HEADER_SHA256)" || { \
	  echo "termbox2.h does not match pinned v2.5.0" >&2; \
	  exit 2; \
	}
	@test "$$(shasum -a 256 \
	  LICENSES/termbox2-release-LICENSE.txt | cut -d' ' -f1)" = \
	  "$(RELEASE_LICENSE_SHA256)"
	@test "$$(shasum -a 256 \
	  LICENSES/termbox2-header-MIT.txt | cut -d' ' -f1)" = \
	  "$(HEADER_LICENSE_SHA256)"

builds/game-of-life: examples/game-of-life.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/life-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/incident-filter: examples/incident-filter.x examples/incidents.log \
		$(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/application-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

# The termbox suite needs the deterministic tty and signal helper, which is
# test-only C and therefore stays out of the package archive.
builds/test-termbox: tests/test-termbox.x tests/terminal-test-helper.c \
		tests/terminal-test-helper.h $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/termbox \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) --c-include-dir tests \
	  --x-include-dir $(ROOT)/unittest \
	  $< tests/terminal-test-helper.c $(ROOT)/unittest/test-support.x
