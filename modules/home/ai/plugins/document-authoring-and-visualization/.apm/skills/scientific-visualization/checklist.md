# Scientific data visualization checklist

A perceptually and cognitively grounded review checklist for scientific figures, tables, diagrams, and other visual displays of data.

Synthesized from Ware (2020), *Information Visualization: Perception for Design* (4th ed.), and Schloss (2025), "Perceptual and Cognitive Foundations of Information Visualization," *Annual Review of Vision Science*, 11, 303-330.

## 1 Purpose and data-task alignment

- [ ] **1.1** The visualization has a clearly defined communicative purpose (exploratory analysis, confirmatory display, narrative explanation, etc.).
- [ ] **1.2** The visualization type (chart, map, table, node-link diagram, or composite) is appropriate for the data structure (nominal, ordinal, interval, ratio, relational, spatial, temporal) and the primary analytic task (compare, correlate, cluster, rank, distribute, show trend, show part-to-whole, etc.). *(Ware Ch. 12, Table 12.1; Schloss "Perceiving")*
- [ ] **1.3** The visual encoding channel matches the task: position for precise point comparisons, length/height for magnitude, color for categories or summary overviews, area only when approximate judgments suffice. *(Cleveland & McGill ranking; Schloss "Perceiving"; Ware G5.15)*
- [ ] **1.4** If the same data could be shown in multiple formats, the chosen format supports the specific perceptual proxy the reader will need (e.g., stacked bars for comparing group means, overlaid bars for pairwise differences). *(Schloss "Role of Heuristic Processing"; Jardine et al. 2020)*

## 2 Visual hierarchy and salience

- [ ] **2.1** Important data elements and patterns are the most visually salient features in the display; less important elements (grids, borders, annotations) are visually subordinate. *(Ware G1.1, G1.2)*
- [ ] **2.2** Greater numerical quantities are represented by more visually distinct graphical elements (larger, more vivid, more textured) unless the analytic task specifically requires the opposite (e.g., an "alarm" for low values). *(Ware G1.3)*
- [ ] **2.3** Strong preattentive cues (color, orientation, size, motion) are reserved for the highest-priority distinctions; weaker cues are used only after strong ones are allocated. *(Ware G5.5)*
- [ ] **2.4** If a single element must "pop out," it is the only element distinctive on that particular feature channel (e.g., the only red item in a field of gray). *(Ware G5.6)*
- [ ] **2.5** Highlighting uses whatever feature dimension is least used elsewhere in the design. *(Ware G5.8)*
- [ ] **2.6** Symbols that must be mutually distinguishable use redundant coding (e.g., differ in both shape and color). *(Ware G5.10)*
- [ ] **2.7** No critical distinction relies on a conjunction of features that cannot be searched preattentively (e.g., "find the small red circle among large red circles and small blue circles"). *(Ware G5.11)*
- [ ] **2.8** Reference lines or grid lines, if present, are faint and unobtrusive so they aid reading accuracy without competing with the data. *(Ware G5.17)*

## 3 Encoding quantity

- [ ] **3.1** Position along a common scale or length/height is the primary channel for quantitative comparison whenever precision matters. *(Ware G5.15; Cleveland & McGill)*
- [ ] **3.2** Area is used only when rough magnitude comparisons suffice; its known under-estimation bias is acknowledged or mitigated (e.g., by direct labeling).
- [ ] **3.3** Volume of 3-D glyphs is **never** used to represent quantity. *(Ware G5.16)*
- [ ] **3.4** If multiple quantitative variables are encoded in a single glyph, separable (independently readable) dimensions are used when analytic processing is needed, and integral dimensions are used when holistic impression is desired. *(Ware G5.13, G5.14)*

## 4 Color: categorical (nominal) encoding

