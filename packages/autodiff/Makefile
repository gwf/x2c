PACKAGE := autodiff
include ../package.mk

PACKAGE_C_FLAGS := --c-include-dir src
PACKAGE_LINK :=

EXAMPLES := autodiff autodiff-fit
EXAMPLE_PROGRAMS := $(addprefix builds/example-,$(EXAMPLES))

.PHONY: check fixtures fixtures-update run benchmark

# The package's own gate: the runtime and macro tests, the translation
# fixtures, and the examples against their expected output.
check: test fixtures run

# The fixtures use the shared runner with this package's fixture directory.
FIXTURES := FIXTURE_DIR=$(CURDIR)/fixtures \
  FIXTURE_BUILD=$(CURDIR)/builds/fixtures X2C=$(abspath $(X2C)) \
  $(ROOT)/unittest/compiler-fixtures/run.sh

fixtures:
	$(FIXTURES) check

fixtures-update:
	$(FIXTURES) update

run: $(EXAMPLE_PROGRAMS)
	@for name in $(EXAMPLES); do \
	  ./builds/example-$$name >builds/$$name.stdout && \
	  diff -u examples/expected/$$name.stdout builds/$$name.stdout || exit 1; \
	done

# The test build owns builds/autodiff, so examples build beside it.
builds/example-%: examples/%.x | builds
	"$(X2C)" build --output $@ --build-dir builds/$*-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

# This example includes the macro module directly and needs no package archive.
builds/example-autodiff: examples/autodiff.x src/autodiff-macros.x | builds
	"$(X2C)" build --plain --output $@ --build-dir builds/autodiff-build \
	  --x-include-dir src $(PACKAGE_C_FLAGS) $< src/autodiff-macros.x

benchmark: builds/autodiff-checkpoint

builds/autodiff-checkpoint: benchmarks/autodiff-checkpoint.x | builds
	"$(X2C)" build --output $@ --build-dir builds/benchmark-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
