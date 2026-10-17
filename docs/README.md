# Building the book

The Markdown in `src/` supplies both the website and the PDF.
`src/SUMMARY.md` defines their chapter order and hierarchy.

## Website

Run `make doc-build` from the repository root to render the mdBook website
in `docs/book/`. Run `make doc-serve` for a live preview.

## PDF

Install Pandoc 3.12 or newer and Typst 0.15 or newer. On macOS:

```sh
brew install pandoc typst
make doc-pdf
```

The result is `docs/x2c-book.pdf`, a build product that Git ignores.
Each release candidate builds it once and retains `x2c-book.pdf` as a release
asset, with its size and SHA-256 in the candidate manifest. Staging and
production distribute those same bytes. Each release keeps its own download;
the website footer links to the PDF for the deployed release.
The target stops with an install hint when
either tool is missing or Pandoc is too old. It sets no document date and
takes `SOURCE_DATE_EPOCH` from the last commit. This optional target does not build
the compiler, run the website highlighter, or change the Markdown sources.
It includes the entire book, including the generated API reference.

If another installation shadows either executable, select the intended one:

```sh
make doc-pdf PANDOC=/opt/homebrew/bin/pandoc TYPST=/opt/homebrew/bin/typst
```

`tools/book-pdf.lua` reads chapters in summary order, expands the grammar
include, omits hidden x2c example lines, and resolves book links to PDF
destinations. Links to repository files outside the book point to GitHub.
`docs/book.typ` owns page layout, fonts, contents, headers, and page numbers.
The fonts ship with Typst; no separate font installation is needed.

Code uses plain monospace text. The website's interactive expanders and
syntax colors are not part of the print edition. After changing the template,
inspect prose, long code examples, API signatures, and multi-page tables in
the generated PDF.