- [ ] **4.1** No more than ~10 colors are used for categorical coding; fewer if symbols must be identified against varied backgrounds. *(Ware G4.18)*
- [ ] **4.2** Color assignments leverage semantically meaningful associations where they exist (e.g., blue for water, red for danger/heat) and are congruent with the reader's inferred mapping. *(Schloss "Visual Semantics"; Lin et al. 2013; Ware G5.18)*
- [ ] **4.3** When concepts lack strong direct color associations, the chosen palette maximizes *semantic discriminability* — the degree to which the color-concept assignment system as a whole is unambiguous. *(Schloss "Semantic Discriminability Theory"; Mukherjee et al. 2022)*
- [ ] **4.4** Category colors use nameable hues (red, green, yellow, blue, brown, pink, purple, gray) where possible. *(Ware G4.16)*
- [ ] **4.5** Small symbols use higher-chroma (more vivid) colors; large background regions use low-chroma, high-lightness (pastel) colors. *(Ware G4.10, G4.12, G4.13)*
- [ ] **4.6** Every colored symbol has sufficient luminance contrast with its background; borders are added where isoluminance against parts of the background is possible. *(Ware G4.14, G4.15)*

## 5 Color: sequential and diverging colormaps

- [ ] **5.1** The rainbow/jet colormap is **not** used for continuous data. It is perceptually non-monotonic, extremely non-uniform in feature resolving power, and actively misleading. *(Ware Ch. 4; Borland & Taylor 2007)*
- [ ] **5.2** Sequential colormaps vary monotonically in luminance from one end to the other, ensuring consistent form perception. *(Ware G4.22)*
- [ ] **5.3** The colormap has adequate luminance variation throughout its extent to resolve spatial features. *(Ware G4.21)*
- [ ] **5.4** If both form perception and value reading from a legend are important, a spiral colormap cycling through hues while trending in luminance is considered. *(Ware G4.23)*
- [ ] **5.5** Diverging colormaps use a perceptually neutral color (white, gray, or black) at the zero or midpoint. *(Ware G4.24)*
- [ ] **5.6** The polarity of the colormap respects relational associations: in most contexts, darker = more (the "dark-is-more" bias). Departures are made only for strong domain convention and are clearly labeled. *(Schloss "Relational Associations"; Schloss et al. 2019)*
- [ ] **5.7** If multiple relational associations are active (e.g., dark-is-more and direct color-concept associations), they are aligned rather than placed in conflict; where conflict is unavoidable, the legend is unambiguous. *(Schloss "Combination Principle")*

## 6 Accessibility and color vision deficiency

- [ ] **6.1** All categorical distinctions that rely on color also include a secondary cue (shape, pattern, label, line style) for ~10% of male and ~1% of female readers with color vision deficiency. *(Ware Ch. 4)*
- [ ] **6.2** Sequential and diverging colormaps remain discriminable under protanopia/deuteranopia; variation in the yellow-blue direction and/or luminance is ensured. *(Ware G4.17)*
- [ ] **6.3** The visualization has been checked with a CVD simulator (e.g., Coblis, Sim Daltonism, or the Viridis-family palettes which are CVD-safe by construction).

## 7 Spatial layout, grouping, and Gestalt organization

- [ ] **7.1** Related information is placed close together (proximity principle); the average saccade between related elements is <= 5 degrees of visual angle where feasible. *(Ware G5.1, G6.1)*
- [ ] **7.2** Perceptual grouping (proximity, similarity, connectedness, common region, continuity) matches the conceptual grouping the reader should make. *(Ware Ch. 6; Schloss "Perceptual Organization for Constructing Takeaway Messages"; Shah et al. 1999)*
- [ ] **7.3** The grouping structure guides the reader toward the intended takeaway: comparisons the designer wants the reader to notice occur *within* perceptual groups, not between them. *(Schloss "Comprehending"; Fygenson et al. 2024)*
- [ ] **7.4** Relationships between entities are shown with connecting lines or ribbons where appropriate. *(Ware G6.3)*
- [ ] **7.5** Regions are defined by closed contours, color fills, or texture fills as appropriate to shape complexity. *(Ware G6.5)*
- [ ] **7.6** Data entities are perceived as figure, not ground; closure, common region, and layout all support figure-ground segregation. *(Ware G6.7)*

