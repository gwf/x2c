---
section: packages
tab: libcurl
title: Three pages, one batch.
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "libcurl" with CurlBatch, CurlEasy;

static String page_title(String html) {
  return html.split("<title>").last().string()
    .split("</title>").car();
}

List pages = %("/guide" "/reference" "/source");
CurlEasy curl = CurlEasy.new().timeouts(1000, 3000);
defer curl.free();
List urls = pages.map(
  %!(String page) => site + page
);

CurlBatch batch = curl.get_all(urls, 3);
defer batch.free();
for (int i = 0; i < batch.len(); i++)
  printf("%s: %s\n",
    pages[i].string()[1:],
    page_title(batch.response(i).text())
  );
```

Fetch three URLs concurrently and print their page titles. A lambda
joins each page path to the site's base URL; `get_all` runs the batch
with up to three transfers at once. Read each response body as a String
and extract its title.

The complete example accepts the site URL on the command line and
defines the small title-extraction helper. This captured run uses the
package's local fixture pages.

Output:

```text
guide: x2c Language Guide
reference: x2c Reference
source: x2c Source
```

[Full example](https://github.com/gwf/x2c/blob/main/packages/libcurl/examples/page-titles.x) / [Package guide](https://github.com/gwf/x2c/blob/main/packages/libcurl/README.md)
