###############################################################################
# Makefile for the X2C compiler
###############################################################################
include etc/make-command.mk
include etc/help.mk
include etc/branch.mk
include etc/build-config.mk
###############################################################################
.DEFAULT_GOAL := build
.SUFFIXES:
.DELETE_ON_ERROR:

CORE_TARGETS = build build-safe verify examples check precommit \
	agent-pr-check sanity-check clean help stats
BUILD_TARGETS = build-install bootstrap-build bootstrap-refresh \
	stage-1 stage-2 stage-3 packages
VERIFY_TARGETS = verify-sanitize verify-fixtures verify-fixtures-update \
	proof-artifact-atomicity proof-raw-symbols proof-conformance \
	build-recovery packages-check
SYMBOL_TARGETS = sym-ensure sym-check sym-update sym-refresh \
	sym-live-build hdr-check hdr-sync artifact-refresh
DIFF_TARGETS = stage-diff-0 stage-diff-1 stage-diff-2 stage-diff-3 \
	stage-diff-all
DOC_TARGETS = doc-generate doc-check doc-examples doc-build doc-serve \
	examples-update
SITE_TARGETS = site site-build site-check site-serve
BENCHMARK_TARGETS = bm-all bm-scan bm-string bm-list bm-block-buffer \
	bm-scope bm-file bm-logger bm-iter bm-exception bm-var bm-varops \
	bm-map bm-map-standard-smoke bm-map-standard-campaign \
	bm-map-u32-smoke bm-map-u32-campaign bm-compiler \
	bm-match-cache bm-lisp-auto
SHOOTOUT_TARGETS = shoot-run shoot-update shoot-calibrate
APE_TARGETS = ape-toolchain ape-build ape-verify
CONFIG_TARGETS = configure configure-packages config-debug config-optimize \
	config-show clean-all
COMPAT_TARGETS = default x2c safely install bootstrap rebootstrap \
	cosmopolitan-toolchain cosmopolitan-ape cosmopolitan-verify \
	test selftest stresstest unittest sanitizer-unittest \
	compiler-fixtures update-compiler-fixtures \
	shootout update-shootout calibrate-shootout \
	symbol-table check-symbol-snapshot update-symbol-snapshot \
	update-header-symbols check-header-symbols \
	artifact-atomicity live-symbol-x2c check-raw-symbols \
	refresh-artifacts update-examples \
	docs check-docs check-doc-examples book book-serve \
	benchmarks scan-benchmark string-benchmark list-benchmark \
	block-buffer-benchmark scope-benchmark file-benchmark logger-benchmark \
	iter-benchmark exception-benchmark var-benchmark varops-benchmark \
	map-benchmark map-standard-benchmark-smoke \
	map-standard-benchmark-campaign map-u32-benchmark-smoke \
	map-u32-benchmark-campaign \
	compiler-translation-benchmark match-cache-benchmark \
	lisp-auto-benchmark diff0 diff1 diff2 diff3 diffs \
	debug optimize show-config

.PHONY: $(CORE_TARGETS) $(BUILD_TARGETS) $(VERIFY_TARGETS) \
	$(SYMBOL_TARGETS) $(DIFF_TARGETS) $(DOC_TARGETS) \
	$(SITE_TARGETS) \
	$(BENCHMARK_TARGETS) $(SHOOTOUT_TARGETS) $(APE_TARGETS) \
	$(CONFIG_TARGETS) $(COMPAT_TARGETS) bootstrap-ready stage0-settle \
	check-after-precommit
# Stage-0 bootstrap artifacts we expect before incremental builds/tests.
BOOTSTRAP_SENTINEL = bin/x2c-bootstrap
STAGE0_X2C ?= ./builds/0/x2c
SYMBOL_CHANGE_MARKER = builds/.symbol-snapshot-changed
STATS_COLOR ?= auto

bootstrap-ready: configure
	@if [ ! -f $(BOOTSTRAP_SENTINEL) ]; then \
		echo "[bootstrap] Missing $(BOOTSTRAP_SENTINEL); running " \
			"'make build-safe' first..."; \
		$(MAKE) build-safe; \
	fi

##@ Getting started
configure:						## Report core build prerequisites
	@./configure

