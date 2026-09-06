---

layout: ../layouts/MarkdownLayout.astro
title: About x2c
index: the project
deck: >-
  What x2c is, who makes it, and what you are and are not signing up for.
description: >-
  x2c is a self-hosting superset of C that compiles to C. Apache 2.0,
  founder-led, closed to code contributions, no support promise.
jump:
  - href: "#what-it-is"
    label: what it is
  - href: "#what-you-get-and-what-you-dont"
    label: the terms
  - href: "#license"
    label: license
  - href: "#bugs-and-security"
    label: bugs
---

## What it is

x2c is a superset of C that compiles to C. You get strings, lists, maps,
pattern matching, iteration, scoped cleanup, typed macros, and an embedded
Lisp. You keep C's types, layouts, headers, libraries, ABI, and every tool you
already own.

The compiler and runtime are written in x2c and translated through the same
pipeline they implement, in about forty-eight thousand lines. It compiles
itself four times and compares the generated C and headers each time. That is
not rigor. I do not trust me.

Nobody asked for another C. You might like this one anyway.

## What you get, and what you don't

You get a stable version, hosted here, that stays where you left it. You get
the source, Apache 2.0, and a fork the moment you want one. You do not get
support, a roadmap, a release schedule, a vote on the design, or a Discord.

My tree is public and moves wherever I currently think is best, which changes
when I learn something. File a bug if you like; I read them and fix the ones
that interest me. You are better off forking &mdash; one designer is why this
fits in 48,000 lines.

The project is closed to external code contributions at initial publication.
That is not a judgement about anyone's code. It is the same constraint as the
line count: one person keeps the whole thing in his head, and that is what
makes the whole thing readable.

## License

Apache License 2.0. The full text is
[in the repository](https://github.com/gwf/x2c/blob/main/LICENSE).

## Bugs and security

Ordinary defects belong in
[GitHub issues](https://github.com/gwf/x2c/issues).

x2c is experimental software with no stable release and no guaranteed
security-response service. Security reports are welcome and should be handled
privately; the current channel and its limits are stated in
[SECURITY.md](https://github.com/gwf/x2c/blob/main/SECURITY.md). Until a
private channel is published, do not put vulnerability details, exploit code,
or secrets in a public issue.
