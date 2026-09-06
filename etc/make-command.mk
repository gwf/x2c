# Preserve the Make selected by PATH. GNU Make 3.81 otherwise canonicalizes
# recursive $(MAKE) invocations to Xcode's bundled binary on macOS.
PATH_MAKE := $(shell command -v make)
MAKE := $(PATH_MAKE)
export MAKE

# Callers may override BUILD_JOBS. Otherwise prefer the portable processor
# query, then the macOS query, and finally a safe serial build.
BUILD_JOBS ?= $(shell \
	jobs=`getconf _NPROCESSORS_ONLN 2>/dev/null || true`; \
	if [ -z "$$jobs" ]; then \
		jobs=`sysctl -n hw.ncpu 2>/dev/null || true`; \
	fi; \
	printf '%s\n' "$$jobs" | \
		awk '/^[1-9][0-9]*$$/ { print; valid = 1 } \
			END { if (!valid) print 1 }')
export BUILD_JOBS

# An inherited jobserver or explicit -j already owns concurrency. Add the
# detected default only at compilation-owning recursive boundaries.
MAKE_HAS_JOBS = $(strip \
	$(findstring --jobserver,$(MAKEFLAGS)) \
	$(filter -j%,$(MAKEFLAGS)) \
	$(findstring j,$(firstword $(MAKEFLAGS))))
PARALLEL_MAKE = $(MAKE) $(if $(MAKE_HAS_JOBS),,-j$(BUILD_JOBS))
