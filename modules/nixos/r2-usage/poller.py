"""The account's R2 usage as node_exporter textfile series (r2-usage).

One GraphQL Analytics API request per run reads two datasets for every
bucket in the account (no bucket list is configured):
  r2StorageAdaptiveGroups over the last day, by bucketName and datetime; the
    latest sample of each bucket gives
    vanixiets_r2_bucket_payload_bytes{bucket}, _metadata_bytes{bucket},
    vanixiets_r2_bucket_objects{bucket} and
    vanixiets_r2_bucket_pending_uploads{bucket} (uploadCount, the pending
    multipart uploads). A bucket whose latest sample is older than the
    configured storageFreshSeconds writes no storage series: Cloudflare was
    seen sampling every existing bucket, empty ones too, at least hourly,
    so such a bucket has been deleted;
  r2OperationsAdaptiveGroups from the start of the billing period to now,
    by bucketName and actionType, summed into
    vanixiets_r2_operations{bucket,class}: class A, B or free per
    Cloudflare's R2 pricing page, and `unclassified` for an action type the
    page does not name, so a new one is counted rather than lost. An
    operation on no bucket (ListBuckets) is counted under bucket
    "(account)". Every bucket gets an A and a B series, zero when it saw no
    such operation. The operations of a bucket with no fresh storage sample
    were real and billed, so they stay, labelled gone="true".
The billing period runs from 00:00 UTC on the configured anchor day of the
month (clamped to the month's last day) to the same time a month later;
vanixiets_r2_billing_period_{start,end}_timestamp_seconds carry it, and
vanixiets_r2_last_success_timestamp_seconds the time of this run.

A response with errors, or without either dataset, fails the run and leaves
the previous file in place, so its last-success time ages.

Usage: poller.py CONFIG TOKEN_FILE OUTPUT_FILE
       poller.py --format CONFIG RESPONSE_FILE NOW_EPOCH_SECONDS
       (prints the file the response gives at that time)
CONFIG is JSON: {"accountTag": str, "endpoint": str, "billingAnchorDay": int,
"storageFreshSeconds": int,
"classes": {"A": [actionType], "B": [actionType], "free": [actionType]}}.
"""

import calendar
import json
import os
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

QUERY = """
query R2Usage($accountTag: string!, $storageSince: Time!, $periodStart: Time!, $now: Time!) {
  viewer {
    accounts(filter: { accountTag: $accountTag }) {
      storage: r2StorageAdaptiveGroups(
        limit: 10000
        filter: { datetime_geq: $storageSince, datetime_leq: $now }
        orderBy: [datetime_DESC]
      ) {
        max { payloadSize metadataSize objectCount uploadCount }
        dimensions { bucketName datetime }
      }
      operations: r2OperationsAdaptiveGroups(
        limit: 10000
        filter: { datetime_geq: $periodStart, datetime_leq: $now }
      ) {
        sum { requests }
        dimensions { bucketName actionType }
      }
    }
  }
}
"""

STORAGE_SERIES = [
    ("vanixiets_r2_bucket_payload_bytes", "payloadSize",
     "Bytes of the objects in the bucket, at the latest storage sample."),
    ("vanixiets_r2_bucket_metadata_bytes", "metadataSize",
     "Bytes of the objects' metadata in the bucket, at the latest storage sample."),
    ("vanixiets_r2_bucket_objects", "objectCount",
     "Objects in the bucket, at the latest storage sample."),
    ("vanixiets_r2_bucket_pending_uploads", "uploadCount",
     "Pending multipart uploads in the bucket, at the latest storage sample."),
]


def iso(moment):
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def anchor(year, month, day):
    last = calendar.monthrange(year, month)[1]
    return datetime(year, month, min(day, last), tzinfo=timezone.utc)


def billing_period(now, day):
    """The billing period holding `now`: [start, end)."""
    start = anchor(now.year, now.month, day)
    if start > now:
        year, month = (now.year, now.month - 1) if now.month > 1 else (now.year - 1, 12)
        start = anchor(year, month, day)
    year, month = (start.year, start.month + 1) if start.month < 12 else (start.year + 1, 1)
    return start, anchor(year, month, day)


def classify(action, classes):
    for name in ("A", "B", "free"):
        if action in classes[name]:
            return name
    return "unclassified"


