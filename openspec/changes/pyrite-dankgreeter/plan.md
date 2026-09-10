# Pyrite DankGreeter implementation plan

Goal: prepare and build C without activation.
Architecture: configure the native nixpkgs greeter/PAM modules and generate typed niri configuration through the existing configuration-only input.
Tech stack: NixOS, home-manager configuration evaluation, native niri/DMS/Quickshell and greetd.

The operator's direct-worker/shared-jj instructions replace the schema's nested-worker/worktree execution instructions.
`tasks.md` is the completion checklist; physical tasks remain unchecked.
The user-approved scope amendment disables empty passwords in shared login PAM, including console login; it is the sole console-authentication preservation exception.

## Delivery and verification

One signed conventional delivery commit, `feat(pyrite): replace GDM with native DankGreeter`, follows `pyrite-dms-prepared`.
Only the machine/check files and this directory are routed into it.
Establish RED, implement, evaluate assertions and preserved interfaces, and run negative/static checks before independent source review.
The initial private build is historical evidence for its exact revision, not for later metadata or repairs.
The parent owns an external final-build evidence lane: freeze the reviewed final B/C revisions, build those exact revisions, and retain receipts in ignored logs without another documentation-only commit.

## Review repair

Verify F1–F3 against pinned sources and merged C before editing.
Enable native greeter PAM session registration, disable only the unused native synchronization hook, and require the actual native deny module in the PAM guard.
Extend the nine negative controls with disabled greeter session registration, restored native sync hook and substituted permit module.
Retain the 18 B preservation groups and separately compare repaired C against pre-review C, allowing only the greeter session rule and sync-hook changes.
Record local RED/GREEN and static evidence in `verify.md`; no remote operations are authorized for this repair worker.
