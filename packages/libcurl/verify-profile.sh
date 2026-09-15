#!/bin/sh
# Check that the pinned libcurl and OpenSSL prefixes are the admitted build.
#
#   ./verify-profile.sh <curl prefix> <openssl prefix> <ca bundle>
#
# The Makefile calls this rather than spelling the comparisons out in a
# recipe: a long continued recipe line is where Apple's make 3.81 on x86_64
# loses bytes.
set -eu

curl_prefix=${1:?usage: verify-profile.sh <curl> <openssl> <ca bundle>}
openssl_prefix=${2:?missing openssl prefix}
ca_bundle=${3:?missing ca bundle}

fail() { echo "libcurl profile: $*" >&2; exit 1; }

version=$("$curl_prefix/bin/curl-config" --version)
[ "$version" = "libcurl 8.22.0" ] || fail "curl is $version"

openssl_version=$("$openssl_prefix/bin/openssl" version | cut -d' ' -f1-2)
[ "$openssl_version" = "OpenSSL 3.6.4" ] || fail "openssl is $openssl_version"

configure=$("$curl_prefix/bin/curl-config" --configure)
case "$configure" in
  *"--with-ca-bundle=$ca_bundle"*) ;;
  *) fail "not built against $ca_bundle" ;;
esac

for option in without-zlib without-brotli without-zstd without-libpsl \
  without-libidn2 without-nghttp2 without-ngtcp2 without-nghttp3 \
  without-libssh2 disable-threaded-resolver disable-ftp disable-file \
  disable-ldap disable-ldaps disable-rtsp disable-dict disable-telnet \
  disable-tftp disable-pop3 disable-imap disable-smb disable-smtp \
  disable-gopher disable-mqtt; do
  case "$configure" in
    *"--$option"*) ;;
    *) fail "built without --$option" ;;
  esac
done
