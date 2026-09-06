PACKAGE := libuv
DEPENDENCY_PREFIX_VAR := LIBUV_PREFIX
include ../package.mk

LIBUV_INCLUDE := $(LIBUV_PREFIX)/include
LIBUV_STATIC := $(LIBUV_PREFIX)/lib/libuv.a

PACKAGE_C_FLAGS := --c-include-dir src --c-system-dir $(LIBUV_INCLUDE)
PACKAGE_LINK := $(LIBUV_STATIC)

.PHONY: example short-example run check-profile verify-profile \
	verify-headers verify-licenses verify-linkage

example: builds/thread-notify builds/network-report builds/ipc-report \
	builds/datagram-report builds/release-checks

short-example: builds/process-report

run: builds/process-report builds/thread-notify builds/network-report \
	builds/ipc-report builds/datagram-report \
	builds/release-checks \
	verify-linkage
	./builds/process-report
	./builds/thread-notify
	./builds/network-report
	./builds/ipc-report
	./builds/datagram-report
	./builds/release-checks

check-profile:
	@test -n "$(LIBUV_PREFIX)" || \
	  { echo "set LIBUV_PREFIX to the static libuv prefix" >&2; exit 1; }
	@test -f "$(LIBUV_STATIC)" || \
	  { echo "missing static archive: $(LIBUV_STATIC)" >&2; exit 1; }

# Nothing links against libuv until its pinned prefix, headers, and licenses
# have been verified.
$(PACKAGE_ARCHIVE): | verify-profile

verify-profile: verify-dependency check-profile verify-headers verify-licenses

verify-headers: $(DEPENDENCY_PREREQUISITE)
	@test "$$(shasum -a 256 "$(LIBUV_INCLUDE)/uv.h" | cut -d' ' -f1)" = \
	  bb9ed99b80cd22c58361bffdfbb2aa7029ce0391cde616745c0072a6f3c03219
	@test "$$(shasum -a 256 "$(LIBUV_INCLUDE)/uv/errno.h" | cut -d' ' -f1)" = \
	  4242edf790e4569ef349026ab4c6e31093334ee5fc02b16ed7a0d9fbacdffd16
	@test "$$(shasum -a 256 "$(LIBUV_INCLUDE)/uv/version.h" | cut -d' ' -f1)" = \
	  a859f2c21f7887d45b0372109ebc91759a6f8c408c7cbf2a12f9bbe579be403b
	@test "$$(shasum -a 256 "$(LIBUV_INCLUDE)/uv/threadpool.h" | cut -d' ' -f1)" = \
	  09ae41099af710289155be012df45c2fce04da6a02e813278b4558935e645938
	@test "$$(shasum -a 256 "$(LIBUV_INCLUDE)/uv/unix.h" | cut -d' ' -f1)" = \
	  06ccd9e0f3f312b610a7e7a8ff16596988e02796e7a0c81a62e29d5f6abe4613
	@test "$$(shasum -a 256 "$(LIBUV_INCLUDE)/uv/darwin.h" | cut -d' ' -f1)" = \
	  222b6dd3ce67cfbb735b14b1662f065fc23570d6969acf463b39d946b7590d8c

verify-licenses:
	@test "$$(shasum -a 256 LICENSES/libuv-1.52.1-MIT.txt | \
	  cut -d' ' -f1)" = \
	  16de0c32b265cb7d46a6d3bd614f259dd4d693a5e26b3407b04aae8d73041f0c
	@test "$$(shasum -a 256 LICENSES/libuv-1.52.1-extra.txt | \
	  cut -d' ' -f1)" = \
	  262c44bd2cdba037e6d2a82fba15f5800d292bc993a6f5d6b6ea487744d02836
	@test "$$(shasum -a 256 LICENSES/libuv-1.52.1-BSD-2-Clause.txt | \
	  cut -d' ' -f1)" = \
	  ba661d1dfdbcb6f30d5f7c583e219f595cd8ae4fefd9f8a45ac5526a1b8e6b75
	@test "$$(shasum -a 256 LICENSES/libuv-1.52.1-ISC-notices.txt | \
	  cut -d' ' -f1)" = \
	  9c3e698639860bd6c45ff70ed43c0c1bba45f3503e5bf527f67d376e9f3175d5

verify-linkage: builds/process-report
	@unexpected="$$(otool -L builds/process-report | tail -n +2 | \
	  awk '{print $$1}' | \
	  grep -Ev '^/usr/lib/libSystem\.B\.dylib$$' || true)"; \
	  test -z "$$unexpected" || \
	  { echo "unexpected dynamic dependency: $$unexpected" >&2; exit 1; }

builds/process-report: examples/process-report.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/process-report-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/thread-notify: examples/thread-notify.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/thread-notify-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/network-report: examples/network-report.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/network-report-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/ipc-report: examples/ipc-report.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/ipc-report-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/datagram-report: examples/datagram-report.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/datagram-report-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/release-checks: examples/release-checks.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/release-checks-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
