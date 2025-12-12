// Tutorials flow diagram for vanixiets documentation
// Shows the progression from bootstrap through tutorials to guides.
// Vertical layout: Bootstrap → Secrets → [Darwin, NixOS] → Guides & Concepts
//
// Build: typst compile --format svg tutorials-flow.typ tutorials-flow.svg
// Optimize: svgo tutorials-flow.svg -o ../public/diagrams/tutorials-flow.svg

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#set page(width: auto, height: auto, margin: 1em)
#set text(font: "Inter", size: 9pt)

// Color palette - using operations green for tutorial/operational content
#let tutorial-fill = rgb("#e8f5e9")
#let tutorial-stroke = rgb("#6ba37b")

// Node styling
#let tutorial-node(coord, label, fill: white, stroke: black) = node(
  coord,
  align(center)[#label],
  fill: fill,
  stroke: stroke + 1pt,
  corner-radius: 4pt,
  inset: 8pt,
)

#diagram(
  spacing: (15mm, 12mm),
  node-stroke: 0.8pt,
  edge-stroke: 1pt + rgb("#666666"),

  // Vertical flow: Bootstrap → Secrets → [Darwin, NixOS] → Next
  tutorial-node((1, 0), [Bootstrap to Activation], fill: tutorial-fill, stroke: tutorial-stroke),
  tutorial-node((1, 1), [Secrets Setup], fill: tutorial-fill, stroke: tutorial-stroke),
  tutorial-node((0, 2), [Darwin Deployment], fill: tutorial-fill, stroke: tutorial-stroke),
  tutorial-node((2, 2), [NixOS Deployment], fill: tutorial-fill, stroke: tutorial-stroke),
  tutorial-node((1, 3), [Guides & Concepts], fill: tutorial-fill, stroke: tutorial-stroke),

  // Edges: Bootstrap → Secrets
  edge((1, 0), (1, 1), "->"),

  // Edges: Secrets → Darwin, Secrets → NixOS
  edge((1, 1), (0, 2), "->", bend: -15deg),
  edge((1, 1), (2, 2), "->", bend: 15deg),

  // Edges: Darwin → Next, NixOS → Next
  edge((0, 2), (1, 3), "->", bend: 15deg),
  edge((2, 2), (1, 3), "->", bend: -15deg),
)
