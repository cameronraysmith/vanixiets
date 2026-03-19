---
name: preferences-data-modeling
description: Data modeling conventions including Arrow-based columnar interchange, DuckDB/DuckLake lakehouse patterns, SQLMesh transformations, and scientific data contracts. Load when designing database structures, data pipelines, cross-language analytics, or data relationships.
---

# Data modeling

## Scope and purpose

This document covers data modeling for data pipelines and analytics using Apache Arrow as the in-memory interchange format, DuckDB as the query engine, DuckLake for lakehouse catalog management, and SQLMesh for data transformation and build orchestration.

What this document covers:
- Arrow columnar format as the interoperability substrate across language runtimes
- Cross-language DuckDB bindings producing Arrow record batches
- Data warehouse schemas and transformations via SQLMesh
- DuckLake operational patterns and remote data access
- Columnar format evolution (Parquet, Vortex, Lance)
- Data quality checks, validation, and scientific data contracts
- Semantic layers and metrics
- Pipeline orchestration patterns

What this document does not cover:
- Application domain modeling (see domain-modeling.md)
- Business logic workflows
- State machines for entity lifecycles
- Smart constructors for domain types

The key distinction is that this document is about modeling data at rest (tables, schemas, metrics) and data in motion (Arrow record batches, IPC, cross-language interchange) while domain-modeling.md is about modeling domain logic (entities, workflows, state transitions).

For application domain modeling using functional programming patterns, see:
- domain-modeling.md for core patterns (smart constructors, state machines, workflows, aggregates)
- architectural-patterns.md for application structure (onion architecture, dependency injection)

## Foundational principles

### Type safety

Data schemas are contracts.
Treat them as type signatures that make implicit assumptions explicit.

- Use Pydantic schemas for data validation at ingestion boundaries
- Define explicit column types in all model definitions (avoid `SELECT *`)
- Document grain (primary keys) as part of the model contract
- Implement audit checks (uniqueness, not-null constraints) as executable type constraints
- Leverage schema evolution capabilities for non-breaking changes only
- Test schema changes in isolated environments before applying to production

### Functional patterns

Data transformations should behave as pure functions where practical.

- Treat SQL views and models as lazily-evaluated pure functions
- Use immutable data files (Parquet via DuckLake or similar formats)
- Make state changes explicit through snapshots and time travel capabilities
- Isolate side effects at pipeline boundaries (ingestion, egress)
- Prefer composition over inheritance in metric and model definitions
- Document data lineage as function composition chains

### Immutability and append-only patterns

Once written, data files should never be modified in place.

- Use append-only data files for all raw and processed data
- Implement updates through delete-insert patterns at partition boundaries
- Maintain historical snapshots for reproducibility and debugging
- Version all schema and model definitions in source control
- Treat data deletions as tombstone markers rather than physical removal where compliance allows

## Schema management

### Evolution principles

Schema changes should be transactional and backward-compatible when possible.

- Use transactional DDL for all schema modifications
- Document breaking vs non-breaking changes explicitly
- Employ column-level lineage tracking for impact analysis
- Test schema changes in virtual or development environments first
- Plan migration paths for breaking changes
- Maintain schema documentation alongside code

### Validation at boundaries

Validate data shape and constraints at system boundaries.

- Implement validation at ingestion points (before data enters the lake)
- Use Pydantic or similar libraries for runtime type checking in Python
- Define data quality checks as executable contracts
- Fail fast on validation errors rather than propagating bad data
- Log validation failures for debugging and monitoring
- Consider partial validation for streaming scenarios (LLM outputs, etc.)

### Type-driven design with ADTs

For comprehensive guidance on modeling domain types and error handling, see:

- `~/.claude/skills/preferences-algebraic-data-types/SKILL.md` — sum types (discriminated unions), product types, newtype pattern, making illegal states unrepresentable
- `~/.claude/skills/preferences-railway-oriented-programming/SKILL.md` — Result types, bind/apply composition, effect signatures, two-track model

