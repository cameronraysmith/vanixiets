---
name: web-to-markdown
description: Convert a URL to clean markdown by downloading the rendered HTML and extracting main content. Use when the user provides a URL and wants it saved as markdown, or asks to download/capture/convert a webpage.
argument-hint: <url> [output-path]
disable-model-invocation: true
---

# Web to markdown

Convert a URL to clean, readable markdown using globally installed CLI tools.

## Decision tree

Determine the page type and follow the appropriate path.

### Static or server-rendered pages

Trafilatura can fetch and extract directly:

```bash
trafilatura -u "<URL>" --markdown --formatting --links > "<output>.md"
```

### JS-rendered pages (SPAs, Angular, React)

Use shot-scraper to capture the rendered DOM first, then extract with trafilatura:

```bash
shot-scraper html "<URL>" > /tmp/web-to-md-source.html
trafilatura --markdown --formatting --links < /tmp/web-to-md-source.html > "<output>.md"
rm /tmp/web-to-md-source.html
```

### Authenticated or login-gated pages

Neither tool can bypass authentication.
Instruct the user to save the page from their browser using "Web Page, complete" and provide the HTML file path, then extract:

```bash
trafilatura --markdown --formatting --links < "<saved-file>.html" > "<output>.md"
```

## Output path conventions

If the user provides `$ARGUMENTS[1]`, use it as the output path.
Otherwise, derive a kebab-case filename from the page title or URL slug and write to the current working directory.

## Trafilatura flags

These flags are recommended for high-fidelity markdown output:

- `--markdown` selects markdown output format
- `--formatting` preserves bold, italic, and other inline formatting
- `--links` preserves hyperlinks in the output
- `--images` includes image references (add when the user wants images)
- `--precision` prioritizes clean extraction over completeness (use when output is noisy)
- `--recall` prioritizes completeness over cleanliness (use when content is missing)

## Verification

After conversion, briefly review the markdown output for:

- Presence of the main content (title, body sections)
- Absence of excessive boilerplate (nav, footers, cookie banners)
- Reasonable formatting (headers, lists, emphasis preserved)

Report any significant content loss or quality issues to the user.
