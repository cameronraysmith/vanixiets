---
name: doc-to-md-cmd
description: >-
  Session-priming skill for batch construction of /doc-to-md invocations.
  Invoke once at session start, then provide citation and PDF path pairs
  repeatedly to get formatted commands copied to clipboard.
---

# doc-to-md-cmd

Format `/doc-to-md` skill invocations from citation and PDF path inputs, copying each to the system clipboard.

## Behavior

This skill primes the session for batch command construction.
After invocation, confirm readiness and wait for inputs.
The user will provide repeated inputs consisting of a citation string and one or more PDF file paths.
For each input, construct a properly formatted `/doc-to-md` invocation and copy it to the system clipboard.
Confirm each clipboard copy with "On your clipboard." and wait for the next input.

## Defaults

The workspace defaults to `modeling-workspace` unless the user specifies otherwise.
The aggregate defaults to `~/projects/modeling-workspace/modeling-references` unless the user specifies otherwise.
Either override persists for the remainder of the session once changed.

## Command construction

The output is a single-line string with this structure:

```
/doc-to-md <citation> --pdf '<path1>' ['<path2>' ...] --workspace <workspace> --aggregate <aggregate-path>
```

Wrap each PDF path in single quotes to handle spaces.
Place `--pdf` before the path list, `--workspace` next, and `--aggregate` at the end.
Strip trailing arXiv references (e.g., `arXiv:2404.12484`, `arXiv:https://arxiv.org/abs/...`) from citations when a DOI is already present, since `/doc-to-md` resolves arXiv sources via DOI.
Preserve the citation string exactly as provided otherwise.

If the user provides PDF paths without quotes, add single quotes in the output.
If the user provides PDF paths already quoted, preserve them as single-quoted in the output.

## Clipboard

Copy via Bash:

```bash
echo "<constructed-command>" | cb copy
```

## Example

User provides:

```
Cao Z, Grima R. Analytical distributions for detailed models of
stochastic gene expression in eukaryotic cells. Proc Natl Acad Sci
U S A. 2020;117: 4682-4692. doi:10.1073/pnas.1910888117

'/Users/crs58/.../Cao and Grima 2020 - Analytical distributions.pdf'
'/Users/crs58/.../Cao and Grima 2020 - supplement.pdf'
```

Clipboard output:

```
/doc-to-md Cao Z, Grima R. Analytical distributions for detailed models of stochastic gene expression in eukaryotic cells. Proc Natl Acad Sci U S A. 2020;117: 4682-4692. doi:10.1073/pnas.1910888117 --pdf '/Users/crs58/.../Cao and Grima 2020 - Analytical distributions.pdf' '/Users/crs58/.../Cao and Grima 2020 - supplement.pdf' --workspace modeling-workspace --aggregate ~/projects/modeling-workspace/modeling-references
```
