---
name: doc-to-md
description: Convert a scholarly reference (paper or book) from PDF or arXiv LaTeX source into a structured, modular markdown repository with indexed sections, README, and token counts.
argument-hint: <reference> [--pdf <path>...] [--workspace <name>] [--aggregate <path>]
disable-model-invocation: true
---

# doc-to-md: scholarly document to modular markdown

Convert a scholarly reference into a git-initialized repository of well-organized markdown files.
Accepts a bibliographic citation plus local PDF path(s), producing modular section files, a TOC index, and a README with token counts.

## Arguments

Parse `$ARGUMENTS` for:

- **Reference**: citation text, DOI, or arXiv identifier
- **PDF paths**: one or more local PDF files (main document, supplement)
- **Workspace**: target subdirectory name under `~/projects/` (e.g. `modeling-workspace`)
- **Aggregate**: path to a subtree aggregate repository (e.g. `~/projects/modeling-workspace/modeling-references`).
  When provided, the completed repo is added as a subtree to the aggregate after GitHub publish.

If arguments are ambiguous or incomplete, ask the user to clarify before proceeding.

## Phase 1: input resolution

Extract from the reference: title, authors, year, DOI and/or arXiv ID.

Derive the repo name in lowercase kebab-case as `short-title-or-author-year-descriptor`.
Examples: `effective-theories-in-physics`, `arruda-2025-compositional-amortized-inference`, `ventre-2023-one-model-fits-all`.

Check for arXiv preprint availability.
If an arXiv ID is provided or discoverable from the DOI, Path A (LaTeX source) is available.
Otherwise, use Path B (PDF-only).

Present the resolved inputs, chosen pathway, and target path `~/projects/<workspace>/<repo-name>/` to the user for confirmation before proceeding.

### Prerequisites

`git-lfs` must be installed and available on `PATH`.
All binary file types used in scholarly documents are tracked via git-lfs to keep repository sizes manageable and avoid GitHub's 100 MB file size limit.
The comprehensive tracking list covers: `*.pdf`, `*.jpeg`, `*.jpg`, `*.png`, `*.eps`, `*.gif`, `*.webp`, `*.tiff`, `*.svg`.

## Phase 2a: arXiv LaTeX pathway

When arXiv LaTeX source is available, download and convert.

### Initialize repo

```bash
mkdir -p ~/projects/<workspace>/<repo-name> && cd "$_"
git init && git commit --allow-empty -m "initial commit (empty)"
git lfs install --local
cat > .gitattributes << 'GITATTR'
*.pdf filter=lfs diff=lfs merge=lfs -text
*.jpeg filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.png filter=lfs diff=lfs merge=lfs -text
*.eps filter=lfs diff=lfs merge=lfs -text
*.gif filter=lfs diff=lfs merge=lfs -text
*.webp filter=lfs diff=lfs merge=lfs -text
*.tiff filter=lfs diff=lfs merge=lfs -text
*.svg filter=lfs diff=lfs merge=lfs -text
GITATTR
git add .gitattributes && git commit -m "chore: configure git-lfs for binary files"
```

### Download LaTeX source

```bash
curl -L "https://arxiv.org/e-print/<arxiv-id>" -o arxiv-source.tar.gz
mkdir -p latex && tar -xzf arxiv-source.tar.gz -C latex/
rm arxiv-source.tar.gz
git add latex/ && git commit -m "feat: add arXiv LaTeX source"
```

### Convert LaTeX to markdown

Identify the main `.tex` file (the one containing `\documentclass` or `\begin{document}`).
Handle common obstacles: custom style files, missing bibliography, or macro-heavy documents.

```bash
pandoc latex/<main>.tex -o <repo-name>.md \
  --wrap=none \
  --standalone \
  --from=latex \
  --to=markdown
git add <repo-name>.md && git commit -m "feat: convert LaTeX to markdown via pandoc"
```

If pandoc fails on complex LaTeX (custom macros, missing packages), fall back to marker on the PDF as in Path B.
Note the fallback in the README if this occurs.

### Copy local PDF

If a local PDF was also provided, rename to lowercase kebab-case on copy (see Path B for naming convention):

```bash
mkdir -p pdfs && cp "<pdf-path>" "pdfs/<first-author>-<year>-<title-fragment>.pdf"
git add pdfs/ && git commit -m "feat: add source PDF"
```

## Phase 2b: PDF-only pathway

When only PDF(s) are available, convert via marker.

### Initialize repo

```bash
mkdir -p ~/projects/<workspace>/<repo-name> && cd "$_"
git init && git commit --allow-empty -m "initial commit (empty)"
git lfs install --local
cat > .gitattributes << 'GITATTR'
*.pdf filter=lfs diff=lfs merge=lfs -text
*.jpeg filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.png filter=lfs diff=lfs merge=lfs -text
*.eps filter=lfs diff=lfs merge=lfs -text
*.gif filter=lfs diff=lfs merge=lfs -text
*.webp filter=lfs diff=lfs merge=lfs -text
*.tiff filter=lfs diff=lfs merge=lfs -text
*.svg filter=lfs diff=lfs merge=lfs -text
GITATTR
git add .gitattributes && git commit -m "chore: configure git-lfs for binary files"
```