Key principles from ADT design:
- Use sum types (ENUMs, discriminated unions) to model "OR" relationships
- Use product types (records, tables) to model "AND" relationships
- Wrap primitives in newtypes to prevent semantic confusion (UserId vs OrderId)
- Design schemas so illegal states cannot be represented
- Use Result<T, E> for operations that can fail
- Distinguish bind (sequential, short-circuit) from apply (parallel, collect errors)

## Incremental processing patterns

### Time-partitioned models

When processing event data, partition by time to enable efficient incremental updates.

- Use `INCREMENTAL_BY_TIME_RANGE` or equivalent patterns for time-series data
- Configure lookback windows to handle late-arriving data gracefully
- Document time columns and partition granularity explicitly
- Implement idempotent transformations (delete + insert within partition)
- Track processing state explicitly (watermarks, snapshots)
- Test backfill and reprocessing scenarios

### State tracking

Make data pipeline state explicit and queryable.

- Maintain processing metadata (last processed timestamp, record counts)
- Use snapshots for point-in-time recovery
- Implement time travel for debugging and rollback
- Track data lineage and transformation history
- Version control pipeline definitions and state schemas

For modeling pipeline execution states (Pending, Running, Completed, Failed), consider using state machine patterns from domain-modeling.md's state machines for entity lifecycles section.
This applies to job status tracking, data quality checks, and orchestration workflows.

## Semantic layer patterns

### Logical vs physical separation

Separate business logic (metrics, dimensions) from physical storage schema.

- Define metrics once in version-controlled configuration (YAML, SQL)
- Abstract physical table structure behind logical views
- Enable ad-hoc query composition without pre-aggregation
- Use semantic definitions as documentation and contracts
- Maintain metric lineage and dependencies explicitly
- Test metrics in isolation from physical implementation

### Metric composition

Build complex metrics from simpler, reusable components.

- Define base metrics as atomic units
- Compose derived metrics from base metrics with explicit dependencies
- Document metric calculation logic alongside definitions
- Version metrics and track breaking changes
- Validate metric consistency across different tools and interfaces

## Arrow as interoperability substrate

Apache Arrow is the in-memory columnar format that makes DuckDB zero-copy across language runtimes.
This is the foundational architectural choice connecting the query engine (DuckDB), on-disk storage (Parquet and its successors), and computational consumers across Python, Julia, and Rust.

Arrow record batches serve as the universal in-memory interchange format.
DuckDB query results are natively Arrow-backed through the C Data Interface, which means results cross language boundaries without serialization or copying.
Parquet files memory-map to Arrow with predicate pushdown, so the transition from storage to compute avoids unnecessary materialization.
Arrow IPC enables efficient cross-process and cross-language data transfer, and GPU streaming via Arrow IPC or GDS/KvikIO saturates GPU compute without CPU-side bottlenecks.

The practical consequence is that any consumer that speaks Arrow — whether a Python dataframe library, a Julia differential equations solver, or a Rust web server — can receive query results from DuckDB with zero intermediate representation.
This makes Arrow the lingua franca of the analytics stack rather than a format choice for any single language ecosystem.

### Cross-language DuckDB bindings

DuckDB provides first-class bindings that all produce Arrow record batches through the same C Data Interface.
The bindings vary in maturity and ecosystem integration but share the same zero-copy Arrow output path.

- Python: `duckdb` package, the most mature binding with tight pandas and polars integration
- Julia: `DuckDB.jl` (source at `~/projects/duckdb/tools/juliapkg`), enabling Julia's SciML ecosystem (DiffEq.jl, Lux.jl, KernelAbstractions.jl) to consume lakehouse data directly as Arrow record batches
- Rust: `duckdb-rs` (`~/projects/omicslake-workspace/duckdb-rs`) for embedded analytics, and `async-duckdb` (`~/projects/rust-workspace/async-duckdb`) for async web application serving via axum

All three language ecosystems benefit equally from the DuckDB-to-Arrow pipeline.
A single DuckLake catalog can serve Python notebooks running probabilistic inference, Julia processes solving differential equations, and Rust services delivering query results over HTTP — all consuming the same Arrow record batches without format translation.

