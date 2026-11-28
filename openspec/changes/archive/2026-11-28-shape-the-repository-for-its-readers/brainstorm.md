<!--
Raw capture of the brainstorming decision log.
-->

# Brainstorm: shape the repository for its readers

## Background

The repository has moved toward the principles of den (github.com/denful/den) and gen (github.com/sini/gen) without adopting either. It has typed registries for hosts (`flake.fleet.hosts`, `modules/lib/hosts.nix`), for the accounts people hold on hosts (`flake.fleet.hosts.<host>.users.<account>`, `modules/lib/host-users.nix`), for omnigent workers (`flake.fleet.workers`, `modules/lib/fleet-workers.nix`) and for cloud machines (`modules/lib/cloud-machines.nix`). It has an obligations register (`fleetObligations`), provider and workstation aspects (`hetzner-cloud`, `gcp-cloud`, `darwin-workstation`), a secrets seam (`vanixiets.secrets`, `modules/system/secrets.nix`), and, in the working copy only, NixOS `base` as an explicit list of named parts (`modules/nixos/base.nix`, the first pull request of `name-the-parts-of-base-and-ai`).

What it has not done is choose its shape on purpose. Its aspects are registered class-first (`flake.modules.<class>.<name>`); its top-level directories follow five principles (by class, cross-class, by aggregate, by host, by external system; `modules/README.md` lists them); `darwin.base`, `ai` and the home aggregates are implicit unions; list order depends on import depth (A344); and no one had measured what a later reader asks.

Terms used below:
- A **named module** is one attribute of `flake.modules.<class>`, the unit a host, home or test imports.
- A **route** is the mechanism by which a named module reaches a host's configuration: the host module's import list, a list such as `base`, another module's `imports`, a clan service's machine or role modules, or a host-registry fact that switches a guarded module on.
- A host's **composition** is the set of named modules its configuration takes, each with its route.
- A **host literal** is a place, outside the host registry, where a host's name or one of its facts is written by hand.
- A **lookup question** asks where something is or what decides it; a **placement question** asks where something new goes; an **enumeration question** asks for everything of a kind that one host or the fleet has; an **impact question** asks what changes if one file changes.

## The evidence

Seven research reports were read whole (den's model, gen's model including its TRUST.md, VALIDATION.md and docs at revision 857e01c, sini/nix-config at fa6a020, this repository's feature-by-class matrix, the order-sensitivity inventory, the classification of `base` and `ai`, and the twenty reader questions), together with the coverage audit of the den-readiness observations, `docs/notes/development/architectural-principles.md` and `modules/README.md`.

Two measurements were then taken on main `1e8fb9ff6d66`, each by fresh read-only agents with only read and search tools.

**Lookup set** (the twenty questions, one agent each): every question answered, high or medium confidence; files opened median 2, maximum 4; searches median 2, maximum 8. Graded against the answer keys in the reader-questions report, all twenty answers are right. Question 1's key is wrong where it calls `nixos/omnigent.nix` a trap: the omnigent clan service imports `nixos.omnigent` into every machine of its instance (`modules/clan/services/omnigent/flake-module.nix:20-23`), its server role, placed on magnetite (`modules/clan/inventory/services/omnigent.nix:62`), sets `services.omnigent.enable` (`flake-module.nix:44-47`), and that turns on PostgreSQL (`modules/nixos/omnigent.nix:61-70`). The agent's answer, which names it, is the right one; the key holds only for magnetite's host file. Five answers were misled once: a stale documentation sentence (Q6, `fleet-observability.md:607`), a comment giving an overlay order no code enforces (Q18, `nixpkgs/compose.nix:39`), a host file naming the primary user but not the uid (Q19), a search returning archived plans (Q17), and cinnabar's `matrix-server` looking like a second PostgreSQL host (Q1).

So lookups are already cheap. The typed registries and a text search answer them whatever the tree's shape, and a new shape cannot be justified by them; it must only not make them worse.

**Hard set** (ten tasks, three agents each; `hard-tasks.json`). First reading, to be confirmed by the graded summary:
- Placement of a fleet-wide setting, a workstation application and a secret, and the dnscrypt-proxy enumeration, came out the same across the three agents, each finding the convention stated in a file header or the README (7-21 files read, 4-18 searches).
- Placement of a new check diverged: two agents wrote a standalone check as `modules/checks/sshd-no-keyboard-interactive.nix` does, one a fleet obligation as the checks skill's placement ladder says (`preferences-nix-checks-architecture`, "a fact about configuration values belongs in a module `assertions` entry, or in an existing fleet obligation"). Two documented conventions disagree.
- Adding a NixOS server was consistent but expensive: every run listed fourteen to sixteen files to edit (registry, cloud table, host-users, inventory tags, host module and disko, observability row, zt-dns names, ssh logins, the flake-shape pin, machine check sizes, `.sops.yaml`, sops correspondence anchors, bridge re-encryption, README enumerations) after reading 27 files, and each noted that no single guide lists them.
- Enumerating what ends up in magnetite took 26-33 files and found about 79 named modules arriving by five routes. The argentum-versus-blackphos difference is almost all registry-derived (enrolled, memory, observability row, exclusion lists), not import-derived.
- Removing ZeroTier touches about sixty files: the overlay network has no seam. `rg -l 'zerotier|\.zt\b' modules` lists 73 files today.

The evidence points away from "the tree's layout is hard to navigate" and toward three costs: a host is named in many separate literals; a host's composition arrives by five routes with no rendered view; one external system (the overlay network's names and addresses) is read everywhere. A fourth, smaller one: two check conventions disagree.

