PACKAGE := libcurl
DEPENDENCY_PREFIX_VAR := CURL_PREFIX
include ../package.mk

OPENSSL_PREFIX ?= $(CURL_PREFIX)
CURL_INCLUDE := $(CURL_PREFIX)/include

PACKAGE_C_FLAGS := --c-include-dir src --c-include-dir $(CURL_INCLUDE)
PACKAGE_LINK := $(PACKAGE_DEPS)/lib/libcurl.a \
	-L$(OPENSSL_PREFIX)/lib -lssl -lcrypto
ifeq ($(shell uname -s),Linux)
CURL_CA_BUNDLE := /etc/ssl/certs/ca-certificates.crt
PACKAGE_LINK += -ldl -pthread
else
CURL_CA_BUNDLE := /etc/ssl/cert.pem
PACKAGE_LINK += -Wl,-framework,CoreFoundation -Wl,-framework,CoreServices \
	-Wl,-framework,SystemConfiguration
endif

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

verify-profile: verify-dependency verify-headers verify-pins
	@./verify-profile.sh "$(CURL_PREFIX)" "$(OPENSSL_PREFIX)" \
	  "$(CURL_CA_BUNDLE)"

verify-headers: $(DEPENDENCY_PREREQUISITE)
# One digest over the curl header tree's own digests, not a file manifest.
	@cd $(CURL_INCLUDE) && find curl -maxdepth 1 -type f -print | \
	  LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | \
	  cut -d" " -f1 | cmp -s - $(CURDIR)/header-tree.sha256