## 8 Legends, labels, and the encoded mapping

- [ ] **8.1** Direct labeling is used in preference to a detached legend whenever spatial layout permits. *(Schloss "Perceptual Organization for Decoding"; Milroy & Poulton 1979)*
- [ ] **8.2** If a separate legend is unavoidable, the order of items in the legend matches the spatial order of items in the plot (top-to-bottom or left-to-right). *(Schloss; Huestegge & Philipp 2011)*
- [ ] **8.3** All axes, colorbars, and categorical legends are clearly labeled with variable names and units.
- [ ] **8.4** The encoded mapping (which visual feature means what) can be decoded without ambiguity; it is not left to the reader to guess.
- [ ] **8.5** Written labels are linked to their graphical referents using Gestalt principles (proximity, connectedness, common region). *(Ware G8.20)*
- [ ] **8.6** Caption or title language references chart elements in the same spatial order they appear in the figure (to avoid cognitive mismatch). *(Schloss; Feeney et al. 2000)*

## 9 Semantic congruence and inferred mappings

- [ ] **9.1** Visual feature mappings are congruent with domain conventions and cultural expectations (e.g., red = hot, up = more, left-to-right = time progression in Western contexts). *(Ware G5.18; Schloss "Visual Semantics")*
- [ ] **9.2** The "dark-is-more" and "opaque-is-more" biases are respected in colormaps unless a well-established domain convention overrides them (in which case, the legend is prominent). *(Schloss "Relational Associations")*
- [ ] **9.3** Larger/bolder/higher graphical elements represent "more" of the mapped variable wherever sensible. *(Ware G1.3; Schloss "High-is-more bias")*
- [ ] **9.4** Data mapping conventions are standardized within a manuscript, presentation, or project; the same variable always gets the same visual encoding. *(Ware G1.4, G6.21)*

## 10 Representing uncertainty

- [ ] **10.1** If the data have meaningful uncertainty (confidence intervals, standard errors, posterior distributions, ensemble spread), it is visually represented — not omitted.
- [ ] **10.2** The chosen uncertainty representation (error bars, gradient bands, hypothetical outcome plots, ensemble displays) does not invite common misinterpretations (e.g., the "cone of uncertainty" width-risk confusion). *(Schloss "Visual Representations of Uncertainty"; Ruginski et al. 2016)*
- [ ] **10.3** The visual metaphor for uncertainty does not conflict with the data metaphor (e.g., blur used for uncertainty should not be confused with out-of-focus rendering used for depth).

## 11 Chart clutter, embellishment, and annotation

- [ ] **11.1** Non-data elements (gridlines, tick marks, borders, background fills) are minimized to those that serve a perceptual purpose (aiding position reading, grouping, or separation).
- [ ] **11.2** Graphical embellishments, if present, are *semantically rich* — they convey meaning about the data, aid memorability, or highlight the intended message. Purely decorative elements that add clutter without semantic value are removed. *(Schloss "Graphical Embellishment"; Ajani et al. 2022; Rensink 2011)*
- [ ] **11.3** The figure balances the "decluttered + focused" design philosophy: remove extraneous elements AND add selective emphasis (color, annotation, arrows) to highlight the key message. *(Ajani et al. 2022)*
- [ ] **11.4** Textual annotations, when used, are placed near the graphical elements they describe (proximity-based grouping). *(Schloss; Stokes et al. 2023b)*
- [ ] **11.5** Extraneous 3-D effects (gratuitous perspective on bar charts, drop shadows with no informational role) are avoided; they introduce perceptual bias without adding information. *(Zacks et al. 1998; Ware G5.16)*

## 12 Tables

