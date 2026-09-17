PACKAGE := libuv
DEPENDENCY_PREFIX_VAR := LIBUV_PREFIX
include ../package.mk

LIBUV_STATIC := $(LIBUV_PREFIX)/lib/libuv.a
PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(LIBUV_PREFIX)/include
PACKAGE_LINK := $(LIBUV_STATIC)

.PHONY: example short-example run check-profile verify-profile verify-linkage

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

# Nothing links against libuv until its pinned prefix has been checked.
$(PACKAGE_ARCHIVE): | verify-profile

verify-profile: verify-dependency check-profile verify-pins

verify-linkage: builds/process-report
	python3 ../tools/check-linkage.py --package libuv builds/process-report