## Q1: What is the acceptance instrument?

Both sets, used differently. The lookup set is a no-regression bound: a change of shape must keep every answer right and not raise files opened or searches above today's medians and maxima, and should remove the three misleads that are repository defects (Q6, Q18, Q19). The hard set is what the shape must improve: agreement of three independent agents on each placement task, and completeness against a key, with files read, for enumeration and impact.

If the hard set had also come out good on today's tree, the case for restructuring would rest only on the principles (P1-P5) and would have to be weighed as such. It did not, but only in the four places named above, and the recommendation is bounded by that.

## Q2: Which candidate shapes?

Three were walked against the twenty questions and the ten tasks:

(i) **Narrow**: keep the class-first tree; add one declaration per host from which the host literals are derived or checked, a rendered per-host composition view, one stated check convention, the one-time order change, and finish the parts lists. The overlay-network seam is already the registry step of `migrate-mesh-to-tincr`.

(ii) **Feature-first re-layout** under plain flake-parts: one directory per concern holding all its class halves (`modules/<area>/<concern>/`), dendritic style. Moves about four hundred files.

(iii) **Entity-and-role-first**, as sini/nix-config does it without den: `fleet/` for entities and relations, one file per host holding its facts and its import list, `roles/` of pure import lists, `policy/` for what every machine gets (dissolving `base`), `features/<area>/<concern>`, `glue/`, checks beside their concern.

Walking the hard tasks:
- Host literals (placement task PL2): (ii) does not touch them: the literals are in the registry, clan inventory, the cloud table, observability rows, pins and docs, wherever those files sit. (iii) moves the registry record into the host file but still needs every other literal derived; the derivation is the work, the move is optional. (i) does the derivation.
- Composition (E1, E2): (ii) leaves the five routes as they are. (iii) reduces them (tags derived from roles, `base` gone) but still needs a rendered view, because the clan service route and registry-switched modules remain. (i) renders the view. E2's difference is registry-derived, so only a view that shows registry facts beside imports answers it.
- Overlay network (I2): no layout moves it; only a seam does, which `migrate-mesh-to-tincr` plans ("a registry of transport-neutral names makes this the last time a transport change touches every consumer").
- Check placement (placement task PL5): a stated convention moves it in every candidate; (iii)'s "checks beside their concern" adds a third convention unless the other two are retired.
- Lookups: (ii) and (iii) move the files today's lookups find in one or two reads (`lib/hosts.nix`, `lib/host-users.nix`, `nixos/base.nix`, `modules/README.md`); a renamed tree risks regressions in the bound for the time agents and docs catch up.

Decision: (i), with the parts lists kept class-first and their names as `name-the-parts-of-base-and-ai` chose them.

## Q3: Does `base` dissolve into fleet-wide settings plus roles?

