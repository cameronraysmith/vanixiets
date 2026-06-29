# Toolchain reference

Per-format compilation details, flags, and gotchas.

## Typst / CeTZ

Primary compiler: `typst compile`

```bash
# Single file to SVG
typst compile input.typ --format svg output.svg

# Single file to PDF (default)
typst compile input.typ output.pdf

# Watch mode for interactive development
typst watch input.typ --format svg output.svg
```

CeTZ is a typst package for programmatic vector graphics (coordinate transforms, path construction, plots).
Fletcher extends CeTZ with node-and-edge diagram support.
Chronos provides sequence diagrams.

Gotchas:
- Typst SVG output uses `<text>` elements with embedded fonts by default, producing larger SVGs but ensuring accurate rendering without font dependencies.
- svgo default configuration may strip font data needed for text rendering. If text appears broken after optimization, use `svgo --config '{"plugins": [{"name": "preset-default", "params": {"overrides": {"removeUnknownsAndDefaults": false}}}]}'`.
- For multi-page documents, `typst compile --format svg` produces one SVG per page as `output-1.svg`, `output-2.svg`, etc.

## LaTeX / TikZ / PGF

Primary workflow: compile to PDF, then convert.

```bash
# Compile to PDF
latexmk -pdf -interaction=nonstopmode input.tex

# PDF to SVG (page-by-page)
pdf2svg input.pdf output.svg

# Alternative: DVI to SVG (bypasses PDF, higher fidelity for vector graphics)
latex input.tex
dvisvgm --no-fonts input.dvi -o output.svg
```

The `dvisvgm` path produces cleaner SVG (paths instead of font references) but requires the DVI workflow (`latex` not `pdflatex`).
For documents using PDF-only features (transparency, embedded images), the `latexmk -pdf` then `pdf2svg` path is necessary.

Gotchas:
- TikZ `external` library pre-compiles individual figures via `\tikzexternalize`, caching each `tikzpicture` as a separate PDF.
- `dvisvgm --font-format=woff2` embeds fonts as WOFF2 for web-compatible SVG output.
- `latexmk -pdf` handles multi-pass compilation (bibliography, cross-references) automatically.
- For standalone TikZ figures, use `\documentclass[tikz]{standalone}` for tightly-cropped output without page margins.

## D2

Primary compiler: `d2`

```bash
# Default SVG output
d2 input.d2 output.svg

# Specify layout engine
d2 --layout elk input.d2 output.svg
d2 --layout dagre input.d2 output.svg

# Watch mode
d2 --watch input.d2 output.svg
```

Layout engines: `dagre` (default, fast), `elk` (better for complex graphs, handles edge routing), `tala` (proprietary, highest quality, requires license).

Gotchas:
- D2 SVG output is clean and generally does not need aggressive svgo optimization.
- `--theme` controls color scheme; `--dark-theme` provides dark mode variant.
- D2 supports `near` keyword for label positioning and `grid-rows`/`grid-columns` for tabular layouts.

## Mermaid

Primary compiler: `mmdc` (mermaid-cli)

```bash
# SVG output
mmdc -i input.mmd -o output.svg

# PNG output (direct, without SVG intermediate)
mmdc -i input.mmd -o output.png -w 1200

# PDF output
mmdc -i input.mmd -o output.pdf

# With custom theme
mmdc -i input.mmd -o output.svg --theme dark
```

Gotchas:
- mmdc requires a browser engine (puppeteer/chromium) for rendering; first invocation may be slow.
- Mermaid SVG output often contains inline styles that svgo can optimize significantly.
- For CI/headless environments, configure puppeteer with `--no-sandbox` via puppeteer config JSON.
- `.mmd` or `.mermaid` file extensions are both conventional.

## PlantUML

Primary compiler: `plantuml`

```bash
# SVG output
plantuml -tsvg input.puml

# PNG output (default)
plantuml input.puml

# PDF output
plantuml -tpdf input.puml

# Specify output directory
plantuml -tsvg -o build/ input.puml
```

Gotchas:
- PlantUML requires a JVM; the `plantuml-c4` package bundles C4 architecture diagram support.
- SVG output includes embedded font metrics that may differ across JVM versions.
- For large diagrams, increase memory: `JAVA_TOOL_OPTIONS=-Xmx1g plantuml -tsvg input.puml`.
- `!include` directives resolve relative to the source file, not the working directory.

## Graphviz

Primary compiler: `dot` (and other layout engines)

```bash
# SVG output with dot layout
dot -Tsvg input.gv -o output.svg

# Other layout engines
neato -Tsvg input.gv -o output.svg    # spring model (undirected)
fdp -Tsvg input.gv -o output.svg      # force-directed
circo -Tsvg input.gv -o output.svg    # circular layout
sfdp -Tsvg input.gv -o output.svg     # scalable force-directed

# PDF output
dot -Tpdf input.gv -o output.pdf
```

Layout engine selection: `dot` for DAGs and hierarchies, `neato`/`fdp` for undirected graphs, `circo` for ring topologies, `sfdp` for large graphs (>1000 nodes).

Gotchas:
- Graphviz SVG output uses absolute coordinates extensively; svgo optimization is effective.
- `dot -Tsvg` produces SVG with `<title>` elements containing node/edge IDs, useful for programmatic post-processing.
- For consistent fonts across platforms, set `fontname="sans-serif"` or embed fonts.
- `overlap=false` and `splines=true` prevent overlapping nodes and produce curved edges.
