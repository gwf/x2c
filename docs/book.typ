#set document(title: "The x2c Book", author: "The x2c authors", date: none)
#set page(paper: "a4", margin: (x: 22mm, top: 22mm, bottom: 23mm))
#set text(font: "Libertinus Serif", size: 10.5pt, lang: "en")
#set par(justify: true, leading: 0.65em, spacing: 0.8em)
#set heading(numbering: none)
#show raw: set text(font: "DejaVu Sans Mono", size: 8pt)
#set table(inset: 5pt, stroke: (bottom: 0.3pt + luma(85%)))
#set terms(hanging-indent: 1em)
#let horizontalRule = line(length: 100%, stroke: 0.4pt + luma(75%))
#let divider = horizontalRule
#show link: set text(fill: rgb("254c65"))
#show raw: set text(hyphenate: false)
#show raw.where(block: true): set block(breakable: true, inset: (y: 5pt))
#show raw.where(block: true): set par(justify: false, leading: 0.45em)
#show figure: set block(breakable: true)
#show table: set text(size: 8.5pt)
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  v(18mm)
  text(size: 27pt, weight: "regular", it.body)
  v(9mm)
}
#show heading.where(level: 2): it => {
  pagebreak(weak: true)
  block(above: 8mm, below: 6mm, text(size: 21pt, weight: "regular", it.body))
}
#show heading.where(level: 3): set text(size: 15pt)
#show heading.where(level: 4): set text(size: 12pt)

#align(left)[
  #v(38mm)
  #text(size: 44pt, weight: "regular")[The x2c Book]
  #v(8mm)
  #text(size: 17pt, fill: luma(35%))[The language, standard library, and compiler]
  #v(1fr)
  #text(size: 11pt)[The x2c authors]
  #v(3mm)
  #link("https://x2c-lang.dev")[x2c-lang.dev]
]
#pagebreak()
#set page(numbering: "i", number-align: center)
#outline(title: [Contents], depth: 2)
#pagebreak()
#counter(page).update(1)
#set page(numbering: "1", header: context {
  let chapters = query(heading.where(level: 2).before(here()))
  set text(size: 8pt, fill: luma(40%))
  if chapters.len() > 0 { chapters.last().body } else { [The x2c Book] }
  line(length: 100%, stroke: 0.3pt + luma(80%))
})

$body$
