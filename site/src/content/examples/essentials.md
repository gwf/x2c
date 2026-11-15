---
slug: essentials
navTitle: x2c essentials
order: -2
section: tours
fullSource: true
title: x2c essentials.
description: A short walkthrough of the distinctions that matter when writing x2c.
source: examples/tours/essentials.x
output: examples/expected/tours-essentials.stdout
run: ./x2c run examples/tours/essentials.x
runIntro: This is one native program. It needs no input files or optional packages. Its final section uses native threads, so run it locally rather than in the browser.
guide: docs/guide/from-c.html
---
Start here for the concepts: dynamic values alongside native types, immutable
values versus shared objects, quoted data, methods and protocols, patterns,
lifetime, and compile-time code. Each section prints a result that makes the
distinction visible.

Read the numbered sections in order. The `main` function at the bottom runs
all nine. The comments explain the gotchas beside the code that demonstrates
them, including exact tags versus conversion and copying a handle versus
copying its contents.

For more forms and details, continue to the
[language walkthrough](../language/). Both pages display the complete checked-in
program and its expected output.
