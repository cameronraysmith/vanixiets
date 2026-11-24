---
description: The @ working-copy pointer never moves; create with jj new --no-edit and land with jj squash --into, using -u and -k, or splice with jj new -B.
---

## Making changes in jj-managed or colocated repos

The working copy is the integrated surface of every active chain.
All of them are merged into it continuously, so two chains that stop being compatible conflict here, at the keyboard, on the day it happens rather than at integration time.
That is what the rule below protects, and every other rule follows from it, including for verbs not listed here.

The working copy pointer `@` never moves.
Relocating `@` onto a single chain dismantles the integration and strands any concurrent editor coordinating through the shared wip.
Create a change with `jj new --no-edit`, which leaves `@` in place, and land work with `jj squash --into <change> --use-destination-message --keep-emptied`.
Both squash flags are load-bearing: `-u` reuses the destination's description instead of opening the description-merge editor, which hangs a non-interactive session, and `-k` preserves the source, because without `-i` or path arguments a squash always exhausts `@`, and an exhausted source is abandoned and recreated with a new change id and no description.
Path-scoped squash is not exempt when the paths exhaust the source.

Because edits land in the integrated surface unattributed, accumulated change is routed down to the chain it belongs to rather than committed in place: path-scoped `jj squash` for what you can name, `jj absorb` for what blame can route, `jj split` for a change spanning boundaries.
Splice into a chain with `jj new --no-edit -B <tip>`; descendants rebase automatically and a downstream merge keeps every edge, so the join stays intact without being touched.

Other top-level sessions may share this working copy and its join, each owning chains you did not create.
Change the join's parents only with a destination derived from its current parents and the trunk, `jj rebase -s <join> -d 'heads((parents(<join>) ~ ::trunk()) | trunk() | <new-chain>)'`, never an explicit parent list, which silently drops the chains you did not name; `| trunk()` keeps what has landed in the join when every remaining chain is based on an older trunk, and `heads()` drops it again when another parent already contains it.
Add a new chain to the join immediately after creating it, before any edit, since a squash into a chain outside the join removes those paths from the working copy; and when a landing moves the trunk, rebase your own remaining chains onto it and rebuild the join the same way before reporting the landing.
The rest of the protocol, which a harness with inter-session messaging carries over that channel, is the `jj-version-control` skill §"Coordinating concurrent sessions on one join".

Read-only inspection takes the global `--ignore-working-copy` so it does not snapshot and race a concurrent session.
Recovery for the destructive class is top-level `jj undo`; there is no `jj op undo`.
See the `jj-version-control` skill for the diamond workflow.
