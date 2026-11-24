---
description: vanixiets iets classic mode as `nix` — where it applies, what it evaluates and falls back on, when an agent must use `nix-stock`, and the off switches.
---

## `nix` as iets classic mode

On a host listed in `flake.lib.hosts.<name>.nixClassic` (`lib/hosts.nix`; stibnite only, as a trial), the host's primary user gets `flake.lib.nixClassic` as `nix`: iets' classic mode, on the user PATH and inside this repository's dev shell alike.
`nix-stock` beside it is always the real Nix, and only the `nix` name changes: `nix-build`, `nix-instantiate`, `nix-shell` and the rest stay the real Nix's own.
It is in effect when `command -v nix-stock` succeeds and `~/.config/nix-classic/enabled` exists; the dev shell carries the wrapper on every host but evaluates with Nix unless that marker exists and the caller is not root.
Root, every other user and every other host get stock Nix, and a shell or agent started before the host's activation keeps its old PATH until restarted.

`nix eval`, `nix build`, `nix develop` and `nix derivation show` evaluate in iets, which on stibnite on 2026-11-23 evaluated a cold host toplevel 5.8-7.6 times faster than stock at about the same peak memory, roughly 2.4 GiB per toplevel.
Anything classic does not implement, including `nix flake check`, `show`, `lock` and `metadata`, `nix run`, `nix shell`, `nix profile`, `--json`, `--apply`, `--dry-run`, `--profile`, `--override-input` and `--version`, prints `iets: falling back to nix: <reason>` and re-runs the real Nix with the same arguments and environment.
That line is not an error and its result is stock Nix's: do not retry the command or reshape it to avoid the fallback.
A call iets evaluates itself prints `setting 'accept-flake-config' is ignored`, which is also harmless, because this flake's `nixConfig` carries only substituters and keys.

Every entry point that produces what a host runs already evaluates with stock Nix internally: nh in the `.#darwin`, `.#os` and `.#home` apps behind `just activate*` and in the dev shell is `flake.lib.nhFleetNix`, which `checks.x86_64-linux.deploy-stock-nix` asserts; `darwin-rebuild`, `clan` and `nix-fast-build` (`just check-fast`) put their own Nix first; and the operator's publish script (`~/.local/share/vanixiets-publish/publish.sh`, outside this repository) calls `nix-stock`.
Do not add `nix-stock` to those recipes, and do not bypass them with a hand-rolled `nix build` of a configuration followed by activation, which would evaluate with iets what then runs on a host.

Use `nix-stock` yourself in three cases:

- When you produce anything a host, cluster, cloud account or release will consume outside the recipes above, such as a store path to copy to a machine, a rendered manifest, or a release artifact.
- When a result disagrees with CI or a path CI built is unexpectedly missing from the binary cache. A different drvPath misses the cache, so an unexpected local rebuild of something CI already built is a possible evaluator divergence: compare `nix eval --raw <attr>.drvPath` with `nix-stock eval --raw <attr>.drvPath` and report both paths rather than working around the rebuild.
- When you measure evaluation cost for comparison with earlier numbers, all of which were measured with stock Nix.

`rm ~/.config/nix-classic/enabled` turns classic off at once for every shell and agent of that user until the next home activation, and `IETS_NIX_FALLBACK=always` turns it off for one environment; removing the host from `nixClassic` turns it off for good.
Flipping either switch changes what every other agent on the host runs, so never do it silently: say in your report that you did it and why.
iets' tracing cache is off by default (`IETS_CACHE=1` turns it on for one run): a cache hit is only as right as iets' record of the files an evaluation read, and a gap in that record would return a stale result without any sign, while every uncached call is still a full evaluation at the speed above.
Do not set `IETS_CACHE` in a shell profile, recipe or environment file to make repeated calls faster.

`just eval-identity` also runs `apps/nix-classic-identity`, which evaluates every host system, every home activation package and the default dev shell with stock Nix and with classic and fails unless drvPaths and whole `.drv` closures agree; one run took about 13 minutes on stibnite on 2026-11-23.
Run it on every bump of the `iets` input before the trial continues, and treat a difference as a finding to report, as for the `nix-eval-jobs` oracle (§Evaluators).