Not now. The classification report puts NixOS `base` at 15 fleet-wide, 7 role-like, 4 feature, 3 judge and 4 glue parts, and darwin's at 12, 14, 3, 3 and 5. Placement of a fleet-wide setting already agrees across agents, and no hard task failed because of `base`. The parts that fit `base` least are correctness questions, not reader costs: `base-initrd-networking` reaches pyrite, which turns it off with `mkForce false` (`machines/nixos/pyrite/default.nix:214-227`) but still receives its virtio initrd modules and its initrd host-key secret; `r2-usage` and `postgresql-backup` are off by default on hosts that do not use them; homebrew and the nine `system-defaults` files go to every Mac, all four of which are workstations. Changing any of these changes what a machine does, which is outside this change's latitude; they are owner questions. The split is recorded as the larger shape's first step, with its mapping, to be taken if the re-measure or the owner asks for it.

## Q4: Where does each host literal go?

Into the host's registry record, and every other site is derived from it or checked against it. Fields the registry lacks today: inventory tags and description (`modules/clan/inventory/machines.nix`), the cloud provisioning row (`modules/lib/cloud-machines.nix`), the observability row (`modules/lib/observability-hosts.nix`), mesh names served by zt-dns, ssh login lists, machine check size classes. Two literals stay literals on purpose and gain checks: the fleet pin (`checks/structure/flake-shape.nix`), which exists to falsify the registry's derivations (P4) and gains a phantom entry (O12); and `.sops.yaml`, which the sops tool reads outside evaluation, so a check compares it with the registry instead. Steps no declaration can derive (machine key material, re-encrypting shared secrets, bridge keys) are listed once in the host-onboarding guide, and a check names any host missing one.

Whether the record moves into each host's directory (as sini/nix-config, a den repository, does: one file per host holding its entity and its composition) is the owner's call; recommended no, because the central registry is where lookups land today in one read, and the derivation is what removes the literals.

## Q5: How is a composition rendered as data that a check keeps true?

Two halves:
- **Static closure**: every list that composes a host (the host module's imports, `base`, `darwin-workstation`, the clan services' machine and role modules, module-to-module includes) is written as names and mapped to modules by one helper; the closure over those names, with the route of each, is plain data (`flake.lib.composition.<host>`), rendered into a committed file in the host's directory and pinned by a small check. Writing `map byName [ ... ]` instead of `with flakeModules; [ ... ]` puts the same modules at the same depth, so no derivation changes.
- **Truth**: in an evaluated host configuration, every definition made through `flake.modules` carries the file `"<file>, via option flake.modules.<class>.<name>"` (nixpkgs `lib/types.nix`, the deferred-module merge; A375, A383). Collecting those names from the host's options gives the named modules actually present; a check fails when that set differs from the static closure. It evaluates the host's options, so its cost is measured before its size class is chosen.

den answers "what does host X consist of" with `host.aspects` and den-diagram; this is the plain-module-system equivalent, without diagrams.

## Q6: Order

The one-time order change is still worth taking, for a reason specific to this plan: `name-the-parts-of-base-and-ai`'s darwin and `ai` pull requests reorder `environment.systemPackages` and `home.packages` and need a fleet deploy anyway. Sorting those two lists once (`apply = lib.sort` on a re-declared option, one module per class and one shared home module) makes both pull requests derivation-identical, makes every later move or rename change no package profile, and costs the same single deploy. The `gh-dash` review bindings become keyed; the overlay order becomes one explicit list (L5 of the audit; it also removes Q18's misleading comment). Lists that are ordered on purpose (darwin activation, launchd activation, tmux plugins, shell init) keep their pinned order, and the README names where each order is written.

## Q7: What happens to `name-the-parts-of-base-and-ai`?

Its first pull request (NixOS `base`) proceeds as written. Its darwin and `ai` pull requests resume after the order step, with the names it already chose (`base-<concern>`, `ai-<harness>`); under the order step both become derivation-identical, so their allow-lists shrink to the structure check, and its own deploy plan folds into this change's single deploy.

## Q8: The audit items left unplanned

- O03, O11, O17, O22, the O04 constructor and the four O09 sites are the same cost for people that host literals are for hosts: an account named in several literals. They form one derivation-identical step.
- O12: every check added here carries a negative control; the fleet pin gains a phantom entry.
- L5 (overlay order) joins the order step.
- O46's residue (test data read from magnetite) is a P5 read across entities, not a shape question; it stays out.

## Q9: What the graded hard set changed

