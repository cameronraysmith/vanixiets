# Analytics data serving with DuckDB

DuckDB serves as the analytics data source within the hypermedia architecture established in sections 01 through 07.
The data flow connects remote analytical storage to browser-rendered visualizations through a chain of well-defined boundaries: DuckDB queries remote DuckLake catalogs or Parquet files via httpfs, an axum handler executes the query through async-duckdb, the result is serialized and delivered as an SSE event, Datastar updates the DOM, and a visualization component renders the data.

This architecture enables web applications to query datasets much larger than browser memory by pushing filtering and aggregation to the server, where DuckDB's columnar engine and predicate pushdown through httpfs read only the relevant row groups from remote storage.
The browser never receives raw analytical data in bulk; it receives either pre-aggregated JSON suitable for Datastar signal updates or, for larger result sets, serialized payloads consumed by visualization components.

## async-duckdb as the stable integration component

async-duckdb provides an async Rust interface to DuckDB, bridging the gap between DuckDB's synchronous C API and axum's async request handling.
The library wraps each DuckDB connection in a dedicated thread and communicates via channels, allowing `conn` and `conn_mut` calls to be awaited from async handlers without blocking the tokio runtime.

The `Pool` type manages multiple connections with round-robin dispatch.
DuckDB supports concurrent reads but is single-writer, which aligns naturally with the SSE read-heavy pattern described in section 02: most requests are analytical queries served from the read path, while writes (data ingestion, catalog attachment) are infrequent and occur at startup or in response to specific domain events.

A service wrapper around `Option<Pool>` centralizes availability checking and error mapping.
When analytics is unavailable (the pool was not configured), query methods return a structured error that maps to HTTP 503, keeping the rest of the application functional.
This pattern treats the analytics subsystem as a degradable capability rather than a hard dependency.

```rust
#[derive(Clone)]
pub struct DuckDBService {
    pool: Option<DuckDbPool>,
}

impl DuckDBService {
    pub async fn query<F, T>(&self, func: F) -> Result<T, AnalyticsError>
    where
        F: FnOnce(&duckdb::Connection) -> Result<T, duckdb::Error> + Send + 'static,
        T: Send + 'static,
    {
        let pool = self.pool.as_ref()
            .ok_or_else(|| AnalyticsError::unavailable())?;
        pool.conn(func).await.map_err(Into::into)
    }
}
```

The closure-based API means the handler constructs its query inside the closure, which executes on the connection's dedicated thread.
Results cross back to the async context via the channel.
This is the stable foundation for analytics data serving; higher-level patterns built on top (caching, query session management) may evolve independently.

## Query result serialization for SSE

DuckDB query results are natively backed by Arrow columnar arrays, but the serialization format for SSE payloads depends on the consumer and the payload size.

For small result sets consumed by Datastar signals, serialize to JSON.
Signal updates flow through `PatchSignals` events as described in section 03.
A handler might query DuckDB for a summary statistic and push it as a signal:

```rust
async fn gene_count_handler(
    State(analytics): State<AnalyticsState>,
    sse: ServerSentEventGenerator,
) -> Result<impl IntoResponse, AppError> {
    let count: i64 = analytics.service.query(|conn| {
        conn.prepare("SELECT COUNT(DISTINCT gene_id) FROM expression WHERE cell_type = ?1")?
            .query_row(params![cell_type], |row| row.get(0))
    }).await?;

    sse.patch_signals(json!({ "geneCount": count }));
    Ok(())
}
```

For larger result sets consumed by visualization components (charting libraries, table renderers), there are two approaches.
Pre-aggregate on the server and send JSON arrays that the visualization component can consume directly, keeping payloads small enough for SSE transport.
Alternatively, for bulk transfers where a visualization library can parse Arrow IPC, serialize the Arrow record batch and send it as a binary SSE payload or as a separate HTTP response referenced by the SSE event.
The choice depends on the consumer's capabilities and the acceptable payload size.

The general principle is that the server performs as much aggregation as possible before serialization, minimizing what crosses the network boundary.
DuckDB's analytical engine is well-suited to this: GROUP BY, window functions, and approximate aggregation (HyperLogLog, reservoir sampling) all execute server-side, and only the summary reaches the browser.

## Predicate pushdown from UI interactions

User interactions in the browser generate parameterized DuckDB queries on the server.
When a user selects a gene, filters by cell type, or chooses a time range, the Datastar signal update triggers a backend action that constructs and executes a filtered query.

The architectural value of this pattern is that DuckDB pushes predicates down through httpfs to remote Parquet files, reading only the relevant row groups rather than downloading entire datasets.
A query filtering expression data by gene and cell type might read a few megabytes of a multi-gigabyte remote Parquet file, with the row group pruning happening transparently based on Parquet metadata.

The server receives filter parameters from Datastar signals (see the ReadSignals pattern in section 03), constructs a parameterized query, executes it, and streams results back via SSE:

```rust
async fn filtered_expression_handler(
    State(analytics): State<AnalyticsState>,
    signals: ReadSignals<FilterSignals>,
    sse: ServerSentEventGenerator,
) -> Result<impl IntoResponse, AppError> {
    let results = analytics.service.query(move |conn| {
        let mut stmt = conn.prepare(
            "SELECT gene_id, mean_expression, cell_count \
             FROM expression \
             WHERE cell_type = ?1 AND organism = ?2 \
             ORDER BY mean_expression DESC \
             LIMIT ?3"
        )?;
        let rows = stmt.query_map(
            params![signals.cell_type, signals.organism, signals.limit],
            |row| Ok(ExpressionRow {
                gene_id: row.get(0)?,
                mean_expression: row.get(1)?,
                cell_count: row.get(2)?,
            }),
        )?;
        rows.collect::<Result<Vec<_>, _>>()
    }).await?;

    let fragment = render_expression_table(&results);
    sse.patch_elements("#expression-results", fragment);
    Ok(())
}
```