## DuckDB and DuckLake patterns

Read models and materialized views in analytics architectures form a Galois connection with the underlying event log or source data.
The projection from events to views is information-lossy but composable; views are quotients of the source data under an equivalence relation.
Query caching is memoization over the query profunctor, with cache invalidation governed by naturality conditions.
DuckLake's time-travel capability implements temporal versioning as indexed types, connecting to the bitemporal semantics described in event sourcing.
See `theoretical-foundations.md` section "Materialized views as Galois connections" for the formal algebraic model.

### Metadata management

Store catalog metadata in SQL databases, not file-based catalogs.

- Use DuckLake or similar for lakehouse patterns with full ACID support
- Store all table metadata (schemas, snapshots, statistics) in relational catalogs
- Leverage transactional guarantees for atomic updates
- Query metadata tables directly for lineage and governance
- Avoid complex file-based metadata (JSON, Avro manifests) where possible

### Query optimization

Leverage DuckDB's strengths for analytical workloads.

- Use Parquet for columnar storage with compression
- Push down predicates and projections to file scans
- Leverage partition pruning through statistics
- Query data where it lives to reduce data movement
- Use inline data storage for small, frequently-changing tables
- Profile queries to identify bottlenecks

### Local development to production

Bridge local DuckDB development with production deployments.

- Develop and test locally with DuckDB files or in-memory databases
- Use consistent SQL dialect between local and production environments
- Deploy to cloud environments (Fabric, MotherDuck) with minimal code changes
- Maintain parity between local and production data samples
- Test incremental logic locally before scheduling in production

### DuckLake operational patterns

DuckLake provides ACID transactions without running a database server, implementing an embedded lakehouse pattern where the catalog is a DuckDB database and data lives in columnar files.

Zero-copy table registration via `CREATE TABLE ... WITH NO DATA` registers external schemas without materializing data, which is useful for schema-only integration with existing Parquet file collections.
The `DATA_PATH` sentinel controls where materialized data lives, separating catalog state from data storage location.
The `ducklake:hf://` protocol enables direct catalog access to HuggingFace-hosted datasets.

For SQLMesh integration, use a separate DuckLake state connection to keep the transformation engine's internal state isolated from the catalog being built.
This avoids contention between SQLMesh's plan/apply lifecycle and DuckLake's ACID transactions on the same catalog.

### httpfs and remote data access

DuckDB's httpfs extension enables predicate pushdown over remote Parquet files, meaning only the relevant row groups and columns are transferred over the network.
The `hf://` protocol provides native access to HuggingFace Hub datasets without downloading full files locally.

This enables server-side DuckDB architectures where a web application queries remote DuckLake catalogs and streams Arrow record batches to clients, avoiding the need for browsers or client applications to download full datasets.
Combined with DuckLake's catalog metadata, the query planner can prune partitions and push predicates before any data crosses the network boundary.

### Format evolution

Parquet is the current standard on-disk columnar format and the default for DuckLake data storage.
Two emerging formats extend the columnar ecosystem in complementary directions.

Vortex (`~/projects/omicslake-workspace/vortex`) is an emerging successor to Parquet with improved compression and query performance.
DuckDB already supports native Vortex read and write, though DuckLake's catalog implementation does not yet support Vortex as a storage backend.

Lance (used by `~/projects/omicslake-workspace/slaf`) is an Arrow-native format optimized for ML and vector workloads.
DuckDB supports Lance via extension, and Lance files are lakehouse-compatible.

The practical stance is Parquet today, with Vortex and Lance as they mature.
DuckDB's native support for all three formats means the transition is transparent to query consumers — the Arrow record batches they receive are identical regardless of which on-disk format backs the data.

## SQLMesh integration

### Model kinds and patterns

Choose appropriate model kinds for different use cases.

- `SEED` - for static reference data loaded from files
- `INCREMENTAL_BY_TIME_RANGE` - for time-partitioned event data
- `VIEW` - for logical transformations without materialization
- `FULL` - for complete refresh of derived tables
- Document rationale for model kind selection

