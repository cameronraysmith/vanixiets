Summarize the newline-delimited JSON build event log at `/root/build-events.jsonl` and write the result to `/logs/artifacts/summary.json`.

The summary object carries exactly these keys, every value an integer:

- `total_events`: the number of event records in the log.
- `failed_events`: the number of records whose `status` field equals `failed`.
- `per_pipeline`: an object mapping each distinct `pipeline` value to an object with `events` (that pipeline's record count) and `failed` (that pipeline's records with `status` equal to `failed`).
- `median_duration_ms`: the median of `duration_ms` across all records, as an integer.
  With an odd record count this is the middle value of the sorted durations; with an even count it is the mean of the two middle values, rounded down.

The result is judged by exact structural equality against the same computation over the log, so every count must be exact and no key may be missing, renamed, or extra.