configure-packages:					## Report package build prerequisites
	@./configure --packages

build: bootstrap-ready					## Build the runtime and compiler
	$(MAKE) -C include all
	$(MAKE) -C lib x2c.x
	$(MAKE) stage0-settle

build-safe: configure					## Conservatively rebuild the compiler
	$(MAKE) -C bootstrap clean
	$(MAKE) bootstrap-build
	$(MAKE) -C builds clean
	$(MAKE) -C include all
	$(MAKE) -C lib x2c.x
	$(MAKE) stage0-settle

# Build stage 0 against a current snapshot, then ask the resulting compiler
# for the same snapshot. The second build is normally a no-op; it runs only
# when the new compiler changed the snapshot that produced it.
stage0-settle:
	$(MAKE) sym-ensure
	$(PARALLEL_MAKE) -C builds x2c
	$(MAKE) sym-ensure
	$(PARALLEL_MAKE) -C builds x2c
	$(MAKE) sym-ensure
	@if [ -f $(SYMBOL_CHANGE_MARKER) ]; then \
		echo "symbol snapshot did not settle after rebuilding stage 0" >&2; \
		echo "use the explicit bootstrap transition for this change" >&2; \
		exit 1; \
	fi

verify: build						## Build and run unit test suites
	./unittest/probes/run-suite-coverage.sh
	$(MAKE) -C unittest clean
	$(PARALLEL_MAKE) -C unittest test-all
	$(PARALLEL_MAKE) -C unittest compiler-fixtures scope-probes \
		error-probes varops-probes
	(cd ./unittest && ./test-all)

examples: build						## Check curated examples
	$(MAKE) -C examples check

packages: configure-packages				## Build packages and examples
	$(MAKE) build
	$(MAKE) -C packages/pcre2 build short-example example lisp-example
	$(MAKE) -C packages/yyjson build short-example example lisp-example
	$(MAKE) -C packages/libcurl build short-example example lisp-example
	$(MAKE) -C examples/packages/http-json-releases build
	$(MAKE) -C packages/termbox2 build short-example example
	$(MAKE) -C packages/blis build short-example example
	$(MAKE) -C packages/libuv build short-example example
	$(MAKE) -C packages/raylib build short-example example builds/live-chart

# Optional: the completed packages need a prepared dependency cache, so this
# stays out of check and precommit. Run it after a compiler or runtime change
# that could reach a package client. `test` builds only tests/, so the example
# programs are named too; they are what a reader of the package actually sees.
packages-check: build					## Test the completed packages
	$(MAKE) -C packages/pcre2 test run run-lisp
	$(MAKE) -C packages/yyjson test run run-lisp
	$(MAKE) -C packages/libcurl test run run-lisp
	$(MAKE) -C examples/packages/http-json-releases test
	$(MAKE) -C packages/termbox2 test run
	$(MAKE) -C packages/blis test run
	$(MAKE) -C packages/libuv test run
	$(MAKE) -C packages/raylib verify

check: build						## Run extended non-mutating checks
	$(MAKE) sym-check
	$(MAKE) check-after-precommit
	$(MAKE) stage-diff-all

check-after-precommit:
	$(MAKE) hdr-check
	$(MAKE) proof-artifact-atomicity
	$(MAKE) verify
# Example checks are optional (Gary, 2026-09-01).
# Run `make examples doc-examples` manually.
#	$(MAKE) examples
	$(MAKE) proof-raw-symbols
	$(MAKE) doc-check
#	$(MAKE) doc-examples

# Stage 2 is where the compiler has reached its fixed point: stage 1 is built
# by the refreshed bootstrap and stage 2 by stage 1, so `stage-diff-2` proves
# the compiler reproduces its own output. `make stage-3` and `stage-diff-all`
# still run the fourth round on demand.
precommit: build					## Prepare the final tree for commit
	$(MAKE) sym-check
	$(MAKE) hdr-sync
	$(MAKE) bootstrap-refresh
	$(MAKE) build-safe
	$(MAKE) stage-2
	$(MAKE) stage-diff-0
	$(MAKE) stage-diff-1
	$(MAKE) stage-diff-2

agent-pr-check:					## Run complete agent PR proof once
	$(MAKE) precommit
	$(MAKE) check-after-precommit

