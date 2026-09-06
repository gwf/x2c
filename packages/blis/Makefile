PACKAGE := blis
DEPENDENCY_PREFIX_VAR := BLIS_PREFIX
BLIS_PROFILE := PROFILE.json
BLIS_SHARED := libblis.dylib
NM_SYMBOL := substr($$1, 2)
ifeq ($(shell uname -s),Linux)
DEPENDENCY_MANIFEST := dependency-linux.json
BLIS_PROFILE := PROFILE-linux.json
BLIS_SHARED := libblis.so
NM_SYMBOL := $$1
endif
include ../package.mk

BLIS_INCLUDE := $(BLIS_PREFIX)/include
BLIS_STATIC := $(BLIS_PREFIX)/lib/libblis.a

PACKAGE_C_FLAGS := --c-include-dir src --c-system-dir $(BLIS_INCLUDE)
PACKAGE_LINK := $(BLIS_STATIC)

.PHONY: example short-example run check-profile verify-profile \
	verify-provenance verify-linkage

# Everything here is only as trustworthy as the prefix it was built against,
# so build and run check the profile first. test depends on build.
build: verify-profile

example: builds/risk-report

short-example: builds/page-rank

run: verify-profile builds/page-rank builds/risk-report verify-linkage
	./builds/page-rank
	./builds/risk-report

check-profile:
	@test -n "$(BLIS_PREFIX)" || \
	  { echo "set BLIS_PREFIX to the admitted BLIS 2.1 prefix" >&2; \
	    exit 1; }
	@test -f "$(BLIS_STATIC)" || \
	  { echo "missing static archive: $(BLIS_STATIC)" >&2; exit 1; }
	@test ! -e "$(BLIS_PREFIX)/lib/$(BLIS_SHARED)" || \
	  { echo "BLIS_PREFIX must contain only the admitted static build" >&2; \
	    exit 1; }

verify-profile: verify-dependency check-profile
	@test "$$(shasum -a 256 $(BLIS_INCLUDE)/blis/blis.h | \
	  cut -d' ' -f1)" = \
	  "$$(jq -r '.header_sha256' $(BLIS_PROFILE))"
	@test "$$(shasum -a 256 LICENSES/BLIS-2.1-BSD-3-Clause.txt | \
	  cut -d' ' -f1)" = \
	  6b54dbb27c2aeba07c72084ea948d3d7ec206758b119eef37a1cc4f958ac694c
	@test "$$(shasum -a 256 LICENSES/BLIS-2.1-additional-notices.txt | \
	  cut -d' ' -f1)" = \
	  05f25bac1e33ea02071a5b8d0c6b311438e61c92e652250c949757704517333a
	@test "$$(shasum -a 256 LICENSES/BLIS-2.1-armv8a-BSD-3-Clause.txt | \
	  cut -d' ' -f1)" = \
	  b59895ecabd0b1935e509829344e0c30490b4e8eae6e4bbc176f7bf5b4e17edc
	@test "$$(shasum -a 256 LICENSES/LAPACK-3.2-BSD-3-Clause.txt | \
	  cut -d' ' -f1)" = \
	  fd725c12cb2d3bbedf0c7bb55fd42ce6ffbc3f82a696051618077808b6b7f3d4
	@test "$$(ar -t $(BLIS_STATIC) | wc -l | tr -d ' ')" = \
	  "$$(jq -r '.archive.members' $(BLIS_PROFILE))"
# The symbol comparison sorts both sides under LC_ALL=C. Without it the
# collation follows the caller's locale: en_US.UTF-8 ignores the leading
# underscores, so _DefaultRuneLocale moves and the diff fails on a machine
# whose LC_COLLATE is not C.
	@profile_tmp=$$(mktemp -d /tmp/x2c-blis-profile.XXXXXX); \
	  trap 'rm -rf "$$profile_tmp"' EXIT; \
	  export LC_ALL=C; \
	  nm -g --format=posix $(BLIS_STATIC) | \
	    awk '$$2 == "U" {print $(NM_SYMBOL)}' | sort -u > \
	    "$$profile_tmp/undefined"; \
	  nm -g --format=posix $(BLIS_STATIC) | \
	    awk '$$2 != "U" && NF >= 2 {print $(NM_SYMBOL)}' | sort -u > \
	    "$$profile_tmp/defined"; \
	  comm -23 "$$profile_tmp/undefined" "$$profile_tmp/defined" > \
	    "$$profile_tmp/external"; \
	  jq -r '.archive.external_undefined_symbols[]' $(BLIS_PROFILE) | \
	    sort -u > "$$profile_tmp/expected"; \
	  diff -u "$$profile_tmp/expected" "$$profile_tmp/external"

verify-provenance: verify-profile

verify-linkage: builds/page-rank builds/risk-report $(PACKAGE_TEST_PROGRAMS)
	python3 ../tools/check-linkage.py --package blis $^

builds/page-rank: examples/page-rank.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/page-rank-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/risk-report: examples/risk-report.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/example \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
