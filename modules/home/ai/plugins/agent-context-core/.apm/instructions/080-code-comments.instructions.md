---
description: Write a new code comment only for a constraint its next editor needs, keep history, evidence, ids and dates out of it, and delete existing comments with care.
---

## Code comments

A comment's reader is whoever next edits the lines beneath it, holding the repository and nothing else.
Write a new comment only for what that editor must know to change those lines safely and cannot see in them: a constraint, an invariant another file depends on, an external quirk with its link; state it in the present tense, about the code as it stands.
If our own code needs a comment to explain surprising behaviour, change the code instead: a name, a type, an extraction.
Beyond that, only licence headers, shebangs, pragmas and directives, public documentation comments and generated-code markers belong in comments.
Never write how the code came to be, what was tried or measured, who decided, which change, design item, task, finding or review asked for it, dates or `logs/` paths: history and evidence go in the commit message, reasoning in the design file or ADR, behaviour in the option's description or documentation comment.
This holds for docstrings, documentation comments and comments in scripts embedded in Nix strings.
A check fails a commit whose added comments carry such ids, dates, measurements, `logs/` paths, history or section banners; on a jj change, which runs no git hooks, run `just comment-gate <rev>`.

Writing a comment is strict; deleting one is careful: remove noise comments from our own code on sight, never touch vendored, generated or upstream-mirrored trees, and keep an existing comment you are unsure of and ask.
`preferences-style-and-conventions` §"Code comments" has examples and the full load-bearing list; `preferences-comment-cleanup` runs removals.
