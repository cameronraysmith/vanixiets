// Reading paths overview diagram for vanixiets documentation
// Renders 15 documentation reading paths organized into 5 groups
// with dependency arrows showing recommended reading order.
//
// Build: typst compile --format svg reading-paths.typ reading-paths.svg
// Optimize: svgo reading-paths.svg -o ../public/diagrams/reading-paths.svg

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#set page(width: auto, height: auto, margin: 1em)
#set text(font: "Inter", size: 9pt)

// Color palette - muted tones that work in light and dark contexts
#let foundations-fill = rgb("#e8f4f8")
#let foundations-stroke = rgb("#5ba3b5")
#let understanding-fill = rgb("#f0e8f5")
#let understanding-stroke = rgb("#9b7bb5")
#let operations-fill = rgb("#e8f5e9")
#let operations-stroke = rgb("#6ba37b")
#let deployment-fill = rgb("#fff8e1")
#let deployment-stroke = rgb("#c9a227")
#let support-fill = rgb("#fce4ec")
#let support-stroke = rgb("#c27b8c")

// Node styling
#let path-node(coord, num, label, fill: white, stroke: black) = node(
  coord,
  align(center)[#text(weight: "bold")[#num.] #label],
  fill: fill,
  stroke: stroke + 1pt,
  corner-radius: 4pt,
  inset: 6pt,
)

// Group label styling
#let group-label(coord, label, fill: white, stroke: black) = node(
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

  // === FOUNDATIONS GROUP (top-left) ===
  group-label((0, 0), [Foundations], fill: foundations-fill, stroke: foundations-stroke),
  path-node((0, 1), "1", [Bootstrap], fill: foundations-fill, stroke: foundations-stroke),
  path-node((0, 2), "2", [Module System], fill: foundations-fill, stroke: foundations-stroke),

  // === UNDERSTANDING GROUP (top-right) ===
  group-label((2.5, 0), [Understanding], fill: understanding-fill, stroke: understanding-stroke),
  path-node((2, 1), "3", [Architecture], fill: understanding-fill, stroke: understanding-stroke),
  path-node((3, 1), "12", [AMDiRE], fill: understanding-fill, stroke: understanding-stroke),
  path-node((3, 2), "13", [Decisions], fill: understanding-fill, stroke: understanding-stroke),

  // === OPERATIONS GROUP (middle) ===
  group-label((1, 3), [Operations], fill: operations-fill, stroke: operations-stroke),
  path-node((0, 4), "4", [Host Onboarding], fill: operations-fill, stroke: operations-stroke),
  path-node((1, 4), "5", [User Setup], fill: operations-fill, stroke: operations-stroke),
  path-node((0.5, 5), "6", [Secrets], fill: operations-fill, stroke: operations-stroke),
  path-node((2, 4), "7", [Packages], fill: operations-fill, stroke: operations-stroke),
  path-node((1.5, 6), "8", [Fleet], fill: operations-fill, stroke: operations-stroke),
  path-node((2.5, 5), "15", [Troubleshooting], fill: operations-fill, stroke: operations-stroke),

  // === PLATFORM DEPLOYMENT GROUP (bottom-center) ===
  group-label((1.5, 7), [Platform deployment], fill: deployment-fill, stroke: deployment-stroke),
  path-node((1, 8), "9", [Cloud/NixOS], fill: deployment-fill, stroke: deployment-stroke),
  path-node((2, 8), "10", [Darwin], fill: deployment-fill, stroke: deployment-stroke),

  // === SUPPORT GROUP (right side) ===
  group-label((3.5, 4), [Support], fill: support-fill, stroke: support-stroke),
  path-node((3.5, 5), "11", [Contributing], fill: support-fill, stroke: support-stroke),
  path-node((3.5, 6), "14", [Reference], fill: support-fill, stroke: support-stroke),

  // === EDGES: Conceptual track ===
  // p2 --> p3 --> p12 --> p13
  edge((0, 2), (2, 1), "->", bend: -15deg),
  edge((2, 1), (3, 1), "->"),
  edge((3, 1), (3, 2), "->"),

  // === EDGES: Operational track ===
  // p1 --> p4, p1 --> p5
  edge((0, 1), (0, 4), "->"),
  edge((0, 1), (1, 4), "->", bend: 10deg),

  // p4 --> p6, p5 --> p6
  edge((0, 4), (0.5, 5), "->"),
  edge((1, 4), (0.5, 5), "->"),

  // p6 --> p8
  edge((0.5, 5), (1.5, 6), "->"),

  // === EDGES: To deployment ===
  // p8 --> p9, p8 --> p10
  edge((1.5, 6), (1, 8), "->"),
  edge((1.5, 6), (2, 8), "->"),

  // === EDGES: Cross-domain connections ===
  // p3 --> p8
  edge((2, 1), (1.5, 6), "->", stroke: rgb("#999999") + 0.8pt),

  // p3 --> p7
  edge((2, 1), (2, 4), "->", stroke: rgb("#999999") + 0.8pt),

  // p3 --> p11
  edge((2, 1), (3.5, 5), "->", stroke: rgb("#999999") + 0.8pt, bend: 15deg),

  // p7 --> p15
  edge((2, 4), (2.5, 5), "->"),
)
