PACKAGE := libcurl
DEPENDENCY_PREFIX_VAR := CURL_PREFIX
include ../package.mk

OPENSSL_PREFIX ?= $(CURL_PREFIX)
CURL_INCLUDE := $(CURL_PREFIX)/include

PACKAGE_C_FLAGS := --c-include-dir src --c-system-dir $(CURL_INCLUDE)
PACKAGE_LINK := $(PACKAGE_DEPS)/lib/libcurl.a \
	-L$(OPENSSL_PREFIX)/lib -lssl -lcrypto \
	-Wl,-framework,CoreFoundation -Wl,-framework,CoreServices \
	-Wl,-framework,SystemConfiguration

# Every test and example talks to the package-local fixture server instead
# of the network, so one wrapper starts it and passes its base URL.
PACKAGE_TEST_COMMAND := python3 tools/run-fixture.py

.PHONY: example short-example lisp-example run run-lisp \
	verify-profile verify-headers

# Nothing links against libcurl until its pinned profile, headers, and
# licenses have been verified.
$(PACKAGE_ARCHIVE): | verify-profile

example: builds/endpoint-report

short-example: builds/page-titles

lisp-example: builds/inline-lisp

run: builds/page-titles builds/endpoint-report
	python3 tools/run-fixture.py builds/page-titles
	python3 tools/run-fixture.py builds/endpoint-report

run-lisp: builds/inline-lisp
	python3 tools/run-fixture.py builds/inline-lisp

verify-profile: verify-dependency verify-headers
	@test "$$($(CURL_PREFIX)/bin/curl-config --version)" = \
	  "libcurl 8.22.0"
	@test "$$($(OPENSSL_PREFIX)/bin/openssl version | cut -d' ' -f1-2)" = \
	  "OpenSSL 3.6.4"
	@test "$$(shasum -a 256 LICENSES/OpenSSL-3.6.4.txt | \
	  cut -d' ' -f1)" = \
	  7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a
	@test "$$(shasum -a 256 LICENSES/curl-8.22.0.txt | \
	  cut -d' ' -f1)" = \
	  82f2f4427d6545ee5aaac4f0b80428da6cc8ba41c2cf5da3a03680ec327b9681
	@config="$$($(CURL_PREFIX)/bin/curl-config --configure)"; \
	  echo "$$config" | grep -q -- \
	    "--with-ca-bundle=/etc/ssl/cert.pem" || exit 1; \
	  for option in without-zlib without-brotli without-zstd \
	    without-libpsl without-libidn2 without-nghttp2 without-ngtcp2 \
	    without-nghttp3 without-libssh2 disable-threaded-resolver \
	    disable-ftp disable-file disable-ldap disable-ldaps disable-rtsp \
	    disable-dict disable-telnet disable-tftp disable-pop3 disable-imap \
	    disable-smb disable-smtp disable-gopher disable-mqtt; do \
	    echo "$$config" | grep -q -- "--$$option" || exit 1; \
	  done

verify-headers: $(DEPENDENCY_PREREQUISITE)
	@test "$$(cd $(CURL_INCLUDE) && \
	  find curl -maxdepth 1 -type f -print | LC_ALL=C sort | \
	  xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1)" = \
	  506b4f38572b387a06f8fb59803cd93ca193f88d98df1e02bf78798eeb20743e

builds/endpoint-report: examples/endpoint-report.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/example \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/inline-lisp: examples/inline-lisp.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/inline-lisp-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<

builds/page-titles: examples/page-titles.x $(PACKAGE_ARCHIVE) | builds
	$(X2C) build --output $@ --build-dir builds/page-titles-build \
	  $(PACKAGE_X_FLAGS) $(PACKAGE_C_FLAGS) $<
