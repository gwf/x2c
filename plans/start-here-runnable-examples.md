# Runnable Start Here examples

> Status: Approved by Gary on 2026-11-19, including native-only threading lessons.

Keep **x2c essentials** and **Language walkthrough** under **Start here** at
`/examples/essentials/` and `/examples/language/`. Give each lesson the same
reading layout as Love, Power, and Magic: a heading, a short explanation, the
complete standalone source, output, and a local command. Put lesson links under
each tour in the sidebar, in reading order. Rename **Language examples** to
**Site Examples** above Love, Power, and Magic.

## Lessons and source

Split the nine essentials lessons and twelve walkthrough lessons into checked-in
programs under `examples/tours/essentials/` and `examples/tours/language/`.
Use one `main` per existing demonstration. Keep its supporting functions, types,
protocols, or macros in the same file where needed to understand the example.
Carry over the allocation scope each demonstration needs and include `meta.x`
where used. Keep the teaching sequence and the distinctions explained in the
current comments.

| Page | Lesson order |
| --- | --- |
| x2c essentials | Values, sharing, quoting, classes, operators, patterns, lifetime, compile-time code, threads |
| Language walkthrough | Values, text, collections, iteration, functions, methods, classes, operators, patterns, lifetime and errors, compile-time code, threads and channels |

Replace the two aggregate manifest rows and stdout files with one row and
expected stdout file per program. The lesson heading and sidebar carry the
sequence, so remove lesson-number prefixes from stdout. Preserve the values and
behavior each lesson demonstrates. Update links and commands in the repository
and examples READMEs, compiler README, and agent task directory to point to the
new lesson directories or individual programs as appropriate.

## Site and browser execution

Use the existing topic page and `ExamplesTopic.astro` renderer at both current
URLs. Move the tour introductions and guide links into the topic pages. Retire
the two monolithic articles and their article-only `fullSource` branch. Keep the
Start Here landing links. Group the new entries by their tour section in the
sidebar. Use the catalog's existing anchor rule, so the full program ID
`tours/essentials/sharing` links to
`/examples/essentials/#tours-essentials-sharing`. Assign lesson order explicitly
in the content entries.

Register each lesson in the gallery with a short `home: false` content entry
that links to its checked-in source. Use the gallery's existing `source` form
so the x2c file owns the program. Extend the shared playground selector to
derive IDs for source-backed examples under `examples/` and include the new
directories in the site source glob. Keep optional and package-backed programs
on their current path. The homepage galleries continue to use their existing
entries.

Target browser Run for the 19 lessons without threads. Each Run starts that
lesson's precompiled WebAssembly program and displays actual output beside
expected output. Both thread lessons use real `Thread` and `Channel` operations.
Give those lessons expected output and a local command with the same native-only
treatment as Love, Power, and Magic. The current WebAssembly runtime does not
provide those operations. If another lesson fails with the existing runtime,
check whether the lesson can be made compatible while preserving what it teaches.
Bring back any unresolved compatibility issue for review.

## Verification

- Run all 21 programs through the existing examples checks. Compare each result
  with the corresponding old stdout section after the planned prefix removal.
- Run the existing gallery check and site tests. Verify that the gallery checker
  accepts the source links and that the current non-tour examples still resolve.
- Require WebAssembly assets when building the site for verification. Confirm
  that the published program list contains the 19 intended lesson IDs, and run
  each lesson in the browser against its expected stdout.
- Check both routes, lesson deep links, sidebar order, and the Site Examples
  heading at desktop and narrow widths. Check that both thread lessons provide
  usable local commands and expected output.

## Plan review

- The manifest already owns expected stdout. The gallery already maps content
  to checked-in source, and the playground build already records which programs
  it produced. The topic pages consume those records without a second check.
- The design removes the aggregate drivers and reuses the topic renderer,
  sidebar, gallery checker, WebAssembly build, and Run controls. The shared
  selector needs to recognize the existing source-backed gallery records so
  source-owned lessons can use the same runner.
- Each program shows its own entry point and keeps its supporting declarations
  close to the demonstration. The split introduces no shared tour driver.
- No new validator, dedicated diagnostic, or negative fixture is proposed.
