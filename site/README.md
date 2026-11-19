# x2c public site

Astro builds the public landing and About pages. The landing page is the short
introduction and includes the installation instructions. The mdBook in
`docs/` is rendered under `/docs/` as part of the same static site.

From the repository root:

```sh
make site
make doc-serve
make site-build
make site-serve
```

`make site` starts Astro and mdBook at Astro's printed URL. It reloads
landing, About, component, style, site-content, and book changes; the book is
available under `/docs/`. `make doc-serve` starts only mdBook at its
printed URL with live reload for book changes.

`make site-build` builds the complete production site. `make site-serve`
rebuilds the site, then previews the landing page, About page, and book
together. Use the port each command prints; other workspaces may already be
using the default port.

`make site-check` builds the same site and checks its generated links,
fragments, canonical metadata, sitemap, and both site-to-book directions under
the selected `SITE_URL` and `SITE_BASE`.

The site is served from the custom domain `https://x2c-lang.dev` at the root
path, and builds use that origin and `SITE_BASE=/` by default. Set `SITE_URL`
and `SITE_BASE` only to build for another origin or path, for example to
rehearse a subpath deployment locally:

```sh
SITE_URL=https://example.github.io SITE_BASE=/x2c make site-serve
```

Check copy, layout, interactions, routes, fragments, and canonical metadata
in the local preview. Check DNS, TLS, redirects, the Pages configuration, and
CDN delivery after deployment.

`public/x2c-version.txt` and `public/packages/index.txt` are checked in at the
last published release and rewritten by `tools/release-candidate.py site` at
candidate assembly.

`site/dist/` is generated and untracked. The build renders Astro first and
then mdBook into `site/dist/docs/`.

Landing-page repository counts are recomputed from the current source tree
when Astro renders the page, using `tools/repo-metrics.py --summary-json`.
Python 3 and `cloc` must be available on `PATH`, including for direct Astro
builds and development previews. The Pages workflow installs both. The
compiler and library cards count `.x` files recursively in `src/` and `lib/`.
Embedded Lisp and macros remain part of their containing file's count.

Like `make stats`, these figures separate nonblank code lines from
comment-only lines using x2c's C-style comment syntax, including in Lisp
files. A line with both code and a comment counts as code. The detailed
`tools/repo-metrics.py --json` inventory instead reports physical lines,
including comments and blanks, from tracked files.

## Unlisted interface demos

`/secret/` links to the standalone `/secret/gallery/` and `/secret/stress/`
demos. These stable routes have `noindex` metadata and no public navigation
links. `site-config.mjs` excludes the entire subtree from the sitemap.
They are not book content and therefore do not enter the book search index.
Anyone with a URL can open or share it; there is no authentication.

The normal `npm run build` builds x2c's WebAssembly runtime and the x2cui
web targets, then installs their HTML, JavaScript, and WebAssembly beneath
`dist/secret/` before the book and deployment metadata are finalized.
Emscripten 6.0.13, a native compiler, and Python 3 are required; Linux also
needs X11 development headers for the package's native build step.
Missing tools or failed demo builds fail the site build rather than omit
the demos. Pages, candidate, and website-only staging workflows provide
these tools; the resulting demos travel with the complete site artifact.

For local verification, build and serve `dist` (or use `npm run preview`).
The demos require Memory64, JavaScript Promise Integration, and WebGL 2.
The stress test suspends while its tab is hidden, retaining its state.
Its FPS remains subject to browser/display pacing and CUI's frame limit.

## Optional measurement

Analytics is off unless both `SITE_ANALYTICS=production` and
`PLAUSIBLE_SCRIPT_URL` are set for the build. The latter is the personalized
`https://plausible.io/js/pa-....js` URL from the site's Plausible installation
settings. Leave them unset for ordinary local builds and previews; the
development server never loads the tracker. The public site and book share the same loader.

Before enabling measurement, create the `Example select` and `Example action`
custom-event goals in Plausible. The loader leaves automatic pageviews
enabled and disables automatic outbound, download, and form events to avoid
counting example actions twice. It does
not enable localhost tracking or hash-based pageviews.

Example selections carry `example`, `section`, and `method`; example actions
carry `example`, `action`, and `surface`. Only authored example identities and
action names are supplied. A successful copy is an action, not evidence of
installation or a successful local run. Real event receipt requires a separate
production verification after activation; local handler checks cannot prove it.

