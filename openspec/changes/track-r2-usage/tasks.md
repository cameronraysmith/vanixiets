## 1. Poller, gate and regulators

- [x] 1.1 `modules/nixos/r2-usage.nix`: `flake.lib.r2Usage` (pricing, free tier, budget, billing anchor, classes, declared and external buckets, cost queries), `flake.lib.r2UsageObligations`, and `flake.modules.nixos.r2-usage` with its option (default off), its units, timers and `cloudflare-analytics` generator (D2-D6). Verify by evaluating magnetite extended with `vanixiets.r2Usage.enable = true`: the units render, no assertion fails, and the judge lists exactly the awaiting, vars and notifiedUnits problems.
- [x] 1.2 `modules/nixos/r2-usage/poller.py` and `checks.x86_64-linux.r2-usage`: the recorded response, the expected file, and the unitConfusion, classMapping and bucketDropped mutants (D9). Verify with `nix-fast-build --remote magnetite.zt` of `checks.x86_64-linux.r2-usage`.
- [x] 1.3 Add the series to `nodeExporterKeep`, and assert `r2UsageObligations` in `withFleetObligations`. Verify by building `nixos-magnetite` and `nixos-cinnabar`.

## 2. Alerts and dashboard

- [x] 2.1 Add the five rules to `rules.nix` and `r2PromtoolRehearsal` to `checks.x86_64-linux.fleet-alert`, each case with its mutants (D4, D7, D8). Verify by building `fleet-alert.passthru.r2PromtoolRehearsal`, then `fleet-alert`.
- [x] 2.2 Add `dashboard-r2-usage.json`. Verify by building `perses-lint`; `r2-usage` asserts the cost queries.

## 3. Operator steps

- [ ] 3.1 Mint the token. In the Cloudflare dashboard, open the **Account API tokens** page (`https://dash.cloudflare.com/?to=/:account/api-tokens`). Select **Create Token**, then **Custom token: Get started**. Under Permissions, choose **Account**, **Account Analytics**, **Read**, and add nothing else. Name it `vanixiets r2-usage (magnetite)` and create it. The account-token template link in `fundamentals/api/how-to/account-owned-token-template.mdx` preselects the same permission.
- [ ] 3.2 Check the token without storing it: `curl -s -H "Authorization: Bearer $T" -d '{"query":"{viewer{accounts(filter:{accountTag:\"1ece4a9a8f092f8cbdd679d22b9ecb1f\"}){r2StorageAdaptiveGroups(limit:1,filter:{datetime_geq:\"<yesterday>T00:00:00Z\"}){max{payloadSize}}}}}"}' https://api.cloudflare.com/client/v4/graphql`. The answer must have no `errors`.
- [ ] 3.3 In a throwaway clone at this change's commit, run `clan vars generate magnetite --generator cloudflare-analytics` and paste the token at the hidden prompt. In the same commit:
  - set `vanixiets.r2Usage.enable = true` on magnetite;
  - remove magnetite from `flake.lib.r2Usage.awaitingSecrets`;
  - add `r2-usage` to magnetite's `notifiedUnits` in `modules/lib/observability-hosts.nix`;
  - commit `vars/per-machine/magnetite/cloudflare-analytics/`.

  Verify with `nix-fast-build` of `nixos-magnetite`, which runs the obligation, then deploy.
- [ ] 3.4 After deploy, wait for the next :07 UTC poll and check:
  - `systemctl status r2-usage` exits 0;
  - `/run/node-exporter-textfile/r2-usage.prom` lists three buckets;
  - the store answers `vanixiets_r2_last_success_timestamp_seconds`;
  - the R2 usage dashboard renders one group per bucket.

  Compare the period's Class A and storage with the Cloudflare dashboard: open **R2 object storage**, select a bucket, then **Metrics** (`r2/platform/metrics-analytics.mdx`), and check the billing page.
- [ ] 3.5 terranix: nothing to import. The account holds exactly the three declared buckets. GreptimeDB and omnigraph live in `sciexp`, which is already declared and imported. When a bucket is made by hand later, either import it into `modules/terranix/cloudflare.nix` with an import block (id `<account>/<name>/default`) and `lifecycle.prevent_destroy = true`, then run `just terraform-plan` before any apply, or list it in `flake.lib.r2Usage.externalBuckets` with its owner.
