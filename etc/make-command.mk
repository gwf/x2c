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
# detected default only at compilation-owning recursive boundaries. MFLAGS
# omits command-line variables, whose values may contain a j. A j counts in
# a word of single-letter flags, not in an option argument such as
# -I/home/jo. Make 3.81 omits -j1 from MFLAGS, so that Make reads -j1 from
# its own command line and passes it on to each recursive Make.
MAKE_ARGUMENT_OPTIONS = -I% -l% -O% -C% -f% -o% -W%
MAKE_HAS_JOBS = $(strip \
	$(filter -j% --jobserver%,$(MFLAGS)) \
	$(findstring j,$(filter-out --% $(MAKE_ARGUMENT_OPTIONS), \
		$(filter -%,$(MFLAGS)))))
MAKE_SERIAL = $(if $(filter 3.%,$(MAKE_VERSION)),$(shell \
	ps -o args= -p $$PPID 2>/dev/null | \
	grep -Eq -- ' (-[a-zA-Z]*j ?1|--jobs[= ]1)( |$$)' && echo -j1))
PARALLEL_MAKE = $(MAKE) \
	$(if $(MAKE_HAS_JOBS),,$(or $(MAKE_SERIAL),-j$(BUILD_JOBS)))