Parameterized queries are essential for safety.
Never construct SQL by string interpolation from user input; use DuckDB's parameter binding (`?1`, `?2`, or named parameters like `$cell_type`) which prevents SQL injection by design.
The ReadSignals deserialization step also provides a type-checked boundary: signals are parsed into a typed struct before reaching query construction, and invalid values fail at deserialization rather than producing malformed SQL.

## httpfs configuration for remote data

DuckDB within an axum service accesses remote data sources through the httpfs extension, which enables transparent HTTP, HTTPS, and S3 reads from Parquet files, CSV files, and DuckLake catalog databases.

Extension initialization happens at service startup, not per-request.
The httpfs and DuckLake (`ducklake`) extensions must be installed once (writing to `~/.duckdb/extensions/`) and loaded on every connection in the pool, since DuckDB extensions are per-connection state:

```rust
pub async fn initialize_extensions(pool: &Pool) -> Result<(), AnalyticsError> {
    // INSTALL is idempotent: writes extension to disk once
    pool.conn(|conn| {
        conn.execute("INSTALL httpfs", [])?;
        conn.execute("INSTALL ducklake", [])?;
        Ok(())
    }).await?;

    // LOAD must run on every connection in the pool
    let results = pool.conn_for_each(|conn| {
        conn.execute("LOAD httpfs", [])?;
        conn.execute("LOAD ducklake", [])?;
        Ok(())
    }).await;

    for result in results {
        result?;
    }
    Ok(())
}
```

HuggingFace Hub datasets are accessible via the `hf://` protocol after loading httpfs.
DuckLake catalogs on HuggingFace use URIs like `ducklake:hf://datasets/org/repo/lakes/catalog.db`, which DuckDB resolves through httpfs to read the catalog metadata and the underlying Parquet data files.
Authentication for private datasets uses the `HF_TOKEN` environment variable, which httpfs reads automatically.

Catalog attachment also runs at startup or on-demand when new data sources are configured, using `ATTACH` with a validated alias:

```rust
// Attach runs on all pool connections so every connection can query the catalog
let results = pool.conn_for_each(move |conn| {
    conn.execute(&format!("ATTACH '{uri}' AS {alias}"), [])?;
    Ok(())
}).await;
```

The alias must be validated as a safe SQL identifier before interpolation, since DuckDB's ATTACH syntax does not support parameterized queries for the URI or alias.
Validate that the alias contains only alphanumeric characters and underscores, starts with a letter or underscore, and reject anything else.

## Cache strategy (provisional)

The current implementation uses an in-memory async cache (moka) to memoize DuckDB query results.
On cache hit, serialized results are returned without executing the query.
On cache miss, the query runs, results are serialized into the cache, and the original value is returned.

This cache layer is provisional and may change after further validation and testing.
async-duckdb and the `DuckDBService` wrapper are the stable components; the cache sits above them and can be replaced or removed without affecting the query execution path.

The cache key structure encodes the query context (catalog, table, version) and a hash of the query parameters, enabling prefix-based invalidation when upstream data changes.
For embedded catalogs (compiled into the binary), the binary version is part of the key prefix, so cache entries automatically invalidate on rebuild.

When documenting or implementing caching for analytics queries, treat it as an implementation detail subject to change rather than a prescribed architectural pattern.
The decision of whether to cache, how long entries live, and how invalidation propagates depends on the data freshness requirements of each use case.

## Integration with event architecture

Analytics queries connect to the event architecture described in section 07 in two directions.

On the read side, DuckDB analytics is a projection: the event log is the write-side authority, and DuckDB queries are the read-side materialization.
When domain events indicate that new data has been ingested, processed, or made available, those events can trigger cache invalidation or re-execution of standing queries, pushing updated results to connected SSE clients via PatchElements or PatchSignals.

On the write side, query execution itself can be modeled as a command-event workflow.
A `StartQuery` command initiates the process, a `QueryStarted` event records the intent, and the actual DuckDB execution runs as a background task that issues subsequent commands (`BeginExecution`, `CompleteQuery`, or `FailQuery`) back through the aggregate.
Clients observe query progress via SSE events published from the event bus, maintaining the Tao of Datastar principle that the server drives UI state.

The event log also captures query patterns for debugging and optimization.
Persisted query events record which SQL was executed, how long it took, how many rows were returned, and whether it succeeded or failed.
This history supports retrospective analysis of query performance and usage patterns without adding separate telemetry infrastructure.

Cross-reference section 07 for the event architecture foundation, including the projection pipeline, temporal consistency model, and the distinction between domain events and transport events that applies equally to analytics query results.

## Related documents

- `01-architecture.md` - effect boundaries, server-first philosophy
- `02-sse-patterns.md` - SSE streaming mechanics, reconnection
- `03-datastar.md` - signal system, ReadSignals pattern, PatchElements/PatchSignals
- `07-event-architecture.md` - event sourcing, projection pipelines, CQRS
- `~/.claude/skills/preferences-data-modeling/SKILL.md` - DuckDB/DuckLake patterns, materialized views, scientific data contracts
- `~/.claude/skills/preferences-rust-development/SKILL.md` - Rust-specific patterns for axum integration
- `~/.claude/skills/preferences-scalable-probabilistic-modeling-workflow/SKILL.md` - section 06 defines the diagnostic artifacts (simulation ensembles, posterior samples, calibration tables) that this serving pipeline delivers to visualization tools
