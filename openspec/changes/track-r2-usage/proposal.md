## Why

We pay for R2, and nothing tracks what we use. The operator's dashboard for the billing period Oct 23 to Nov 23 2026 shows 257.39 GB stored, 1.22M Class A and 1.58M Class B operations, and $7.76 billable: $3.26 for storage and $4.50 for Class A. Class A went past the 1M free tier by 0.22M and was billed a whole million, because R2 rounds usage up to the next billing unit (`r2/pricing.mdx`, "Billable unit rounding"). The free-tier edge is therefore a $4.50 step that nobody saw coming. F87 found buckets in the account that terranix did not declare (one, `omicsberg`, has since been deleted), and F74 found multipart uploads that are never cleaned up. Neither has a regulator.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`. The operator approved the scope as Q79 on 2026-11-20.

- **Usage in the fleet store (D1-D3, D5).** A poller on magnetite queries Cloudflare's GraphQL Analytics API every hour for every bucket in the account. It writes each bucket's size, metadata size, object count and pending multipart uploads, plus its operations since the billing period began, by pricing class. The data goes to node_exporter's textfile directory, which the collector already ships to GreptimeDB. It authenticates with a new clan vars generator, `cloudflare-analytics`, which holds an Account Analytics Read token and is loaded only by the poller.
- **Off until the token exists (D6).** `vanixiets.r2Usage.enable` defaults to false, and magnetite is listed in `flake.lib.r2Usage.awaitingSecrets`, following back-up-postgresql-off-host D16. A fleet obligation pins both.
- **Alerts (D4, D7, D8).** Five rules:
  - `R2MultipartUploadPending`: an upload pending for over 24 h (F74).
  - `R2CostProjected` (info): Class A or Class B projected past its free tier, or storage past a 300 GB-month budget.
  - `R2BucketGrowthAnomalous`: a bucket's 7-day growth far above its 30-day rate.
  - `R2BucketUndeclared`: a bucket that terranix does not declare, or a listed external bucket that holds data (F87).
  - `R2UsageStale`: no successful poll for 2 h.
- **Dashboard (D4).** A new Perses dashboard, `r2-usage`, shows the billing period's estimated cost and one repeated panel group per bucket.
- **Regulators (D9).** `checks.x86_64-linux.r2-usage` runs the poller against a recorded GraphQL response, plus three mutants, the obligation judge, and the dashboard's cost queries. `fleet-alert`'s new `r2PromtoolRehearsal` runs one promtool case per rule, each with its mutants.

## Capabilities

### New Capabilities
- `r2-usage-interface` (stratum: `interface`): the poller units and their textfile series, the `cloudflare-analytics` generator, the enable option and the awaiting-secrets list, the five rules, the dashboard, and the checks that pin them.
  Trust boundary:
  - What this machine guarantees: it declares the units, rules and dashboard, and it judges the evaluated configuration, the poller's formatting of a recorded response, and the rules' PromQL semantics.
  - What it does not guarantee:
    - that Cloudflare's analytics match the bill. The GraphQL API documents itself as not a billing measure (`analytics/graphql-api/index.mdx`).
    - that the live schema keeps the shape the fixture records. The query was validated against it on 2026-11-20.
    - that the operator mints the token.
  - Runtime evidence for the poller is `R2UsageStale`.

No behavioral capability is claimed. The cost and growth thresholds are operator decisions recorded in `design.md`, not requirements on the world.

## Impact

- Code:
  - new `modules/nixos/r2-usage.nix`, `modules/nixos/r2-usage/poller.py`, `modules/checks/r2-usage.nix` with `modules/checks/r2-usage/{response.json,expected.prom}`, and `modules/nixos/perses/resources/dashboard-r2-usage.json`;
  - `modules/nixos/fleet-alert/rules.nix`, `modules/checks/fleet-alert.nix`, `modules/checks/machines.nix` and `modules/clan/services/otel-collector/schema.nix`.
- Hosts: magnetite only, once the operator turns the poller on.
- Steps the operator does by hand: listed in `tasks.md` section 3.
- Spending: none on R2. GraphQL Analytics API requests are not R2 operations, and the poller sends 24 a day against a quota of 300 per 5 minutes (D5).