Plausible documents the [installation snippet](https://plausible.io/docs/plausible-script),
[configuration options](https://plausible.io/docs/script-extensions), and
[custom events](https://plausible.io/docs/custom-event-goals).

## Writing the public pages

Long-form landing and About prose and the code samples are in `src/content/`.
Structural labels, statistics, navigation, and calls to action remain in the
Astro pages and components:

- `home.md` is the hero copy; `titleSubject`, `titleOpening`, `titleEnding`,
  and `kicker` are its frontmatter.
- `about.md` is the About page copy.
- `love.md`, `power.md`, and `magic.md` hold the three section introductions;
  each title is frontmatter and its overview is ordinary Markdown.
- `install.md` is the installation code window. `run` holds the release
  install commands; `source` holds the commands that follow the source build
  from `core-setup.ts`.
- `packages.md` introduces the package example gallery. Its slides contain
  excerpts from `packages/*/examples/`, links to the complete programs, and
  captured output. Refresh the excerpt and result together when its example
  changes; package-dependent excerpts use the documented `x2c,ignore` fence.
  Slide frontmatter may supply `status` and an `image` path relative to
  `public/`, with `imageAlt`, `imageWidth`, and `imageHeight`. Animated GIFs
  also supply `imagePoster` for the pause control and reduced-motion fallback.
- `packages-build.md` supplies the shell commands beside the package
  introduction, using the same code-window styling as installation.
- `slides/*.md` are the Love, Power, Magic, and Packages slides, one file per
  slide, ordered by filename. Frontmatter names the `section`, the `tab`
  label, and the `title` shown below the code.

A slide is split into its two panels at the end of its first code block: the
code appears first, and the prose after it appears below. A slide without
code may use a `---` rule as the separator instead.

Fence a sample with ```` ```x2c ```` and it is highlighted by the same grammar
the VS Code extension uses (`etc/vsc-extension/syntaxes/`), colored by the
site palette in `shiki-x2c.mjs`. Do not hand-write `<span>` markup for code.

Every ```` ```x2c ```` block on the site is compiled by
`tools/check-doc-examples`, which runs in `make doc-examples`. A line
starting with `~` is compiled but not shown, which is how a nine-line sample
can still be a complete program. Home galleries show labeled source excerpts;
Examples shows the complete source. Hide the `main` wrapper and test-only
setup with `~`, retaining the feature declarations and operations. The excerpt
renderer removes the hidden wrapper's indentation while preserving nested
indentation. Keep `main` last in the complete example.

`examples/gallery.json` maps each slide to its complete program. After editing
a generated example's slide, run
`builds/0/x2c script tools/check-gallery-examples --update`; do not edit the
generated example separately. Source-owned package excerpts must stay faithful
to their linked program. Gallery links use the same routes as the Examples
index. The former `/playground/?example=...` interface redirects to those
routes; `/playground/programs/` still holds the shared WebAssembly assets.

Complete programs use `src/content/examples/*.md` metadata and the shared
article layout. The two Start here tours use the same topic layout as Love,
Power, and Magic. Each lesson is a source-owned gallery entry with
`home: false`. The gallery supplies the lesson title and order, and the
manifest supplies its expected output. The browser runs each supported lesson
independently. The threads lessons run locally. `/examples/` opens Essentials.


A sample that genuinely cannot compile must
be tagged ```` ```x2c,ignore ```` with an `<!-- ignore: reason -->` comment
above it.

## Prepared release destinations

Release tooling can set `SITE_SOURCE_REF` to the selected full source SHA.
The complete build pins rendered source links and source ZIP downloads to
that revision, including Markdown slides and book pages. Source checkout
examples explicitly check out the same SHA. Ordinary development builds
retain their existing defaults.

For candidate output, also set `SITE_RELEASE_CHANNEL=staging`,
`SITE_CANDIDATE_ID=candidate-<full-sha>-<run-id>-<attempt>`,
`SITE_URL=https://staging.x2c-lang.dev` and `SITE_BASE=/`. Every rendered page
carries the candidate identity in `x2c-release-channel` and `x2c-candidate`
metadata and a `noindex` robots tag, and its canonical URL names the
production page. `robots.txt` disallows all crawling. The landing install
commands use a fresh `X2C_PREFIX` and the explicit staging package index.
Book examples continue documenting ordinary production behavior. The
compiler's default package index does not change.

Run the complete `npm run build`, not just `astro build`: the final book step
also applies destination links and banners across the complete site. Release
assembly must then overlay the selected version, index, candidate metadata and
installer with candidate-specific defaults before archiving the whole output.
The site build alone does not produce a publishable candidate installation.
These options do not activate workflows or change live routing.

## Benchmark comparison materials

[BENCHMARKS.md](BENCHMARKS.md) describes the versioned results/charts archive,
portable public exports, future Astro integration, and measurement caveats.

## Cheat-sheet PDF

`npm run build` generates `dist/x2c-cheatsheet.pdf` from the built
`/cheatsheet/` page using headless Chromium. The page's HTML, fonts, and print
CSS are the only layout source. The renderer waits for fonts, uses the CSS
page size and margins, includes background graphics, and omits browser headers
and footers.

After `npm ci`, install the browser once with `npx playwright install chromium`.
On Linux CI, use `npx playwright install --with-deps chromium`; the candidate
workflow does this automatically. To regenerate only the PDF after an Astro
build, run `npm run pdf:cheatsheet`.
