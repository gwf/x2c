---
slug: language
navTitle: Language walkthrough
order: -1
section: tours
fullSource: true
title: Walk through the language.
description: From a Var to your own types, operators, patterns, macros, and cooperating threads.
source: examples/tours/language.x
output: examples/expected/tours-language.stdout
run: ./x2c run examples/tours/language.x
runIntro: This is one native program. It needs no input files or optional packages. Run it locally to include the final threads-and-channels section.
guide: docs/guide/x2c-syntax-map.html
---
This walkthrough introduces the main language features in twelve steps.
It begins with `Var`, then builds through text and collections to functions,
user-defined types, classes, protocols, pattern matching, cleanup, and
compile-time code. Two workers finish by counting words through a channel.

Definitions appear beside the section that introduces them. Read from the top;
`main` at the bottom calls each section in order. Small recurring examples
keep the focus on the language rather than application setup.

The shorter [essentials walkthrough](../essentials/) emphasizes concepts and
gotchas. The [language guide](../../docs/guide/from-c.html) supplies the fuller
rules, including source organization and alternate indentation syntax.
