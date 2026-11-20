## Context

R2 holds four kinds of data:
- the nix cache, `sciexp-nix-cache`, written by niks3;
- the PostgreSQL backups, `sciexp-postgresql-backup`;
- browser evidence under `sciexp`;
- GreptimeDB's SSTs and omnigraph's clusters, both in `sciexp`.

Cloudflare's analytics are per bucket, and the bill is per account and per billing period. The fleet store already receives textfile series from magnetite through node_exporter and the collector.

## Decisions

### D1: Source: the GraphQL Analytics API, every bucket in the account
- **Choice**: Make one request per run. It covers `r2StorageAdaptiveGroups` over the last day, by `bucketName` and `datetime`, of which each bucket's latest sample is kept. It also covers `r2OperationsAdaptiveGroups` from the start of the billing period, by `bucketName` and `actionType`. No bucket list is configured, so a bucket nobody declared still appears; D8 depends on that.
- **Rationale**:
  - The dashboard's own metrics come from this API (`r2/platform/metrics-analytics.mdx`).
  - It needs one read-only permission.
  - A range of up to 31 days per query covers a billing period.
- **Evidence**: On 2026-11-20 the query was sent with the existing terraform token. The API rejected the token as `not authorized for that account` at the `storage` path, after validating the query. The same request with a misspelt field was rejected as `unknown field`. So the shape is valid against the live schema, and the terraform token cannot read analytics.

### D2: Path: a textfile writer, not a receiver
- **Choice**: `r2-usage.service` writes a record under `/var/lib/r2-usage`, and `r2-usage-publish.service` copies it into the host's one textfile directory every minute. The series names join `nodeExporterKeep`. The writer registers in `vanixiets.nodeExporter.textfileWriters`. magnetite's row in `observabilityHosts` already says `textfile = true`, so nothing changes there.
- **Rationale**: This path has the fewest new parts. It needs no new receiver, exporter or pipeline. The sqlquery receiver does not fit: it runs SQL against a database, and this source is an HTTPS GraphQL endpoint. An OTLP push would need a client library and a second credential path into the collector.
- **Boundary**: source-versus-delivered. node_exporter, the keep-list and the collector are unchanged code paths, and an assertion ties the poller to the keep-list and the directory flag.

### D3: The billing period, not the calendar month
- **Choice**: Operations count from 00:00 UTC on day 23 (`billingAnchorDay`), clamped to the month's last day, until the same time a month later. Both bounds are exported as series.
- **Rationale**: The free tier and the rounding apply per billing period, and the operator's dashboard shows Oct 23 to Nov 23. Counting from a calendar month would cross the free-tier edge on a different day than the bill does. That the period starts at 00:00 UTC is an assumption; if the anchor moves, change the constant.

### D4: Prices, projection and the cost edge
- **Choice**: `flake.lib.r2Usage.pricing` and `freeTier` hold the values from `r2/pricing.mdx`:
  - storage: $0.015 per GB-month, 10 GB-month free;
  - Class A: $4.50 per million, 1M free;
  - Class B: $0.36 per million, 10M free.

  The dashboard's cost panel rounds each class up to whole millions past the free tier, and storage up to whole GB-months, as Cloudflare bills them. It takes GB as 10^9 bytes and holds storage at today's level for the whole period. `checks.x86_64-linux.r2-usage` requires the panel's queries to equal `costQueries`.

  `R2CostProjected` (info) projects each class's operations so far over the period. The elapsed time used is at least one day, so a burst in the first hours does not warn. The rule fires when Class A passes 1M, when Class B passes 10M, or when stored bytes pass `storageBudgetGBMonth`, which is 300.
- **Rationale**:
  - Both operation classes are $-steps at the free-tier edge.
  - Storage is already far past its 10 GB free tier and costs linearly beyond it, so a free-tier arm for storage would fire forever. A budget is an edge that can still be crossed. Its comment records the baseline it was set against: 257.39 GB, $3.26 storage, $4.50 Class A.

### D5: Authentication, and the poller's own cost
- **Choice**:
  - A clan vars generator `cloudflare-analytics` with a hidden, persisted prompt `api-token` (not deployed) and a deployed file `token`.
  - The token is an Account API token with exactly Account > Account Analytics > Read.
  - `r2-usage.service` loads the file as the systemd credential `token`. The obligation fails if any other unit loads it or if the file is owned by anyone but root.
- **Cost**:
  - GraphQL Analytics API requests are Cloudflare API requests, not R2 operations. `r2/pricing.mdx` lists the billable Class A and B operations, which are S3 and bucket operations, and the analytics API is not among them.
  - `analytics/graphql-api/limits.mdx` sets a quota of 300 queries per 5 minutes and names no charge. The poller sends 24 requests a day.
  - The new series add about 30 samples a minute to GreptimeDB, whose SSTs live in `sciexp`. That cost is negligible next to the existing ones, and it is not measured.

### D6: Off until the token is in the repository
- **Choice**:
  - `vanixiets.r2Usage.enable` defaults to false, and `flake.lib.r2Usage.awaitingSecrets` is `[ "magnetite" ]`.
  - `flake.lib.r2UsageObligations`, asserted by `withFleetObligations`, fails in these cases:
    - the poller host is off and not awaiting its token;
    - the poller is on but the host is still listed as awaiting;
    - the poller is on without the vars in the repository;
    - the poller is on and `r2-usage` is missing from `notifiedUnits`;
    - the token is owned by anyone but root, or loaded by another unit;
    - the poller is on for any host other than magnetite.

  The commit that adds magnetite's vars also makes three edits: it enables the option, removes magnetite from `awaitingSecrets`, and adds `r2-usage` to magnetite's `notifiedUnits`.
