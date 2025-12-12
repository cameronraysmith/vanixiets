// AMDiRE (Architecture, Model, Design, Implementation, Requirements, Evolution) diagram
// Visualizes the three-layer documentation architecture with dependency flows
// from Context through Requirements to Solution layers.
//
// Build: typst compile --format svg development-amdire.typ development-amdire.svg
// Optimize: svgo development-amdire.svg -o ../public/diagrams/development-amdire.svg

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#set page(width: auto, height: auto, margin: 1em)
#set text(font: "Inter", size: 9pt)

// Color palette - muted professional tones for light and dark contexts
#let context-fill = rgb("#e8f4f8")
#let context-stroke = rgb("#5ba3b5")
#let requirements-fill = rgb("#f0e8f5")
#let requirements-stroke = rgb("#9b7bb5")
#let solution-fill = rgb("#e8f5e9")
#let solution-stroke = rgb("#6ba37b")

// Node styling for layer elements
#let layer-node(coord, label, fill: white, stroke: black) = node(
  coord,
  align(center)[#label],
  fill: fill,
  stroke: stroke + 1pt,
  corner-radius: 4pt,
  inset: 6pt,
)

// Group label styling for layer headers
#let layer-label(coord, label, fill: white, stroke: black) = node(
  coord,
  text(weight: "bold", size: 10pt)[#label],
  fill: fill,
  stroke: stroke + 1.5pt,
  corner-radius: 6pt,
  inset: 8pt,
)

#diagram(
  spacing: (12mm, 10mm),
  node-stroke: 0.8pt,
  edge-stroke: 1pt + rgb("#666666"),

  // === CONTEXT LAYER (top) ===
  layer-label((1, 0), [Context Layer], fill: context-fill, stroke: context-stroke),
  layer-node((0, 1), [Project Scope], fill: context-fill, stroke: context-stroke),
  layer-node((1, 1), [Stakeholders], fill: context-fill, stroke: context-stroke),
  layer-node((2, 1), [Goals], fill: context-fill, stroke: context-stroke),
  layer-node((3, 1), [Constraints], fill: context-fill, stroke: context-stroke),

  // === REQUIREMENTS LAYER (middle) ===
  layer-label((1.5, 3), [Requirements Layer], fill: requirements-fill, stroke: requirements-stroke),
  layer-node((0.5, 4), [System Vision], fill: requirements-fill, stroke: requirements-stroke),
  layer-node((1.5, 4), [Usage Model], fill: requirements-fill, stroke: requirements-stroke),
  layer-node((2.5, 4), [Functions], fill: requirements-fill, stroke: requirements-stroke),
  layer-node((3.5, 4), [Quality], fill: requirements-fill, stroke: requirements-stroke),

  // === SOLUTION LAYER (bottom) ===
  layer-label((1.5, 6), [Solution Layer], fill: solution-fill, stroke: solution-stroke),
  layer-node((0.5, 7), [Architecture], fill: solution-fill, stroke: solution-stroke),
  layer-node((1.5, 7), [ADRs], fill: solution-fill, stroke: solution-stroke),
  layer-node((2.5, 7), [Traceability], fill: solution-fill, stroke: solution-stroke),

  // === EDGES: Context to Requirements ===
  edge((0, 1), (0.5, 4), "->", bend: -10deg),
  edge((1, 1), (1.5, 4), "->"),
  edge((2, 1), (2.5, 4), "->"),
  edge((3, 1), (3.5, 4), "->", bend: 10deg),

  // === EDGES: Context to Solution (direct influences) ===
  edge((0, 1), (0.5, 7), "->", stroke: rgb("#999999") + 0.8pt, bend: -15deg),
  edge((3, 1), (2.5, 7), "->", stroke: rgb("#999999") + 0.8pt, bend: 15deg),

  // === EDGES: Requirements to Solution ===
  edge((0.5, 4), (0.5, 7), "->"),
  edge((1.5, 4), (1.5, 7), "->"),
  edge((2.5, 4), (1.5, 7), "->", bend: 10deg),
  edge((3.5, 4), (2.5, 7), "->", bend: -10deg),
)