### Copy and rename source PDFs

Rename PDFs to lowercase kebab-case on copy: `<first-author>-<year>-<title-fragment>.pdf`.
For multiple PDFs from the same reference, append a disambiguating suffix like `-supplement`.
Example: `gorin-2022-rna-velocity-unraveled.pdf` and `gorin-2022-rna-velocity-unraveled-supplement.pdf`.

```bash
mkdir -p pdfs
cp "<original-path>" "pdfs/<first-author>-<year>-<title-fragment>.pdf"
git add pdfs/ && git commit -m "feat: add source PDFs"
```

### Set up Python environment

`marker-pdf` requires Python 3.12 or earlier (incompatible with 3.13+).
Pin the version explicitly to avoid build failures from the system Python.

```bash
uv init --name doc-convert --python 3.12
uv python pin 3.12
uv add "marker-pdf>=1.7.4,<1.11" tiktoken
```

Use `uv run` to invoke marker rather than activating the venv, since shell state does not persist between tool calls.

Add a `.gitignore`:

```
.venv/
__pycache__/
```

```bash
git add .gitignore pyproject.toml uv.lock && git commit -m "chore: add uv project for PDF conversion"
```

### Convert PDFs

Marker conversion can be slow, especially on CPU fallback (potentially hours for long documents).
Run marker in the background using the Bash tool's `run_in_background: true` parameter to avoid the 10-minute timeout limit, then poll for completion.

```bash
# run in background:
cd <repo-dir> && uv run marker_single pdfs/<main>.pdf --output_dir ./ --output_format markdown
```

Check progress by reading the background task output.
Once complete:

```bash
git add <output-dir>/ && git commit -m "feat: convert main PDF via marker"
```

If a supplement PDF exists, run it the same way (background, then commit):

```bash
# run in background:
cd <repo-dir> && uv run marker_single pdfs/<supplement>.pdf --output_dir ./ --output_format markdown
```

### Marker troubleshooting on macOS Apple Silicon

The `surya-ocr` layout model used by marker can fail with torch tensor index errors on the MPS (Metal Performance Shaders) backend.
These errors typically manifest as `IndexError` or `RuntimeError` inside `torch/nn/modules/module.py` during the layout recognition step.

If `marker_single` crashes, apply these fallbacks in order, stopping at the first one that succeeds.
Both `PYTORCH_MPS_DISABLE=1` and `TORCH_DEVICE=cpu` are needed — torch 2.10+ may ignore `PYTORCH_MPS_DISABLE` alone.
CPU fallbacks are significantly slower (potentially hours for long documents).
Always run these in the background using `run_in_background: true` and poll for completion.

**Fallback 1** — force CPU backend (slower but avoids MPS bugs):

```bash
cd <repo-dir> && PYTORCH_MPS_DISABLE=1 TORCH_DEVICE=cpu uv run marker_single pdfs/<file>.pdf --output_dir ./ --output_format markdown
```

**Fallback 2** — CPU with reduced batch sizes and no multiprocessing:

```bash
cd <repo-dir> && PYTORCH_MPS_DISABLE=1 TORCH_DEVICE=cpu uv run marker_single pdfs/<file>.pdf \
  --output_dir ./ --output_format markdown \
  --disable_multiprocessing \
  --layout_batch_size 1 \
  --detection_batch_size 1 \
  --recognition_batch_size 1
```

**Fallback 3** — skip the layout model entirely by forcing all pages to be treated as text blocks (fastest, loses layout fidelity for tables and figures):

```bash
cd <repo-dir> && PYTORCH_MPS_DISABLE=1 TORCH_DEVICE=cpu uv run marker_single pdfs/<file>.pdf \
  --output_dir ./ --output_format markdown \
  --force_layout_block Text
```

Note which fallback was required in the README so the user understands any quality tradeoffs in the conversion.

Do not substitute alternative PDF extraction tools (e.g. pymupdf4llm, pdfplumber, pdfminer) for marker-pdf.
Marker's Surya OCR pipeline is the only open-source option here that extracts mathematical notation as LaTeX (`$...$` and `$$...$$`).
Alternatives output Unicode approximations or render equations as images, which destroys math fidelity for scholarly content.
If all three marker fallbacks fail, stop and report the issue to the user rather than switching tools.

## Phase 3: structure analysis and splitting

### Analyze heading structure

Inspect the monolithic markdown to identify section boundaries.

Using pandoc JSON AST (preferred when the markdown is well-formed):

```bash
pandoc <source>.md -t json | python3 -c "
import json, sys
doc = json.load(sys.stdin)
for i, block in enumerate(doc['blocks']):
    if block['t'] == 'Header':
        level = block['c'][0]
        inlines = block['c'][2]
        text = ''.join(
            i.get('c', '') if isinstance(i.get('c', ''), str) else ''
            for i in inlines
        )
        print(f'{i:4d} H{level}: {text}')
"
```