sanity-check: bootstrap-refresh			## Prove bootstrap recovery and self-hosting
	$(MAKE) build-safe
	$(MAKE) stage-3

clean:							## Remove ordinary generated output
	$(MAKE) -C builds clean
	$(MAKE) -C include clean
	$(MAKE) -C examples clean
	$(MAKE) -C unittest clean

help:							## Show grouped Make targets
	@python3 -c "$$PRINT_HELP_PYSCRIPT" < $(firstword $(MAKEFILE_LIST))

stats:							## Show repository statistics
	@python3 tools/repo-metrics.py --summary --color="$(STATS_COLOR)"

##@ Build and stages
build-install: build					## Install this compiler in bin
	rm -f ./bin/x2c-$(BRANCH)
	cp builds/0/x2c ./bin/x2c-$(BRANCH)
	rm -f ./bin/x2c
	ln -s x2c-$(BRANCH) ./bin/x2c

bootstrap-build:					## Build the bootstrap compiler
	$(PARALLEL_MAKE) -C bootstrap

bootstrap-refresh: build				## Refresh the portable bootstrap
	$(MAKE) -C bootstrap realclean
	cp builds/0/lib/*.[ch] bootstrap/lib/
	cp builds/0/src/*.[ch] bootstrap/src/
	$(MAKE) bootstrap-build

stage-1: build						## Build through compiler stage 1
	$(PARALLEL_MAKE) -C builds test

stage-2: build						## Build through compiler stage 2
	$(PARALLEL_MAKE) -C builds selftest

stage-3: bootstrap-ready				## Build through compiler stage 3
	time $(PARALLEL_MAKE) -C builds stresstest

##@ Verification and proofs
verify-sanitize: build					## Run tests under ASan and UBSan
	$(PARALLEL_MAKE) -C unittest sanitizer

verify-fixtures: build					## Check compiler phase fixtures
	$(MAKE) -C unittest compiler-fixtures

verify-fixtures-update: build				## Rewrite compiler fixture output
	$(MAKE) -C unittest update-compiler-fixtures

proof-artifact-atomicity:				## Prove artifact updates are atomic
	./unittest/probes/run-artifact-atomicity.sh

build-recovery: build					## Check incremental build recovery
	./unittest/probes/run-build-recovery.sh

proof-raw-symbols: build				## Check raw symbol collection parity
	./unittest/probes/run-raw-symbol-sweep.sh

proof-conformance: build ## Compare owned conformance rows between snapshot and live symbol modes
	./tools/check-conformance-coherence.sh

##@ Symbols and artifacts
sym-ensure:						## Refresh stale symbols only when inputs changed
	@python3 tools/sync-symbol-snapshot.py \
		--compiler "$(STAGE0_X2C)" --fallback ./bin/x2c \
		--changed "$(SYMBOL_CHANGE_MARKER)"

sym-check: build					## Check the compiler symbol snapshot
	@tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT; \
		$(STAGE0_X2C) translate --live-symbols --dump-symbol-snapshot \
		etc/symbol-source.x >"$$tmp" && \
		diff -u etc/symbols.xlisp "$$tmp"

sym-update: build					## Rewrite the compiler symbol snapshot
	$(MAKE) hdr-sync

sym-refresh: sym-update					## Refresh and verify symbol artifacts
	$(MAKE) sym-check

sym-live-build: bootstrap-ready				## Build stage 0 from live symbols
	$(MAKE) -C builds clean
	$(MAKE) -C include all
	$(MAKE) -C lib x2c.x
	$(PARALLEL_MAKE) -C builds x2c X2C_FLAGS=--live-symbols

HEADER_SYMBOL_SOURCES = $(filter-out lib/x2c.x,$(wildcard lib/*.x)) \
	$(wildcard src/*.x)

hdr-check: build					## Check the header symbol artifact
	@tmp=$$(mktemp); trap 'rm -f "$$tmp"' EXIT; \
		$(STAGE0_X2C) translate --dump-header-symbols \
		$(HEADER_SYMBOL_SOURCES) >"$$tmp" && \
		diff -u etc/header-symbols.xlisp "$$tmp"

hdr-sync: build						## Refresh stale header symbols
	@tmp=$$(mktemp etc/.header-symbols.xlisp.XXXXXX); \
		trap 'rm -f "$$tmp"' EXIT; \
		$(STAGE0_X2C) translate --dump-header-symbols \
			$(HEADER_SYMBOL_SOURCES) >"$$tmp" || exit $$?; \
		if cmp -s etc/header-symbols.xlisp "$$tmp"; then \
			exit 0; \
		fi; \
		echo "Refreshing etc/header-symbols.xlisp"; \
		diff -u etc/header-symbols.xlisp "$$tmp" || true; \
		mv "$$tmp" etc/header-symbols.xlisp

artifact-refresh:					## Refresh tracked source artifacts
	$(MAKE) sym-update
	$(MAKE) bootstrap-refresh

##@ Stage comparison
stage-diff-0:						## Compare bootstrap and stage 0
	./tools/check-generated-stages.sh bootstrap builds/0

stage-diff-1:						## Compare stages 0 and 1
	./tools/check-generated-stages.sh builds/0 builds/1

stage-diff-2:						## Compare stages 1 and 2
	./tools/check-generated-stages.sh builds/1 builds/2

stage-diff-3:						## Compare stages 2 and 3
	./tools/check-generated-stages.sh builds/2 builds/3

stage-diff-all: stage-3				## Compare every generated stage
	$(MAKE) stage-diff-0
	$(MAKE) stage-diff-1
	$(MAKE) stage-diff-2
	$(MAKE) stage-diff-3

##@ Documentation and examples
doc-generate:						## Regenerate derived documentation
	python3 tools/gen-module-catalog.py --write
	python3 tools/gen-api-reference.py --write

doc-check:						## Check documentation for drift
	python3 tools/check-docs.py

doc-examples: build					## Compile every example in the book
	python3 tools/check-doc-examples.py

doc-build: site/node_modules/.package-lock.json		## Render the documentation book
	@command -v mdbook >/dev/null 2>&1 || { \
		echo "mdbook not installed; run: cargo install mdbook --locked" >&2; \
		exit 1; \
	}
	mdbook build docs

doc-serve: site/node_modules/.package-lock.json		## Serve the book with live reload
	@command -v mdbook >/dev/null 2>&1 || { \
		echo "mdbook not installed; run: cargo install mdbook --locked" >&2; \
		exit 1; \
	}
	mdbook serve docs --open

site/node_modules/.package-lock.json: site/package.json site/package-lock.json
	npm ci --prefix site

site: site/node_modules/.package-lock.json		## Serve the complete site with live reload
	@command -v mdbook >/dev/null 2>&1 || { \
		echo "mdbook not installed; run: cargo install mdbook --locked" >&2; \
		exit 1; \
	}
	npm --prefix site run dev -- --host 127.0.0.1 --force

site-build: site/node_modules/.package-lock.json		## Render the public site and book
	@command -v mdbook >/dev/null 2>&1 || { \
		echo "mdbook not installed; run: cargo install mdbook --locked" >&2; \
		exit 1; \
	}
	npm --prefix site run build

site-check: site-build					## Check the rendered public site
	node site/scripts/check-built-site.mjs

site-serve: site-build					## Serve the complete public site
	npm --prefix site run preview -- --host 127.0.0.1

examples-update: build					## Rewrite expected example output
	$(MAKE) -C examples update

##@ Benchmarks
RUNTIME_BENCHMARKS = bm-scan bm-string bm-list bm-block-buffer bm-scope \
	bm-file bm-logger bm-iter bm-exception bm-var bm-varops

bm-all: $(RUNTIME_BENCHMARKS)				## Run the current runtime timings

# Shared benchmark steps: translate + compile one focused benchmark
# ($(1) = source stem, $(2) = target-specific compile flags), and the
# 5-sample run loop shared by the timing targets.
define RUN_X2C_BENCHMARK
	mkdir -p unittest/build/benchmarks
	./builds/0/x2c translate --out-dir unittest/build/benchmarks \
		unittest/benchmarks/$(1).x
	$(CC) $(2) -iquote include \
		unittest/build/benchmarks/$(1).c \
		-L builds/0 -lx2c -lm -o unittest/build/benchmarks/$(1)
endef

define RUN_BENCHMARK_SAMPLES
	@for sample in 1 2 3 4 5; do \
		echo "sample,$$sample"; \
		./unittest/build/benchmarks/$(1); \
	done
endef

bm-scan: build						## Run focused scanner timings
	$(call RUN_X2C_BENCHMARK,scan-hot-paths,-O2)
	./unittest/build/benchmarks/scan-hot-paths

bm-string: build					## Run focused String timings
	$(call RUN_X2C_BENCHMARK,string-hot-paths,$(BUILD_CFLAGS))
	$(call RUN_BENCHMARK_SAMPLES,string-hot-paths)

bm-list: build						## Run focused List timings
	$(MAKE) -C unittest benchmark-list

bm-block-buffer: build					## Run Block and Buffer timings
	$(call RUN_X2C_BENCHMARK,block-buffer-hot-paths,$(BUILD_CFLAGS))
	$(call RUN_BENCHMARK_SAMPLES,block-buffer-hot-paths)

bm-scope: build						## Run focused Scope timings
	$(MAKE) -C unittest scope-benchmark

bm-file: build						## Run focused File timings
	$(call RUN_X2C_BENCHMARK,file-hot-paths,-O2)
	./unittest/build/benchmarks/file-hot-paths

bm-logger: build					## Run focused Logger timings
	mkdir -p unittest/build/benchmarks
	./builds/0/x2c translate --out-dir unittest/build/benchmarks \
		unittest/benchmarks/logger-hot-paths.x
	$(CC) -g -iquote include \
		unittest/build/benchmarks/logger-hot-paths.c \
		-L builds/0 -lx2c -lm \
		-o unittest/build/benchmarks/logger-hot-paths-debug
	$(CC) -O2 -iquote include \
		unittest/build/benchmarks/logger-hot-paths.c \
		-L builds/0 -lx2c -lm \
		-o unittest/build/benchmarks/logger-hot-paths-optimized
	@for mode in debug optimized; do \
		for sample in 1 2 3 4 5; do \
			echo "$$mode-sample,$$sample"; \
			./unittest/build/benchmarks/logger-hot-paths-$$mode; \
		done; \
	done

bm-iter: build						## Run focused Iter timings
	$(MAKE) -C unittest iter-benchmark

bm-exception: build					## Run focused exception timings
	$(MAKE) -C unittest exception-benchmark

bm-var: build						## Run existing Var hot paths
	$(call RUN_X2C_BENCHMARK,var-hot-paths,$(BUILD_CFLAGS))
	$(call RUN_BENCHMARK_SAMPLES,var-hot-paths)

bm-varops: build					## Check Var operator fast lanes
	./unittest/benchmarks/run-varops-hot-paths.sh

bm-map: build						## Compare Map with pinned klib khashl
	./unittest/benchmarks/hash-table/direct/run.sh

bm-map-standard-smoke: build			## Smoke-test recognized Map suites
	./unittest/benchmarks/hash-table/run-jackson.sh smoke matched
	./unittest/benchmarks/hash-table/run-jackson.sh smoke fixed-policy
	./unittest/benchmarks/hash-table/run-udb3.sh smoke

bm-map-standard-campaign: build			## Run full external Map campaign
	./unittest/benchmarks/hash-table/run-jackson.sh full matched
	./unittest/benchmarks/hash-table/run-jackson.sh full fixed-policy
	./unittest/benchmarks/hash-table/run-udb3.sh full

bm-map-u32-smoke: build				## Smoke-test runtime-free U32Map
	./unittest/benchmarks/hash-table/run.py smoke

bm-map-u32-campaign: build			## Run full runtime-free U32Map campaign
	./unittest/benchmarks/hash-table/run.py full

bm-compiler: stage-1					## Measure representative translation
	./unittest/benchmarks/run-compiler-translation.sh

bm-match-cache: stage-1					## Run Match cache acceptance gates
	./unittest/benchmarks/run-match-cache-benchmark.sh

bm-lisp-auto: stage-1					## Run Lisp AUTO acceptance gate
	./unittest/benchmarks/run-lisp-auto-benchmark.sh

##@ Shootout and portable builds
shoot-run: build					## Run against pinned shootout references
	python3 examples/shootout/tools/shootout.py run

shoot-update: build					## Refresh the tracked shootout table
	python3 examples/shootout/tools/shootout.py update

shoot-calibrate: build					## Recalibrate all shootout data
	python3 examples/shootout/tools/shootout.py calibrate

ape-toolchain:						## Prepare the pinned APE toolchain
	./etc/cosmopolitan/setup-toolchain.sh

ape-build:						## Build the source-bearing APE
	./etc/cosmopolitan/build.sh

ape-verify:						## Verify the APE-to-native rebuild
	./etc/cosmopolitan/verify-ape.sh

##@ Configuration and maintenance
config-debug:						## Switch to debug build mode
	@echo "Switching to debug build mode..."
	@echo "debug" > $(BUILD_MODE_FILE)
	@echo "Build mode set to: Debug build with symbols and warnings"
	@echo "Run 'make clean' and 'make' to rebuild with debug flags"

config-optimize:					## Switch to optimized build mode
	@echo "Switching to optimized build mode..."
	@echo "optimize" > $(BUILD_MODE_FILE)
	@echo "Build mode set to: Optimized build for performance"
	@echo "Run 'make clean' and 'make' to rebuild with optimization flags"

config-show:						## Show current build configuration
	@echo "Current build mode: $(BUILD_MODE)"
	@echo "Full LTO: $(BUILD_LTO)"
	@echo "Description: $(BUILD_DESCRIPTION)"
	@echo "Compiler flags: $(BUILD_CFLAGS)"
	@echo "Final-link flags: $(BUILD_LDFLAGS)"

clean-all: clean					## Also remove bootstrap objects
	$(MAKE) -C bootstrap clean

###############################################################################
# Additional aliases for build, test, and documentation targets.
default x2c: build
safely: build-safe
ifeq ($(strip $(PREFIX)),)
install: build-install
else
install: build
	python3 etc/x2c-payload.py install --prefix "$(PREFIX)" \
	  --destdir "$(DESTDIR)"
endif
bootstrap: bootstrap-build
rebootstrap: bootstrap-refresh
cosmopolitan-toolchain: ape-toolchain
cosmopolitan-ape: ape-build
cosmopolitan-verify: ape-verify
test: stage-1
selftest: stage-2
stresstest: stage-3
unittest: verify
sanitizer-unittest: verify-sanitize
compiler-fixtures: verify-fixtures
update-compiler-fixtures: verify-fixtures-update
shootout: shoot-run
update-shootout: shoot-update
calibrate-shootout: shoot-calibrate
symbol-table: sym-refresh
check-symbol-snapshot: sym-check
update-symbol-snapshot: sym-update
update-header-symbols: hdr-sync
check-header-symbols: hdr-check
artifact-atomicity: proof-artifact-atomicity
live-symbol-x2c: sym-live-build
check-raw-symbols: proof-raw-symbols
refresh-artifacts: artifact-refresh
update-examples: examples-update
docs: doc-generate
check-docs: doc-check
check-doc-examples: doc-examples
book: doc-build
book-serve: doc-serve
benchmarks: bm-all
scan-benchmark: bm-scan
string-benchmark: bm-string
list-benchmark: bm-list
block-buffer-benchmark: bm-block-buffer
scope-benchmark: bm-scope
file-benchmark: bm-file
logger-benchmark: bm-logger
iter-benchmark: bm-iter
exception-benchmark: bm-exception
var-benchmark: bm-var
varops-benchmark: bm-varops
map-benchmark: bm-map
map-standard-benchmark-smoke: bm-map-standard-smoke
map-standard-benchmark-campaign: bm-map-standard-campaign
map-u32-benchmark-smoke: bm-map-u32-smoke
map-u32-benchmark-campaign: bm-map-u32-campaign
compiler-translation-benchmark: bm-compiler
match-cache-benchmark: bm-match-cache
lisp-auto-benchmark: bm-lisp-auto
diff0: stage-diff-0
diff1: stage-diff-1
diff2: stage-diff-2
diff3: stage-diff-3
diffs: stage-diff-all
debug: config-debug
optimize: config-optimize
show-config: config-show