- **Rationale**: This is back-up-postgresql-off-host D16. A declared generator makes `clan machines update` prompt for its value, so an unattended deploy of main would block until the token exists.

### D7: Pending uploads, growth and staleness
- **Pending uploads**: `R2MultipartUploadPending` fires when `uploadCount > 0` holds for 24 h. `sciexp`'s lifecycle rule aborts uploads at 7 days. The other buckets have no abort rule.
- **Growth**: `R2BucketGrowthAnomalous` fires when both of these hold for 2 h:
  - `deriv(payload[7d]) * 604800 > 1 GB`;
  - `deriv(payload[7d]) > 3 * deriv(payload[30d])`.

  `deriv()` fits a least-squares line to whatever samples each window holds. That makes the rule:
  - defined from the second sample on;
  - hard for one odd sample to move;
  - silent while there are fewer than 7 days of history, because both windows then hold the same samples and compare equal;
  - fully discriminating once there are 30 days of history.

  The rule uses payload only, because metadata is under 0.1 % of it.
- **Staleness**: The publisher keeps the file fresh, so HostProbeStale passes as long as the publisher runs. `R2UsageStale` reads the poll's own success time and fires after 2 h, which is two missed polls. When no record exists, the publisher seeds the success time with its own start, so a poller that never succeeds still ages. This is the `PostgresqlBackupStale` pattern.

### D8: Declared and external buckets
- **Choice**: `declaredBuckets` comes from `modules/terranix/cloudflare.nix` itself. Its `cloudflare_r2_bucket` resources are applied to placeholder arguments, and their `name`s are read. If a name stops being a literal, evaluation fails loudly.

  `externalBuckets` maps a name to an owner note for buckets that terranix deliberately does not manage. It is empty. The account held only the three declared buckets on 2026-11-20, after the operator deleted the empty `omicsberg`.

  `R2BucketUndeclared` has two arms. It fires on a bucket in neither list, and on an external bucket with any object or byte, because its entry claims it is empty. `fleetAlertRules` takes `r2ExternalBuckets` as a parameter, so the check can render the rule with a fixture bucket listed.

  A deleted bucket keeps its last storage sample inside the query's one-day window: the first live poll at 16:28Z on 2026-11-20 still reported `omicsberg`, deleted at about 15:55Z. So the poller drops a bucket whose latest sample is older than `storageFreshSeconds` (2 h). The docs give no sampling cadence. The live response for 2026-11-18 to 2026-11-20 showed samples every 10 to 60 minutes for every bucket, the empty `omicsberg` hourly, so 2 h is twice the longest gap seen. The bucket's operations in the period were real and billed, so they stay, labelled `gone="true"`; the rule reads storage series only. The rule's `for` is `storageFreshSeconds` plus 2 h (4 h), which exceeds the bound plus one hourly poll. A bucket first polled after its deletion therefore drops out before the rule fires.
- **Boundary**: vendored-versus-first-party. Only our own module's literals are read, not the provider's state.

### D9: Regulators
- **Poller**: `checks.x86_64-linux.r2-usage` formats `response.json` (written to the documented schema) at 2026-11-20T15:00:00Z and compares the result with `expected.prom`. The fixture holds every action type of the live period. Five mutants must each change a named line:
  - `unitConfusion`: sizes read as KiB;
  - `classMapping`: `ListObjects` priced as class B;
  - `bucketDropped`: only rows at the newest time kept;
  - `noFreshness`: the bound widened to the query's whole day;
  - `deleteObjectsFree`: `DeleteObjects` counted as free.

  The same check runs the judge over literal fixtures and asserts the dashboard's cost queries.
- **Rules**: `fleet-alert.passthru.r2PromtoolRehearsal` runs one promtool case per rule. The mutants are `moreThanOne`, `noProjection`, `noClamp`, `noBaseline`, `noExclusion`, `externalIgnored`, `forOneHour` and `r2StaleThreshold`.
- **Store**: every expression was run against GreptimeDB 1.2.1 on magnetite on 2026-11-20. GreptimeDB accepted each one: `scalar`, `clamp_min`, `label_replace`, `deriv` over 30 d, and set operators with `count by`.

## Per-service attribution within `sciexp`

GreptimeDB (`projects/vanixiets/observability/store/`), omnigraph (`omnigraph/…`) and the browser evidence share `sciexp`. Cloudflare's analytics are per bucket, so this source cannot split `sciexp` by service. Two things could provide that split:
- separate buckets per service, which needs a data migration;
- a periodic per-prefix size, computed from data we already hold. GreptimeDB's own metrics endpoint, which the collector already scrapes as job `greptimedb`, may carry its region or object-store sizes; that is unverified, and it would be the first place to check. A daily S3 `ListObjectsV2` sum per prefix would also work, though it costs Class A operations.

Neither is implemented here.

## Risks

- R2's action type names may differ from the pricing page's. An unnamed type is counted as `unclassified` and shown on the dashboard, not dropped. The live period had three: `DeleteObjects`, `GetBucketNotificationConfiguration` and `GetBucketSippyConfiguration`. No R2 page names their class. The dashboard's 1.22M Class A and 1.58M Class B match our A and B without the 56,363 `DeleteObjects`, which suggests they are not billed.
- The analytics datasets are sampled. The GraphQL API is not a billing measure.