def account_of(response):
    if response.get("errors"):
        raise ValueError(f"GraphQL errors: {json.dumps(response['errors'])}")
    accounts = ((response.get("data") or {}).get("viewer") or {}).get("accounts") or []
    if len(accounts) != 1:
        raise ValueError(f"expected one account, got {len(accounts)}")
    account = accounts[0]
    for dataset in ("storage", "operations"):
        if account.get(dataset) is None:
            raise ValueError(f"the response has no {dataset} dataset")
    return account


def format_usage(response, now, config):
    account = account_of(response)
    start, end = billing_period(now, config["billingAnchorDay"])

    fresh = timedelta(seconds=config["storageFreshSeconds"])
    latest = {}
    for row in account["storage"]:
        bucket = row["dimensions"]["bucketName"]
        moment = row["dimensions"]["datetime"]
        if bucket not in latest or moment > latest[bucket][0]:
            latest[bucket] = (moment, row["max"])
    latest = {
        bucket: sample for bucket, sample in latest.items()
        if now - datetime.fromisoformat(sample[0].replace("Z", "+00:00")) <= fresh
    }

    operations = {}
    for row in account["operations"]:
        bucket = row["dimensions"]["bucketName"] or "(account)"
        key = (bucket, classify(row["dimensions"]["actionType"], config["classes"]))
        operations[key] = operations.get(key, 0) + int(row["sum"]["requests"])

    buckets = sorted(set(latest) | {bucket for bucket, _ in operations})
    for bucket in buckets:
        for cls in ("A", "B"):
            operations.setdefault((bucket, cls), 0)

    lines = []
    for name, field, help_text in STORAGE_SERIES:
        lines += [f"# HELP {name} {help_text}", f"# TYPE {name} gauge"]
        for bucket in sorted(latest):
            value = int(latest[bucket][1][field])
            lines.append(f'{name}{{bucket="{bucket}"}} {value}')
    name = "vanixiets_r2_operations"
    lines += [
        f"# HELP {name} Operations on the bucket since the billing period began, by pricing class.",
        f"# TYPE {name} gauge",
    ]
    for (bucket, cls), value in sorted(operations.items()):
        gone = ',gone="true"' if bucket != "(account)" and bucket not in latest else ""
        lines.append(f'{name}{{bucket="{bucket}",class="{cls}"{gone}}} {value}')
    for name, moment, help_text in [
        ("vanixiets_r2_billing_period_start_timestamp_seconds", start,
         "Unix time the billing period began."),
        ("vanixiets_r2_billing_period_end_timestamp_seconds", end,
         "Unix time the billing period ends."),
        ("vanixiets_r2_last_success_timestamp_seconds", now,
         "Unix time of the last poll whose response gave both datasets."),
    ]:
        lines += [f"# HELP {name} {help_text}", f"# TYPE {name} gauge",
                  f"{name} {int(moment.timestamp())}"]
    return "\n".join(lines) + "\n"


def query(config, token, now):
    start, _ = billing_period(now, config["billingAnchorDay"])
    body = json.dumps({
        "query": QUERY,
        "variables": {
            "accountTag": config["accountTag"],
            "storageSince": iso(now - timedelta(days=1)),
            "periodStart": iso(start),
            "now": iso(now),
        },
    }).encode()
    request = urllib.request.Request(
        config["endpoint"],
        data=body,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=60) as reply:
        return json.load(reply)


def main(argv):
    if len(argv) == 5 and argv[1] == "--format":
        config = json.loads(open(argv[2]).read())
        response = json.loads(open(argv[3]).read())
        now = datetime.fromtimestamp(int(argv[4]), tz=timezone.utc)
        sys.stdout.write(format_usage(response, now, config))
        return 0
    if len(argv) != 4:
        sys.stderr.write(__doc__)
        return 2
    config = json.loads(open(argv[1]).read())
    token = open(argv[2]).read().strip()
    now = datetime.now(timezone.utc).replace(microsecond=0)
    text = format_usage(query(config, token, now), now, config)
    output = argv[3]
    with open(output + ".tmp", "w") as handle:
        handle.write(text)
    os.chmod(output + ".tmp", 0o644)
    os.replace(output + ".tmp", output)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