- [ ] **12.1** The table is used because the reader needs to look up exact values or make comparisons across many dimensions — tasks for which tables outperform graphs. *(Ware Ch. 12)*
- [ ] **12.2** Rows and columns are sorted to reveal the most important pattern (e.g., descending by the primary outcome variable), not merely alphabetical or chronological order by default.
- [ ] **12.3** Visual coding (color, boldface, shading bands) is used sparingly to aid row tracking and highlight key values without overwhelming the data.
- [ ] **12.4** Numeric columns are right-aligned or decimal-aligned for easy comparison; text columns are left-aligned.
- [ ] **12.5** Units and variable names are in column headers, not repeated in every cell.

## 13 Diagrams and node-link displays

- [ ] **13.1** Node-link diagrams reserve spatial position for relational (topological) structure, not for encoding a quantitative variable (unless it is a geographic map overlay). *(Ware Ch. 6, Ch. 12)*
- [ ] **13.2** Node shapes, sizes, and colors encode attributes of entities; line thickness, color, and style encode attributes of relationships. *(Ware G6.22, G6.23)*
- [ ] **13.3** Directed relationships use tapering lines (broad end at source) or arrows; non-directed relationships use uniform lines. *(Ware G6.24)*
- [ ] **13.4** The layout minimizes edge crossings and uses white space to maintain readability.

## 14 Consistency and standardization

- [ ] **14.1** Visual encoding conventions are standardized *within* the paper/project: the same color, shape, and axis assignments are used for the same variable across all figures. *(Ware G1.4, G6.21; Schloss "Semantic Congruence")*
- [ ] **14.2** When a sequence of figures is presented (e.g., in a talk or multi-panel figure), transitions between successive panels minimize changes in visualization type, axis scales, and color encoding. *(Ware G9.10)*
- [ ] **14.3** Novel or unconventional encodings are used only when the estimated payoff substantially exceeds the learning cost, and they are accompanied by clear explanation. *(Ware G1.6, G1.7)*

## 15 Cognitive load and working memory

- [ ] **15.1** The number of distinct categories, colors, or symbols the reader must hold in working memory at once does not exceed ~4 for unfamiliar patterns. *(Ware Ch. 12)*
- [ ] **15.2** If more than ~4 categories exist, the design uses spatial separation, faceting, or interactive filtering to keep the instantaneous cognitive load manageable.
- [ ] **15.3** The visualization is as compact as possible (consistent with clarity) to reduce time spent on saccades between related elements. *(Ware G5.1)*

## 16 Awareness of bias and misinterpretation

- [ ] **16.1** The visualization does not inadvertently truncate axes, manipulate aspect ratios, or use other techniques that exaggerate or minimize effects. *(Pandey et al. 2015)*
- [ ] **16.2** The designer has considered how prior beliefs might bias the reader's interpretation of the data (e.g., confirmation bias amplifying perceived correlations that align with expectations). *(Schloss "Prior Knowledge and Cognitive Biases"; Xiong et al. 2023)*
- [ ] **16.3** The "curse of knowledge" is mitigated: the designer has tested the figure with a naive reader or has assumed the reader does not share the designer's domain expertise. *(Xiong et al. 2020)*
- [ ] **16.4** Where a visualization could guide the reader toward a particular conclusion by design choices (grouping, emphasis, annotation), the guidance is benevolent and transparent, not manipulative. *(Schloss "Comprehending")*

## 17 Final review

- [ ] **17.1** The figure is legible at the size it will actually be rendered (journal column width, slide projection, poster at arm's length, phone screen).
- [ ] **17.2** The figure has been checked in grayscale to verify that essential structure is preserved for readers who print in black-and-white.
- [ ] **17.3** Alt-text or a descriptive caption is provided for accessibility by screen readers.
- [ ] **17.4** Someone unfamiliar with the project can state the figure's main message within ~10 seconds of looking at it (the "squint test"). If not, consider revising the visual hierarchy.

## Key references

- Ware, C. (2020). *Information Visualization: Perception for Design* (4th ed.). Morgan Kaufmann.
- Schloss, K. B. (2025). Perceptual and cognitive foundations of information visualization. *Annual Review of Vision Science*, 11, 303-330.
