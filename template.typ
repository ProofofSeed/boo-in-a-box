/* Document template. */
#let template(
  title: [Paper Title], // paper title
  author-meta: "",
  author-block: none,
  abstract: none, // paper abstract (optional)
  accent-color: black, // accent colour (optional)
  body, // paper body
) = {
  // Set document properties:
  set document(title: title, author: author-meta)
  set page(paper: "a4", margin: (x: 1in, y: 1in), numbering: "1")
  set par(justify: true, spacing: 1em, first-line-indent: 0em)
  set text(lang: "en", region: "gb", font: "New Computer Modern", size: 12pt)
  show link: set text(fill: accent-color)
  show ref: set text(fill: accent-color)
  show cite: set text(fill: accent-color)
  set heading(numbering: "1.1.1.")
  show heading: set block(below: 1em)
  set enum(indent: 10pt, body-indent: 6pt, numbering: "1.a.i.")
  set list(indent: 10pt, body-indent: 6pt)
  show raw: set text(font: "Fira Code", size: 10pt, weight: 400)
  show raw: set block(spacing: 1.5em)
  set math.equation(numbering: "(1)")
  show math.equation: set block(spacing: 1.5em)
  set figure(placement: none)
  show figure.caption: set text(size: 12pt)

  // Display paper title:
  align(center, text(20pt, title))

  // Display authors list:
  v(10mm, weak: true)
  if author-block != none {
    set align(center)
    set text(size: 14pt)
    set table(stroke: none)
    author-block
  }
  v(10mm, weak: true)

  // Display abstract:
  if abstract != none [
    #set text(11pt, weight: 400)
    ABSTRACT. #abstract
  ]

  // Display body:
  body
}
