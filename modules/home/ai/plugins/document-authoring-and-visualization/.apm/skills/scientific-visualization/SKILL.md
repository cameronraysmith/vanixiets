---
name: scientific-visualization
description: >
  Perceptually and cognitively grounded guidance for designing and reviewing
  scientific figures, tables, diagrams, and other visual displays of data.
  Synthesized from Ware (2020) Information Visualization 4th ed. and Schloss
  (2025) Annual Review of Vision Science. Use when creating new visualizations,
  choosing chart types, selecting color palettes, reviewing figure quality,
  auditing accessibility, or evaluating any scientific display for adherence to
  perception research best practices. Supports two modes: design (proactive
  guidance for new visualizations) and review (systematic audit of existing ones).
---

# Scientific data visualization

Advisory skill for designing and reviewing scientific visualizations, grounded in the perception and cognition research of Ware (2020) and Schloss (2025).

## Modes

Determine the mode from context:

**Creating a new visualization?** Follow the design workflow below.
**Evaluating an existing visualization?** Follow the review workflow below.

## Design workflow

Given a dataset description, analytic task, and intended audience or medium, walk through these steps:

1. Clarify the communicative purpose (exploratory, confirmatory, narrative) and identify the primary analytic task (compare, correlate, cluster, rank, distribute, show trend, part-to-whole).
2. Select visualization type using the applicability map below.
3. Choose encoding channels by the precision hierarchy: position on common scale > length/height > angle/slope > area > color value > color hue. Use the highest-ranked channel for the most important comparison.
4. Select color strategy based on data type:
   - Nominal categories: <=10 nameable hues, maximize semantic discriminability, leverage meaningful associations. See checklist sections 4 and 6.
   - Ordered/continuous: monotonic-luminance sequential colormap (never rainbow/jet). Respect dark-is-more bias. See checklist sections 5 and 6.
   - Diverging: neutral midpoint (white/gray/black), symmetric luminance ramps. See checklist section 5.
5. Apply layout and grouping: place elements so that the comparisons you want readers to make occur *within* perceptual groups, not between them. Proximity < 5 degrees visual angle for related elements.
6. Verify against applicable checklist sections (load [checklist.md](checklist.md)) for the chosen visualization type.
7. Check final-review items: legibility at render size, grayscale survival, alt-text, and the 10-second squint test.

## Review workflow

Given a visualization (screenshot, description, or plotting code), produce a structured audit:

1. Classify the visualization type (chart/graph, table, node-link diagram, map, composite).
2. Determine applicable checklist sections using the applicability map below.
3. Load [checklist.md](checklist.md) and evaluate each applicable item.
4. For each finding, assign a severity:
   - *Critical* — misrepresents data or actively misleads the reader (e.g., rainbow colormap on continuous data, truncated axes that exaggerate effect, encoding quantity as 3D volume).
   - *Major* — significantly impairs comprehension or excludes readers (e.g., >10 categorical colors, no CVD accommodation, legend order mismatches data order, grouping opposes intended comparison).
   - *Minor* — suboptimal but comprehensible (e.g., overly prominent gridlines, unnecessary embellishment, inconsistent encoding across figures in a series).
   - *Advisory* — best practice where deliberate departure may be justified by domain convention or audience; note the tradeoff.
5. For each finding, provide a specific remediation citing the relevant Ware guideline or Schloss principle.
6. Summarize: count of findings by severity, top three highest-impact changes, and an overall assessment.

## Applicability map

Which checklist sections apply to which visualization type.
Sections not listed are universal and always apply.

| Section | Charts/graphs | Tables | Diagrams | Maps | Heatmaps |
|---------|:---:|:---:|:---:|:---:|:---:|
| 3 Encoding quantity | x | | | | |
| 4 Color — categorical | x | | x | x | |
| 5 Color — colormaps | x | | | x | x |
| 10 Uncertainty | x | | | x | |
| 12 Tables | | x | | | |
| 13 Diagrams/node-link | | | x | | |

Universal sections (always evaluate): 1, 2, 6, 7, 8, 9, 11, 14, 15, 16, 17.

## References

The full evaluation checklist with item-level citations:

| File | Contents |
|------|----------|
| [checklist.md](checklist.md) | Complete 17-section checklist with Ware guideline numbers and Schloss section references |

## See also

- `preferences-scientific-inquiry-methodology` for the epistemological framework these visualizations serve
- `preferences-style-and-conventions` for general formatting and documentation standards
