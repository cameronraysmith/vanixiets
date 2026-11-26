---
title: OmniGraph
description: "How magnetite's omnigraph-server is watched: what omnigraph-probe reads every minute, what each of its series means, the read-only monitor actor, and how to answer OmnigraphNotServing."
---

This runbook covers the graph store magnetite serves, `omnigraph-server.service` from `flake.modules.nixos.omnigraph` in `modules/nixos/omnigraph.nix`, and how it is watched.
magnetite serves ten example graphs, one per cookbook of the pinned `omnigraph-cookbooks`, `cookbook-agent-ops` to `cookbook-vc-os`, on port 8090, which cinnabar's TLS fronts reach over the mesh.

## What watches the server

Four things report on `omnigraph-server`:
- its own failure notice: `omnigraph-server` is among magnetite's notified units, so a failed start posts `FAILED omnigraph-server.service on magnetite` to `fleet-alerts`;
- `omnigraph-probe.service`, every minute, which writes the server's state to node_exporter's textfile collector as `/run/node-exporter-textfile/omnigraph.prom`;
- the alert `OmnigraphNotServing`, which fires when the probe has found the server not ready, or serving a blocked graph, for 5 minutes;
- the Perses view `OmniGraph` (`modules/nixos/perses/resources/dashboard-omnigraph.json`), which shows every series below per host.

A probe that stops writing is reported by `HostProbeStale`, as for every textfile writer.

## What the probe reads

omnigraph-server serves no metrics endpoint, so `omnigraph-probe` (`modules/nixos/omnigraph-probe.nix`) asks the server and the host:
- `GET /readyz`, which needs no token and answers whether the server is ready and how many graphs it serves, and how many of them are ready, loading or blocked, but not which;
- `systemctl show omnigraph-server`, for the time from the server's main process start to the end of its start job, whose readiness wait ends only once every graph is open;
- with the `monitor` actor's token, `GET /graphs` for the graphs and their states, then `GET /graphs/<graph>/snapshot` for each ready graph: the entity count of each of its datasets, its manifest version and its storage format;
- on a local root only, `zfs list` for the dataset mounted at the root's parent directory and its snapshots, and `/var/lib/omnigraph-metrics/lock-recoveries` for the number of stale locks the server's start has cleared.

The probe runs as node_exporter's user, so it can write the directory node_exporter reads, and receives the token through systemd credentials.
A read that fails leaves its series out of the file and keeps the others; nothing the probe finds fails the unit.

## The series

| Series | Meaning | Written |
|---|---|---|
| `vanixiets_omnigraph_ready` | 1 while `/readyz` answers `ready: true`; 0 while it answers otherwise or nothing answers | always |
| `vanixiets_omnigraph_graphs{state}` | the graphs the server serves (`served`, blocked ones included) and how many are `ready`, `loading` and `blocked` | while `/readyz` answers |
| `vanixiets_omnigraph_start_to_ready_seconds` | seconds from the main process start of the current run to the end of its start job | while the unit is active |
| `vanixiets_omnigraph_graph_entities{graph}` | entities in the graph's `main` branch, summed over its datasets | per ready graph, with the `monitor` actor's access |
| `vanixiets_omnigraph_graph_manifest_version{graph}` | the graph manifest version of `main`, which rises with each commit | per ready graph, with the `monitor` actor's access |
| `vanixiets_omnigraph_graph_storage_format{graph}` | the storage format (`internal_schema_version`) `main` is stamped at | per ready graph, with the `monitor` actor's access |
| `vanixiets_omnigraph_dataset_used_bytes` | bytes the dataset holding the root uses, snapshots included | on a local root on its own ZFS dataset |
| `vanixiets_omnigraph_dataset_quota_bytes` | that dataset's quota, 0 for none | on a local root on its own ZFS dataset |
| `vanixiets_omnigraph_dataset_snapshots` | that dataset's snapshots | on a local root on its own ZFS dataset |
| `vanixiets_omnigraph_lock_recoveries_total` | stale serve locks the server's start has cleared on this host, 0 before the first | on a local root |

