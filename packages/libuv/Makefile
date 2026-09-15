PACKAGE := libuv
DEPENDENCY_PREFIX_VAR := LIBUV_PREFIX
include ../package.mk

LIBUV_INCLUDE := $(LIBUV_PREFIX)/include
LIBUV_STATIC := $(LIBUV_PREFIX)/lib/libuv.a
LIBUV_HEADERS := headers-darwin.sha256
ifeq ($(shell uname -s),Linux)
LIBUV_HEADERS := headers-linux.sha256
endif

PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(LIBUV_INCLUDE)
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
	@cd "$(LIBUV_INCLUDE)" && $(CHECK_SHA256) $(CURDIR)/$(LIBUV_HEADERS)

verify-licenses:
	@$(CHECK_SHA256) licenses.sha256

verify-linkage: builds/process-report
	python3 ../tools/check-linkage.py --package libuv builds/process-report

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