Fallback when pandoc cannot parse (common with marker output):

```bash
rg '^#{1,6} ' <source>.md --line-number
```

### Determine split strategy

- **Books**: split by chapter into `chapters/` directory, files named `NN-chapter-title.md`
- **Papers**: split by major section into `sections/` directory, files named `NN-section-title.md`
- **Front matter** (abstract, preface, acknowledgments): `00-front-matter.md`
- **Back matter** (references, appendices, index): last numbered file or separate `NN-back-matter.md`

### Generate and run the split script

Dynamically create `scripts/split-sections.py` (or `split-chapters.py`) tailored to the document.
The script should:

1. Read the monolithic markdown file
2. Split at heading boundaries identified by line number ranges from the analysis above
3. Normalize heading levels so the top-level section in each file is h1, subsections are h2, etc.
4. Use pandoc JSON AST for heading normalization when feasible (read markdown, manipulate AST, write back)
5. Write each section to its numbered file
6. Generate `00-index.md` with a table mapping filenames to brief descriptions

```bash
mkdir -p scripts
# (write the generated script to scripts/split-sections.py)
python3 scripts/split-sections.py
git add scripts/ chapters/ && git commit -m "feat: split into modular section files"
```

Use `chapters/` for books, `sections/` for papers.
Verify no empty files were produced and that all content from the source is accounted for.

## Phase 4: README and index

### Token counting

Count tokens per file using tiktoken with cl100k_base encoding:

```python
import tiktoken
enc = tiktoken.get_encoding("cl100k_base")
token_count = len(enc.encode(text))
```

If tiktoken is not available, use `ttok` from the command line:

```bash
cat <file>.md | ttok
```

### README.md structure

1. Document title as h1
2. Authors and formatted citation
3. Source information: DOI/arXiv link, conversion method (pandoc from LaTeX / marker from PDF)
4. Files table: filename, brief description, token count
5. Total token count across all section files
6. Contents: hierarchical outline showing major sections and key subsections from each file

### 00-index.md structure

Document title as h1, then a table mapping each numbered file to a one-line description.

```bash
git add README.md chapters/00-index.md && git commit -m "docs: add README and section index"
```

## Verification checklist

Before presenting results to the user, verify:

- All section files are properly numbered and named in lowercase kebab-case
- 00-index.md lists every file with a description
- README.md has accurate token counts and a contents outline
- No empty section files exist
- Heading levels are normalized within each file
- Mathematical notation is preserved (inline `$...$`, display `$$...$$`)
- Git history has atomic commits for each phase
- `.venv/` and `__pycache__/` are gitignored (if uv project was created)
- Original PDF(s) are preserved in `pdfs/`
- Git LFS is active (`git lfs ls-files` lists all binary files; `.gitattributes` contains filter/diff/merge entries)

Report the final `tree --du -ah` output and any quality issues to the user.

## Phase 5: publish and notify

After verification passes, send a completion notification and create the GitHub repository.

```bash
curl -k -d "doc-to-md: <repo-name> complete" https://ntfy.zt/$(hostname -s)
```

Create a private GitHub repository from the local repo.
Run this from within the repo directory so `-s .` resolves correctly:

```bash
cd ~/projects/<workspace>/<repo-name> && gh repo create cameronraysmith/<repo-name> --private --push -r github -s .
```

This command will be intercepted by a Claude Code hook requesting permission before execution.
The remote name `-r github` matches the convention used across existing doc-to-md repos.

## Phase 6: subtree aggregate integration

When `--aggregate` is provided, add the newly published repo to the subtree aggregate repository.
Skip this phase if no aggregate path was specified.

GitHub's server-side GH008 pre-receive hook rejects pushes containing LFS pointer references when the corresponding LFS objects are not yet in the target repo's LFS storage.
The steps below follow the required ordering: subtree add, then LFS object transfer, then push.

### Add subtree to aggregate

The LFS smudge filter must be skipped during subtree add to prevent pointer/blob mismatches in the working tree.

```bash
cd <aggregate-path>
export GIT_LFS_SKIP_SMUDGE=1
git remote add <repo-name> "https://github.com/cameronraysmith/<repo-name>.git" 2>/dev/null || true
git fetch <repo-name> main
git subtree add --prefix=<repo-name> <repo-name> main -m "subtree: add <repo-name>"
git checkout -- . 2>/dev/null || true
unset GIT_LFS_SKIP_SMUDGE
```

### Transfer LFS objects and push

Transfer LFS objects from the individual repo to the aggregate's GitHub LFS storage before pushing refs.

```bash
cd ~/projects/<workspace>/<repo-name>
git remote add aggregate "https://github.com/cameronraysmith/<aggregate-repo-name>.git" 2>/dev/null || true
git lfs push aggregate --all

cd <aggregate-path>
git push github main
```

Verify the aggregate is consistent after push:

```bash
cd <aggregate-path>
git lfs ls-files --include="<repo-name>/**" | wc -l
```