The graded summary (`baseline-hard.md`) confirmed the first reading and added these points:
- All three I1 runs said 26 standalone homes; the pin in `checks/structure/flake-shape.nix:47-70` has 20. The systems a home is built for follow the locked `systems` input and are readable only from that pin. Decision: each standalone home's composition view lists its systems.
- A new host appears in 8 hand-maintained lists a check or evaluation enforces (`hosts.nix`, `cloud-machines.nix`, `inventory/machines.nix`, `host-users.nix`, the `structure-fleet` pin, the machine `testSizes`, `machineAnchors`, `.sops.yaml`) and 4 kept by convention only (observability row, `ztRecords`, ssh `logins`, the justfile's `nixos_hosts`); all three runs missed the `sops/secrets/<host>-age.key/groups/fleet-deployers` link a new enabled host needs (`fleet-deployer.nix:5-9`, `sops-correspondence.nix:203-206`). Decision: derive six of the twelve, leave none by convention, and list the generated steps in one guide section with the check that fails for each.
- Hand-entered secrets diverged between two prompt shapes, with an older `exit 1` shape also present. Decision: one stated shape (prompt, `deploy = false`, rendered file), the six existing uses as its examples; the five old ones move only when their services next change.
- The check divergence has a cause beyond the two documents: fleet obligations run only in the machine checks, which skip `checked = false` hosts (scheelite), so the standalone precedent is the only form that covers "every NixOS host". Decision: the ladder gains that one exception, and `sshd-no-keyboard-interactive.nix` becomes its stated example rather than a violation.
- ZeroTier removal touches 91 files under `modules/`. The overlay seam stays with `migrate-mesh-to-tincr`.

None of these is a layout cost; each is moved by derivation, a view or a stated rule. The recommendation stands and narrows: a full feature-first re-layout would move none of them.

## Q10: What a review of the plan changed

Each point was checked against the code before the text changed.
- Routes cannot be judged by presence alone. The module system records each evaluation's import tree as `graph` (`key`, `file`, `imports`, `disabled` per node; nixpkgs `lib/modules.nix:410,616-645`), and the NixOS, nix-darwin and standalone home-manager wrappers keep it; integrated homes do not expose one. Decision: read routes from `graph`; judge unknown route kinds with a fleet obligation in the machine checks (`system/mesh-hosts.nix:33-36` is the precedent for an obligation replacing a standalone every-host check); drop the `modulesNamed` rewrite, which would have been a second way to write a name list.
- Deriving `ztRecords` would reorder it, and its order feeds every peer's hosts file (`system/mesh-hosts.nix:46`) and cinnabar's dnsmasq; `migrate-mesh-to-tincr` deletes it anyway. `nixos/hm-sops-bridge.nix:185-186` assigns into `darwin.base`, so moving the file before `darwin.base` is a list would reorder it. Decision: leave `ztRecords`; move the darwin halves after the parts step.
- electrum, galena and scheelite are `enabled = false`, and blackphos has no machine. Decision: deploy the six enabled hosts; record the others.
- Derivations that would make a check compare a value with itself: the `machineSystems`-versus-inventory assert is deleted once the inventory is derived; `testSizes` stays hand-written; phantom entries follow `checks/validation.nix:105-120`, where the expected value is the one a correct comparison gives. Each host list now gets one of three treatments.
- `observabilityHostsFor` takes a parameter (`checks/omnigraph-retired-roots.nix:45`) and the cloud table carries location, image, GPU and comment fields. Decision: both tables stay and gain key checks.
- The evidence was over-read: three runs per task, one model, evaluation forbidden, self-reported lookup counts, one grader. Decision: state the limits where the numbers are quoted; targets are per-run passes; a commands arm measures what evaluation answers.
- Sorting the system path is behavioural where equal-priority packages provide differing files (`ignoreCollisions`). Decision: a priority step first, measured on every enabled host, then the sort; content, not link targets, is compared. home-manager's path refuses differing files, so its order is behaviourally immaterial, but it still decides the derivation, so `home.packages` is still sorted, for derivation stability. `users.knownUsers` is no longer touched.
- A committed composition file would make every module-adding change regenerate up to 30 files. Decision: print it on request.
- The column of registry facts that switch guarded modules has no source. Decision: dropped.

## Agreed approach

Option (i), stacked as: the measure kit and misleading texts; host lists derived or checked; the composition command and route judge; placement rules; priority, then order; the resumed parts lists, then the darwin-half moves; people's literals; one deploy of the enabled hosts; the re-measure, which decides whether any of the larger shape is taken. Planned only; implementation waits for approval.
