# libcurl 8.22.0 macOS profile

This is the pinned build profile for the experimental libcurl package. The
curl source archive is `https://curl.se/download/curl-8.22.0.tar.xz`, SHA-256
`f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7`.

`dependency.json` configures a static library with OpenSSL 3.6.4 and no
optional third-party protocol, compression, resolver, internationalization,
or HTTP/2/3 backend:

```sh
./configure --prefix="$CURL_PREFIX" --disable-shared --enable-static \
  --with-openssl="$OPENSSL_PREFIX" --with-ca-bundle=/etc/ssl/cert.pem \
  --without-zlib --without-brotli \
  --without-zstd --without-libpsl --without-libidn2 --without-nghttp2 \
  --without-ngtcp2 --without-nghttp3 --without-libssh2 \
  --disable-threaded-resolver --disable-ftp --disable-file --disable-ldap \
  --disable-ldaps --disable-rtsp --disable-dict --disable-telnet \
  --disable-tftp --disable-pop3 --disable-imap --disable-smb \
  --disable-smtp --disable-gopher --disable-mqtt --disable-manual
make
make install
```

The resulting library supports HTTP, HTTPS, IPFS/IPNS gateways, and WebSocket
URLs using libcurl's own code. Its non-platform dependency closure is only
OpenSSL 3.6.4 (`libssl` and `libcrypto`). The final macOS executable also links
CoreFoundation, CoreServices, SystemConfiguration, libffi, and libSystem from
the platform. Other operating systems need separate build and test results.

OpenSSL 3.6.4 is Apache-2.0; the exact license file hash is pinned by
`make verify-profile`. libcurl retains its curl license. Both terms are under
`LICENSES/`. No dependency source or binary is vendored in Git; fetched sources and libraries stay in the shared dependency cache.

The OpenSSL source origin is the `openssl-3.6.4.tar.gz` release at
`https://github.com/openssl/openssl/releases/download/openssl-3.6.4/`,
SHA-256
`9bffaa1ad1e07b354c21bd3324ec02fa15579f45a7d0494b3e74bc449b7333ef`.

The default CA bundle is pinned to macOS's `/etc/ssl/cert.pem`; libcurl does
not inherit a configure-host probe result. A caller can select another trust
store through the raw `CURLOPT_CAINFO` or `CURLOPT_CAPATH` options.

Imported declarations preserve upstream `const`, `volatile`, and `restrict`
qualifiers. Treat read-only results and fields as their upstream declarations
require; x2c rejects conversions that discard these qualifiers. The
[qualifier notes](../FOREIGN-C-QUALIFIERS.md) describe the compiler change
and its regression fixtures.
