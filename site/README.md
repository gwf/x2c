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

`make site` starts Astro and mdBook at Astro's printed `/x2c/` URL. It reloads
landing, About, component, style, site-content, and book changes; the book is
available under `/x2c/docs/`. `make doc-serve` starts only mdBook at its
printed URL with live reload for book changes.

`make site-build` builds the complete production site. `make site-serve`
rebuilds the site, then previews the landing page, About page, and book
together. Use the port each command prints; other workspaces may already be
using the default port.

`make site-check` builds the same site and checks its generated links,
fragments, canonical metadata, sitemap, and both site-to-book directions under
the selected `SITE_URL` and `SITE_BASE`.

The default URL is the repository Pages path at
`https://gwf.github.io/x2c/`. When a custom domain is acquired, set
`SITE_URL` to its origin and `SITE_BASE=/` for both local and Pages builds. To
rehearse those custom-domain routes and canonical URLs locally, run:

```sh
SITE_URL=https://x2c-lang.dev SITE_BASE=/ make site-serve
```

Check copy, layout, interactions, routes, fragments, and canonical metadata
in the local preview. Check DNS, TLS, redirects, the Pages configuration, and
CDN delivery after deployment.

`site/dist/` is generated and untracked. The build renders Astro first and
then mdBook into `site/dist/docs/`.

## Writing the public pages

Long-form landing and About prose and the code samples are in `src/content/`.
Structural labels, statistics, navigation, and calls to action remain in the
Astro pages and components:

- `home.md` is the hero copy; `title` and `kicker` are its frontmatter.
- `about.md` is the About page copy.
- `love.md`, `power.md`, and `magic.md` hold the three section introductions;
  each single-word title is frontmatter and its overview is ordinary Markdown.
- `install.md` is the installation code window.
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
code appears first, and the prose after it appears below. The descent slide has
no code, so it uses a `---` rule as the separator instead.

Fence a sample with ```` ```x2c ```` and it is highlighted by the same grammar
the VS Code extension uses (`etc/vsc-extension/syntaxes/`), coloured by the
site palette in `shiki-x2c.mjs`. Do not hand-write `<span>` markup for code.

Every ```` ```x2c ```` block on the site is compiled by
`tools/check-doc-examples.py`, which runs in `make doc-examples`. A line
starting with `~` is compiled but not shown, which is how a nine-line sample
can still be a complete program. A sample that genuinely cannot compile must
be tagged ```` ```x2c,ignore ```` with an `<!-- ignore: reason -->` comment
above it.
