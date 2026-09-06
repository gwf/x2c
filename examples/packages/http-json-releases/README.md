# HTTP plus JSON release report

This cross-package application imports both packages and links both
archives. libcurl fetches the bytes and yyjson parses them: one
`CurlEasy` fetches a release catalog with a user agent and a retained request
header, `Json.parse` turns the response text into ordinary x2c values, and
the summary goes back as one JSON body through `body()` and `request()`.

```x2c
import "libcurl" with CurlEasy, CurlResponse;
import "yyjson" with Json;
```

The program is named after its directory, and the Makefile lists
`examples/packages` first in `--package-dir`. The maintained adapters
remain under the separate `packages` search root.

This example uses the experimental libcurl package.

```sh
make build
make test
```

`make test` runs it against a deterministic local catalog. It does not
depend on the public network.