Every name is in `nodeExporterKeep` in `modules/clan/services/otel-collector/schema.nix`, and an assertion in the probe's module fails evaluation when one is missing there or the textfile collector is off.
magnetite serves its graphs from R2 today, so its file holds only the first three series and, once the `monitor` actor may read the graphs, the per-graph ones; the dataset panels of the view stay empty.

## The monitor actor

The per-graph reads need a bearer token, and the probe reads as `monitor`, an actor allowed to list the graphs and read them and nothing else, so that `admin`'s token is not read every minute.
Its token is the clan vars generator `omnigraph-monitor-token` on magnetite; `services.omnigraph.extraBearerTokenFiles.monitor` names its file, and the server's start adds it to the assembled tokens file, refusing to start if the tokens file already names `monitor`.
`modules/machines/nixos/magnetite/omnigraph/server.policy.yaml` grants it `graph_list`, and `examples.policy.yaml` grants it `read` on every example graph; `checks.x86_64-linux.omnigraph-cluster-actor-policy` holds it to those and denies it `change`, `export`, `schema_apply`, `maintain` and `config_manage`.

A policy reaches a root only through `cluster apply`, which on magnetite runs at a root's creation or by hand with the server stopped.
Until an apply has reached the served root with these grants, `GET /graphs` refuses `monitor` and the per-graph series are absent; readiness and graph counts do not depend on them.

Regenerating the token restarts `omnigraph-server`, which reads it only at start:

```bash
clan vars generate magnetite --generator omnigraph-monitor-token --regenerate
```

## Answering OmnigraphNotServing

The alert fires when `vanixiets_omnigraph_ready == 0 or vanixiets_omnigraph_graphs{state="blocked"} > 0` has held for 5 minutes.
The first arm's instance carries the host; the second's also carries `state="blocked"`.

On the host, first look at the unit and what the probe last wrote:

```bash
systemctl status omnigraph-server omnigraph-probe.timer
sudo journalctl -u omnigraph-server -n 100 --no-pager
cat /run/node-exporter-textfile/omnigraph.prom
curl -sS http://127.0.0.1:8090/readyz | jq
```

Then, by what you find:
- The unit is `activating`: the start job is still waiting for every graph to open. A start over magnetite's R2 root takes about 4 min 50 s, so a slow one fires the alert; it resolves 5 minutes after `/readyz` answers ready. A start that outlasts its `TimeoutStartSec` fails and posts its failure notice.
- The unit failed: read the journal from the failed start. A held admission lock (`state_lock_held`) left by a direct writer needs `sudo omnigraph-cluster force-unlock <LOCK_ID>` with the id `sudo omnigraph-cluster status --json` reports; a root that was never applied needs `systemctl restart omnigraph-cluster-apply` with the server stopped. Start it again with `systemctl start omnigraph-server` once the cause is gone.
- The unit is active and `/readyz` reports a blocked graph: graphs are opened only at a start, so a blocked graph stays blocked until the server restarts. Read which graph and why from `GET /graphs`, whose entries carry `failure` and `action`, as `admin`:

  ```bash
  sudo jq -r '"header = \"Authorization: Bearer \(.admin)\""' \
      /run/secrets/vars/per-machine/magnetite/omnigraph-bearer-tokens/tokens.json \
    | curl -sS --config - -H 'Omnigraph-Http-Api: 0.14' http://127.0.0.1:8090/graphs \
    | jq '.graphs[] | select(.state != "ready")'
  ```

  `Omnigraph-Http-Api` names the HTTP contract of the packaged omnigraph, which `omnigraph version --json` reports as `http_contract`. Correct the graph's configuration or storage, apply it with the server stopped, and start the server.
- The unit is active, `/readyz` answers ready, and the probe's file still says 0: the probe cannot reach the server. Read `sudo journalctl -u omnigraph-probe -n 20 --no-pager` and run `sudo systemctl start omnigraph-probe` to write the file again.

The alert resolves 5 minutes after the probe last found the server not ready or a graph blocked.
