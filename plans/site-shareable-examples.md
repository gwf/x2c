> Status: active
> Local implementation committed and rebased onto origin/main at efed52a.
> Site statistics refreshed from make stats. Publication remains pending.
> Started from origin/main at 1bc7e67.
> Torch, continuous Game of Life, and the replacement Lisp tic-tac-toe example
> are implemented for local review. All four example pages now use continuous
> code and annotation columns. The Lisp opponent runs inside a native playable game.
> Landing-page captions and code remain exactly as pulled from main.

# Shareable x2c examples

## Result and scope

Every existing landing gallery example has a stable fragment and copyable link.
The hero introduces four standalone examples in navigation order:

- Recognize handwritten digits with the Torch package.
- Give your game a Lisp player; edit its tic-tac-toe strategy without recompiling.
- Run Game of Life, with one continuous code panel and aligned caption sections.
- Differentiate a function and fit a growth curve.

The compact autodiff example stays in Code is Magic and links to the existing
standalone growth-fitting page. The agreement example stays in the gallery;
its duplicate standalone page and social assets are removed.

Preserve the landing page's established Love/Power/Magic framing, package
layout, captions, code samples, and vertical spacing. New detail content lives
separately. Keep everything local until Gary approves publication.

## Implementation

1. `site/src/lib/examples.ts` loads the existing slide Markdown in filename
   order. Explicit slide slugs make fragments independent of tab positions.
   Articles identify their related slide through `slide`; their own route
   slug may differ, as with embedded Lisp and the runtime Lisp gallery slide.
2. `FeatureCarousel.astro` supplies static panel IDs, permalink/copy actions,
   and an article link where one exists. `src/lib/carousel.ts` owns selection,
   keyboard/swipe behavior, query-preserving history updates, fragment entry,
   and inactive-panel accessibility. Without JavaScript, slides remain stacked.
3. `ExamplePanel.astro` preserves the original gallery presentation and media
   behavior. The static detail route uses separate panel Markdown, reusing the
   same component through `ExampleWalkthrough.astro`. An article's optional
   `extraPanels` supplies further source excerpts within one continuous code
   column. Its annotations share one continuous column opposite the code.
   Authored line references align notes to actual highlighted lines; normal
   document flow prevents overlap when an explanation needs more room. The
   columns remain paired above 720px, with fluid padding and type sizing.
   Images retain compact display limits when the columns stack.
4. The detail route shares header, footer, syntax highlighting, copy controls,
   canonical metadata, and `CoreSetup.astro`. Each page provides its own run
   introduction, command recipe, code label, source and guide links. There is
   one complete setup recipe, without repeated 'already built' disclosures.
5. Detail subtitles use the available header width. Code uses compact source
   formatting; captions explain the mechanisms and observable results without
   artificial metaphors, repeated print explanations, or padding for height.
6. Review the completed authored diff for unnecessary machinery, duplicated
   content, source accuracy, and layout regressions before final validation.

## Content and source

| Page | Existing source | Presentation |
| --- | --- | --- |
| Torch | `packages/torch/examples/mnist.x` | Convolutional model, training, batched evaluation, actual digit predictions including errors, exact dataset and package preparation. |
| Embedded Lisp | `examples/magic/tic-tac-toe.x`, `tic-tac-toe.xlisp` | Native binding and interpreter excerpts, compact Lisp opponent, and short aligned annotations. Complete game remains available through the source link. |
| Game of Life | `packages/termbox2/examples/game-of-life.x` | One continuous program beside its recording and aligned notes for drawing, generation updates, and the main loop. Displayed variable `terminal` becomes `term`; executable source is unchanged. |
| Autodiff | `examples/magic/autodiff-fit.x` | Growth simulation, generated gradient, checkpointing and verified fitting output. Gallery keeps its original energy-function sample. |

The C-and-Lisp gallery's pointer-identity demonstration remains as authored on
main. It receives no expanded caption or substitute sample.

Torch, Life, and autodiff reuse existing executable examples. Embedded Lisp adds
a small native game and an editable strategy using the established binding decorators
and interpreter. No compiler/runtime changes are required. A static source
endpoint serves these authored files directly for local review and publication;
it introduces no checked-in source copies. Excerpts are clearly labeled;
full-source links provide complete programs. Prediction assets must come from
an actual x2c classifier run, not invented labels or a Python-trained model.

## Sharing and measurement

The hero and next-example links share the articles' explicit order.
Each neutral breadcrumb names its example; only the x2c label links home. Previous and next links use that same circular order; the breadcrumb returns
to the top of the home page. The existing sitemap build discovers static routes.
Each detail page has its own 1200 by 630 social image with an editable SVG
source; global metadata still has the shared image fallback.

Optional Plausible analytics are enabled only with `SITE_ANALYTICS=production`
and `PLAUSIBLE_SCRIPT_URL` in an intended production build. Development always
disables them. The shared loader also serves mdBook. The two custom events
measure example selection and actions, never successful installation.
The measurement page explains enabled measurement. No external
account configuration, activation, outreach, or publication is authorized.

## Validation

- Compare all 36 landing slide files with the pulled main, ignoring only the
  newly added `slug` fields. Captions and samples must match byte for byte.
- Run the existing examples using prepared local tools. Verify tic-tac-toe games, immediate wins and blocks, draw detection, invalid input and EOF. Check
  the pictured board against a real game. Verify Torch predictions against a real classifier run.
- Compare Game of Life excerpts with package source, allowing only the stated
  local variable rename. Its full executable was previously built and run in
  a terminal; no behavior changes are proposed.
- Run `make site-check` for static routes, metadata, links, fragments and
  sitemap, plus existing site Node tests. Check root and subpath builds when
  route changes affect both.
- Inspect desktop and narrow layouts, page captions/code balance, hero links,
  gallery deep links, copy controls and previous/next navigation in the local browser.
- No new mandatory gate. Code publication checks apply only if publication is
  later authorized; this batch stops at the local preview.

## Plan review

Existing Markdown, source programs, Astro routing and book tooling establish
content, route generation and local-reference resolution. Consumers do not
add a second validator for those established facts. The original carousel
controller is shared; the detail renderer reuses the existing panel and setup
components. Extra panel names are simple authored ordering, not another page
framework. Removing the agreement page removes duplicate content and assets.

No compiler, runtime or package API changes are needed. Source snippets retain
ordinary repository code and native library operations. Square bounds are checked before native array access; occupied squares cannot
be played. Human input and Lisp moves use the same legal-square check. No separate validator, negative fixture,
cache or mandatory process step is introduced. The final diff review checks these same properties before
local validation and any separately authorized publication.
