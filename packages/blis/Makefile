PACKAGE := blis
DEPENDENCY_PREFIX_VAR := BLIS_PREFIX
BLIS_PLATFORM := $(shell uname -s | tr A-Z a-z)-$(shell uname -m)
# Apple Silicon builds BLIS's firestorm kernels; every other platform builds
# the generic configuration. Archive members and the symbols the archive
# leaves undefined follow the kernel set, so each platform has its own
# recorded profile. tools/record-blis-profile.sh writes one.
DEPENDENCY_MANIFEST := dependency-generic.json
ifeq ($(BLIS_PLATFORM),darwin-arm64)
DEPENDENCY_MANIFEST := dependency.json
endif
BLIS_PROFILE := PROFILE-$(BLIS_PLATFORM).json
BLIS_SHARED := libblis.dylib
NM_SYMBOL := substr($$1, 2)
ifeq ($(shell uname -s),Linux)
BLIS_SHARED := libblis.so
NM_SYMBOL := $$1
endif
include ../package.mk

BLIS_INCLUDE := $(BLIS_PREFIX)/include
BLIS_STATIC := $(BLIS_PREFIX)/lib/libblis.a

PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(BLIS_INCLUDE)
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
	@$(CHECK_SHA256) licenses.sha256
	@./verify-archive.sh $(BLIS_PROFILE) "$(BLIS_PREFIX)"

verify-provenance: verify-profile

verify-linkage: builds/page-rank builds/risk-report $(PACKAGE_TEST_PROGRAMS)
	python3 ../tools/check-linkage.py --package blis $^

builds/page-rank: examples/page-rank.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/page-rank-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/risk-report: examples/risk-report.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/example \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
