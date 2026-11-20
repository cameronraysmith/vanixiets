## ADDED Requirements

### Requirement: The poller writes every bucket's usage to the textfile directory

Where `vanixiets.r2Usage.enable` is set, `r2-usage.service` SHALL run hourly and write, for every bucket in the account's latest storage sample, `vanixiets_r2_bucket_{payload_bytes,metadata_bytes,objects,pending_uploads}{bucket}` and `vanixiets_r2_operations{bucket,class}` since the billing period began, through the host's one textfile directory.

#### Scenario: a recorded response is formatted

- **WHEN** the poller formats `modules/checks/r2-usage/response.json` at 2026-11-20T15:00:00Z
- **THEN** its output equals `modules/checks/r2-usage/expected.prom`

#### Scenario: a bucket sampled earlier than the others

- **WHEN** one bucket's latest storage sample is an hour older than the others'
- **THEN** its series are still written

### Requirement: A deleted bucket's storage is dropped and its operations kept

The poller SHALL write no storage series for a bucket whose latest storage sample is older than `flake.lib.r2Usage.storageFreshSeconds`, and SHALL keep that bucket's operations in the period, labelled `gone="true"`.

#### Scenario: a bucket last sampled 2 h 10 min ago

- **WHEN** the recorded response's `deleted-scratch` was last sampled 2 h 10 min before the poll
- **THEN** no `vanixiets_r2_bucket_*` series names it, and its operations carry `gone="true"`

### Requirement: Operations are classed by R2's pricing page

Each action type SHALL count toward class `A`, `B` or `free` as `r2/pricing.mdx` lists it, and toward `unclassified` when the page does not name it; an operation on no bucket SHALL count under bucket `(account)`.

#### Scenario: ListObjects

- **WHEN** a response holds 187,340 `ListObjects` on `sciexp`
- **THEN** they count toward `vanixiets_r2_operations{bucket="sciexp",class="A"}`

#### Scenario: an action type the page does not name

- **WHEN** a response holds 55,752 `DeleteObjects` on `sciexp`
- **THEN** they count toward `vanixiets_r2_operations{bucket="sciexp",class="unclassified"}`

### Requirement: The poller is off until its token is in the repository

`vanixiets.r2Usage.enable` SHALL default to false; a fleet obligation SHALL fail `flake.lib.r2Usage.host` when the poller is off and the host is not in `awaitingSecrets`, and any host when the poller is on while awaiting, without the `cloudflare-analytics` vars, outside `notifiedUnits`, or on another host.

#### Scenario: main before the token is minted

- **WHEN** magnetite is evaluated with the poller off and magnetite in `awaitingSecrets`
- **THEN** the obligation reports no problem

#### Scenario: awaiting list emptied without the token

- **WHEN** magnetite is removed from `awaitingSecrets` while the poller stays off
- **THEN** the obligation reports exactly one problem

### Requirement: Only the poller reads the analytics token

The `cloudflare-analytics` generator's deployed `token` SHALL be owned by root and loaded as a systemd credential by `r2-usage.service` alone; the obligation SHALL fail when its owner differs or another unit loads it.

#### Scenario: a second unit loads the token

- **WHEN** a judged host lists `nixbot` beside `r2-usage` as loading the token
- **THEN** the obligation reports exactly one problem

### Requirement: Stale usage is reported

`R2UsageStale` SHALL fire when `vanixiets_r2_last_success_timestamp_seconds` is over 2 h old for 10 min, and the publisher SHALL seed that time when no record exists, so a poller that never succeeds is reported.

#### Scenario: the poll stops

- **WHEN** the last success stops advancing at 2 h
- **THEN** the rule is pending at 4 h 10 min and fires at 4 h 20 min

### Requirement: Cost edges are projected per billing period

`R2CostProjected` SHALL fire, per class, when class A or B operations so far, scaled to the billing period over at least one elapsed day, exceed 1,000,000 or 10,000,000, or when stored bytes exceed `storageBudgetGBMonth` GB.

#### Scenario: class A on pace past the free tier

- **WHEN** class A grows 1,700 an hour in a 30-day period
- **THEN** class A fires at 10 d 2 h and not at 12 h

### Requirement: Undeclared and non-empty external buckets are reported

`R2BucketUndeclared` SHALL fire for a bucket neither declared by `modules/terranix/cloudflare.nix` nor listed in `flake.lib.r2Usage.externalBuckets`, and for a listed external bucket holding any object or byte.

#### Scenario: an external bucket gains objects

- **WHEN** a listed external bucket reports 3 objects for 4 h
- **THEN** the rule fires for that bucket

### Requirement: Pending uploads and anomalous growth are reported

`R2MultipartUploadPending` SHALL fire when a bucket holds a pending upload for 24 h, and `R2BucketGrowthAnomalous` when a bucket's 7-day fitted growth exceeds 1 GB a week and three times its 30-day fitted growth for 2 h.

#### Scenario: steady growth

- **WHEN** a bucket grows 2 GB a day for 35 days
- **THEN** the growth rule does not fire

### Requirement: The dashboard's cost uses the rules' prices

The `r2-usage` dashboard's cost panel queries SHALL equal `flake.lib.r2Usage.costQueries`, rendered from `pricing` and `freeTier`.

#### Scenario: a price changes in one place

- **WHEN** `pricing` changes and the dashboard does not
- **THEN** `checks.x86_64-linux.r2-usage` fails to evaluate