### Virtual environments and testing

Test changes safely before affecting production.

- Use virtual environments to preview changes
- Run audits and tests before applying plans
- Validate data quality in isolated environments
- Enable column-level lineage for impact analysis
- Roll back changes atomically if issues arise

### Audit and governance

Build data quality checks into model definitions.

- Define audits as executable contracts (unique, not-null, ranges)
- Document grain (primary keys) explicitly in model metadata
- Track model dependencies and lineage
- Version models and track breaking changes
- Implement continuous testing for data quality

## Scientific data contract patterns

Data artifacts from scientific and computational workflows benefit from columnar storage and DuckDB queryability when they follow consistent structural conventions.

Simulation ensembles produce millions of (parameter, observation) pairs where observations may be variable-length time series.
Arrow list and struct columns naturally represent these variable-length trajectories without flattening to a fixed grid, and DuckDB's nested type support means the data is directly queryable without denormalization.

Diagnostic tables — SBC ranks, z-scores, contractions, calibration metrics — are inherently tabular with one row per (dataset_id, parameter).
These are the simplest case: flat columnar tables that DuckDB processes efficiently and that translate directly to diagnostic visualizations.

Posterior samples are tabular with (sample_id, parameter columns), directly queryable for summary statistics, quantiles, and convergence diagnostics.
Storing these as Parquet partitioned by model version enables time-travel queries across model iterations.

Model provenance registries track which artifacts belong to which model version: (model_version, ensemble_path, approximator_path, timestamp, invalidated_by).
This is the metadata layer that connects simulation outputs, trained approximators, and diagnostic results into a queryable lineage graph.

Experimental design sweep results follow the pattern (design_config, parameter, metric_value), enabling cross-configuration queries to identify which experimental designs yield the best inference performance.

See `preferences-scalable-probabilistic-modeling-workflow` section 06 for diagnostic threshold definitions and paradigm-specific applicability.

## Current data hosting stack

The concrete operational stack consists of three components: SQLMesh for data build and transformation, DuckDB with DuckLake for catalog management and query, and HuggingFace Hub with git-xet/git-lfs for data hosting and distribution.
This combination provides a serverless lakehouse where the catalog is a DuckDB file, data lives in Parquet on HuggingFace, and SQLMesh manages the transformation DAG.

Data ingestion (dlt) and workflow orchestration (Dagster) are plausible future additions that could become relevant under certain operational contexts.
Neither is part of the current operational stack, and their adoption would depend on whether ingestion complexity or scheduling requirements exceed what SQLMesh provides natively.

## Composability and modularity

### Reusable transformations

Build libraries of reusable data transformations.

- Extract common logic into views or utility models
- Parameterize transformations where appropriate
- Document inputs, outputs, and assumptions
- Test transformations in isolation
- Version transformation logic separately from business rules

### Cross-tool consistency

Ensure metrics and logic remain consistent across tools.

- Define metrics in a central semantic layer
- Use the same SQL dialect across tools where possible
- Share schema definitions between validation and transformation code
- Test metric calculations across different interfaces
- Document expected behavior and edge cases

## Best practices summary

When modeling data, prioritize:

1. Explicit contracts — schemas, types, and constraints as documentation
2. Immutability — append-only patterns and versioning
3. Composability — building complex models from simple, reusable components
4. Testability — validating transformations in isolation
5. Lineage — tracking data flow from source to consumption
6. Type safety — leveraging type systems to catch errors early
7. Transactionality — ACID guarantees for consistency
8. Separation of concerns — logical models separate from physical storage
9. Arrow interchange — zero-copy columnar format as the universal data handoff between languages and processes

Remember that in the ideal case, data pipelines should behave as a monad transformer stack where side effects are explicit in signatures and isolated at boundaries to preserve compositionality.

For concrete implementation patterns see ~/.claude/skills/preferences-railway-oriented-programming/SKILL.md (Result types, bind/apply, effect signatures) and ~/.claude/skills/preferences-algebraic-data-types/SKILL.md (domain modeling with sum/product types).
