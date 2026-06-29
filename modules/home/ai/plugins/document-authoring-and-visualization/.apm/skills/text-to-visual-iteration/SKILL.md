---
name: text-to-visual-iteration
description: >
  Mechanical workflow for iterative compilation and refinement of text-based
  visual specifications (tikz/pgf, typst/cetz, d2, mermaid, plantuml, graphviz,
  and similar text-to-visual languages) into rendered output (SVG, PNG, PDF).
  Covers the compile-inspect-refine iteration loop using both SVG text inspection
  and multimodal bitmap vision for dual-channel feedback. Use when authoring,
  compiling, or iteratively refining any text-to-visual pipeline, choosing output
  formats, setting up build artifact directories, post-processing SVG output
  (svgo, resvg, svg2pdf), or optimizing layout and graphical properties through
  successive compilation cycles.
---

# Text-to-visual iteration

Mechanical workflow for compiling text-based visual specifications into rendered output and iteratively refining them through a dual-feedback loop combining structural SVG inspection with multimodal bitmap perception.

## Artifact conventions

Source files live in a git-tracked directory.
All rendered output goes to a gitignored build artifact directory (e.g., `build/`, `dist/`, `_output/`).

Generate three output formats per source file:

1. SVG — primary output, optimized via svgo
2. PNG — accessory, rasterized via resvg for high-fidelity output
3. PDF — accessory, converted via svg2pdf

The three-format convention ensures portability across web (SVG), documents and slides (PDF), and contexts requiring bitmap images (PNG).

## Post-processing pipeline

After compiling source to SVG, run the post-processing chain:

```bash
svgo input.svg -o optimized.svg
resvg optimized.svg output.png --width <target-width>
svg2pdf optimized.svg output.pdf
```

For batch processing, iterate over source files and preserve the filename stem across outputs.
Target width for resvg depends on context: 1200px for web and slides, 2400px for print, or use `--dpi 300` for DPI-based sizing.

## Iteration loop

For each refinement cycle:

1. **Compile** source to SVG using the appropriate toolchain (see dispatch table below, or load [references/toolchains.md](references/toolchains.md) for per-format details).

2. **Post-process** the SVG through the pipeline above.

3. **Inspect structurally** by reading the optimized SVG as text:
   - Element hierarchy, grouping (`<g>` elements), transforms
   - Coordinates, dimensions, viewBox geometry
   - Style attributes: fill, stroke, font-size, opacity, stroke-width
   - Text content and positioning
   - Path data for shape verification

4. **Inspect perceptually** by reading the PNG via multimodal vision:
   - Layout balance and whitespace distribution
   - Label legibility and overlap detection
   - Color contrast and discriminability
   - Visual hierarchy and emphasis
   - For scientific figures: evaluate against the `scientific-visualization` checklist

5. **Diagnose** by comparing structural and perceptual findings.
Structural inspection reveals what the SVG contains; perceptual inspection reveals how it reads visually.
Mismatches between intended structure and perceived result indicate refinement targets.

6. **Refine** by modifying the source file to address findings.
Prefer source-level changes over SVG post-processing hacks.

7. **Repeat** until the visualization meets quality criteria or the user approves.

### Feedback channel selection

| Concern | Channel | Rationale |
|---------|---------|-----------|
| Element overlap or collision | SVG text | Coordinate arithmetic is precise |
| Color values and consistency | SVG text | Exact hex/rgb values readable |
| Overall visual balance | Bitmap vision | Gestalt perception needed |
| Label readability at target size | Bitmap vision | Rendering-dependent |
| Font rendering quality | Bitmap vision | SVG text shows intent, bitmap shows result |
| Alignment precision | SVG text | Coordinate comparison |
| Accessibility (contrast, CVD) | Both | SVG for values, bitmap for perceptual verification |

### When to skip dual feedback

Not every iteration needs both channels.
Use SVG-only inspection for purely structural changes (repositioning elements, adjusting dimensions, fixing attribute values).
Use bitmap-only inspection when the source format compiles to raster directly (e.g., LaTeX to PDF to PNG without SVG intermediate).
Use both channels when evaluating overall quality or when structural changes have perceptual consequences.

## Toolchain dispatch

| Source format | Extension | Compiler | SVG output |
|---|---|---|---|
| Typst / CeTZ | `.typ` | `typst compile --format svg` | Native |
| LaTeX / TikZ / PGF | `.tex` | `latexmk -pdf` then `pdf2svg` or `dvisvgm` | Via intermediate |
| D2 | `.d2` | `d2 --layout elk` | Native (default) |
| Mermaid | `.mmd` | `mmdc -i input.mmd -o output.svg` | Native |
| PlantUML | `.puml` | `plantuml -tsvg` | Native |
| Graphviz | `.gv`, `.dot` | `dot -Tsvg` | Native |

For compilation flags, format-specific gotchas, and alternative output paths, load [references/toolchains.md](references/toolchains.md).

## Scientific visualization integration

When the output serves a scientific purpose (data figures, experimental results, statistical plots), load `scientific-visualization/SKILL.md` and apply its design or review workflow.
The perceptual inspection step in the iteration loop is the integration point: evaluate the bitmap against the scientific-visualization checklist during step 4.

## See also

- `scientific-visualization` — perceptual design principles and review checklist
- `preferences-style-and-conventions` — general formatting and documentation standards
