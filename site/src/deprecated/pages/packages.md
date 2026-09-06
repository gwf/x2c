---
layout: ../layouts/MarkdownLayout.astro
title: Packages
index: integrations
deck: >-
  x2c has one flat namespace, so a package keeps its own. It compiles once
  into an archive, and an importing program reaches its names through an
  alias. Seven adapters for third-party C libraries build and test today.
description: >-
  x2c packages: what they are, how to import one, how to wrap your own C
  library, and the PCRE2 and yyjson adapters.
jump:
  - href: "#importing-a-package"
    label: importing
  - href: "#pcre2"
    label: pcre2
  - href: "#yyjson"
    label: yyjson
  - href: "#writing-one"
    label: writing one
---

## Importing a package

A package is a directory named for the package, with its public surface in
`src/` above `#pragma private`. An importing program names it and chooses how
its names arrive: an alias qualifies everything, and a `with` list pulls named
types into the flat namespace.

```text
import "yyjson" as json;
import "pcre2" with Regexp, RegexpCapture, RegexpMatch;
```

Nothing else changes. The archive links like any other static library, and the
C types underneath stay reachable.

## PCRE2

The PCRE2 adapter compiles expressions once, iterates matches lazily, and
returns captures as ordinary x2c values, named or numbered.

```text
int main(void) {
  Regexp request = Regexp.compile(
    %"^(?<method>[A-Z]+) (?<path>[^ ]+) HTTP/[0-9.]+ (?<status>[0-9]{3})$$",
    PCRE2_UTF | PCRE2_UCP
  );
  defer request.free();

  String log = %"GET /docs HTTP/1.1 200";
  foreach(RegexpMatch line, request.find_all(log))
    printf("%s %s\n", line[<method>], line[<status>]);
  return 0;
}
```

The accepted application is `packages/pcre2/examples/request-report.x`: it
parses an access-log batch, aggregates by method, and redacts tokens by
replacement.

## yyjson

The yyjson adapter gives a lossless document view. Ordered and duplicate
object members survive, numeric intent is exact, and conversion into x2c
values is something you ask for rather than something that happens to you.

```text
int main(void) {
  json.JsonDocument catalog =
    json.JsonDocument.read_file(%"catalog.json");
  defer catalog.free();

  json.JsonObject root = catalog.root().object();
  json.JsonArray releases = root[%"releases"].array();
  printf("%d releases\n", releases.len());
  return 0;
}
```

The accepted application is `packages/yyjson/examples/release-catalog.x`:
document views, exact numbers, explicit conversion, Patch, and serialization.

## Writing one

PCRE2 and yyjson are accepted. Five more — libcurl, termbox2, BLIS, libuv,
and raylib — are importable packages whose applications are awaiting review.
The rejected libevent client remains recorded in
`plans/archive/libevent-reference-client.md` rather than shipped as a package.

[Wrapping a C library](../docs/guide/wrapping-c-libraries.html) is the guide:
deciding what to expose, who owns each value the library hands back, keeping
the raw API reachable, errors that carry the library's own codes, and the Lisp
surface. The [packages chapter](../docs/guide/packages.html) covers import and
build mechanics.

This repository additionally requires an application accepted by its author
before a package counts as supported; that contributor rulebook is
[`packages/AGENTS.md`](https://github.com/gwf/x2c/blob/main/packages/AGENTS.md).

Packages need network-fetched sources and are outside the ordinary build.
