# Delivery plan

This change is a program, so delivery is one pull request per slice rather than one for the whole change.
Each slice is authored on the shared jj development join, routes only its own paths into its delivery change, and lands through the merge queue on its own.
Each later sub-project (groups 10 to 14 in tasks.md) opens by recording its decision in design.md and adding its micro-steps here before implementation starts.

## Order

1. Phase 0 (group 1) runs first and produces no code: the inventory with declaration statuses, the baseline count, the job catalogue and the discovery records.
   Its files go in a location the operator chooses; this change does not create them.
2. S1 (group 2) is delivered by its own owner; this plan only records its merge.
3. S2 (groups 3 and 4): the spike is answered and D6 is DECIDED; pyrite's Bitwarden agent, polkit touch unlock and per-host pins were deployed from branch `pyrite-bitwarden-yubikey`; the remaining commits are the backup YubiKey enrollment, stibnite's per-host pins, `refactor(ssh): one ssh-identity module for both laptops`, and its checks; `feat(rbw): declare rbw with a graphical pinentry` ships independently.
4. S3 (groups 5 and 6): `feat(niri): generate chord binds from one chord table`, then the half-window chords after the operator chooses O1 or O2, then the keyboard modifier and Caps Lock settings after Q4 and Q5 are decided.
5. Shared-layer fixes (group 7), one commit each: CA trust on pyrite, Zed on Linux, fonts in Nix, darwin-only command gating.
6. Declarative Zen (group 8), then desktop behaviour (group 9), then the sub-projects in group order.

## Steps per slice

1. Establish RED where a check can express the property: evaluate the focused assertion against the current base and confirm it fails.
2. Make the change in the owned files only.
3. Evaluate both laptops' affected attributes with `nix eval --no-update-lock-file --no-write-lock-file`; aarch64-darwin attributes are evaluated only and never built locally.
4. Build x86_64-linux outputs on magnetite with `--eval-store auto --store ssh-ng://magnetite.zt`; pyrite is never used as a builder.
5. For checks with mutants, confirm each mutant fails.
6. Run `openspec validate workstation-parity --strict` and tick the slice's tasks with their evidence.
7. Recount stibnite's declared share (task 15.1) and record it in the pull request description.

Long commands write complete output to `logs/workstation-parity-<step>-$(date +%Y%m%d-%H%M%S).log` through `tee`.

## Deploy and acceptance

Activation is a separate operator act for every slice.
For S2, only pyrite and stibnite deploy, since no authorized key changes.
Physical acceptance (unlock prompts, logins, chords, key feel, browser fill, screenshots) is recorded by the operator and has no evaluation-only equivalent.
