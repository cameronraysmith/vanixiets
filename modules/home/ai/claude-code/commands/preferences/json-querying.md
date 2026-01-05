# JSON querying

## Tool selection

Choose the right tool based on your task's characteristics.

| Task | Prefer | Reason |
|------|--------|--------|
| Aggregations, joins, window functions | DuckDB | Full SQL analytical capabilities |
| Multi-file queries, cross-format joins | DuckDB | Native Parquet/CSV/JSON interop |
| Tabular output for analysis | DuckDB | Columnar result formatting |
| Extract/transform/filter → JSON output | jaq | Preserves JSON structure naturally |
| Unix pipelines, curl piping | jaq | Composable streaming, fast startup |
| Recursive key search in nested structures | jaq | `..` operator for recursive descent |
| In-place JSON modification | jaq | Update operators (`|=`, `//=`) |
| Memory-constrained streaming | jaq | Line-by-line NDJSON processing |

### Decision heuristic

Use DuckDB when you think in SQL (SELECT, GROUP BY, JOIN).
Use jaq when you think in transformations (map, filter, reshape).

## DuckDB JSON patterns

### Basic querying

DuckDB reads JSON files directly with automatic schema inference:

```sql
-- Auto-infer schema
SELECT * FROM read_json_auto('data.json');

-- Shorthand syntax
SELECT * FROM 'data.json';

-- Query remote JSON
SELECT * FROM read_json('https://api.example.com/data.json');
```

### Nested structure handling

Unnest arrays and access nested fields using SQL:

```sql
-- Unnest array field
WITH events AS (
    SELECT unnest(domainEvents) as event
    FROM read_json_auto('workflow.json')
)
SELECT
    event.id::VARCHAR as id,
    event.description::VARCHAR as description,
    event.version::INT as version
FROM events;

-- Access nested paths
SELECT
    json_extract(data, '$.user.email') as email,
    json_extract(data, '$.items[0].name') as first_item
FROM read_json_auto('nested.json');
```

### Aggregations on JSON

SQL analytical functions work directly on JSON data:

```sql
SELECT
    type,
    COUNT(*) as count,
    AVG(json_extract(data, '$.duration')::DOUBLE) as avg_duration
FROM read_json_auto('events/*.json')
GROUP BY type
ORDER BY count DESC;
```

### Cross-format joins

Join JSON with other formats without intermediate steps:

```sql
SELECT
    j.id,
    j.name,
    c.category_name,
    p.metrics
FROM read_json_auto('entities.json') j
JOIN read_csv_auto('categories.csv') c ON j.category_id = c.id
JOIN read_parquet('metrics.parquet') p ON j.id = p.entity_id;
```

### Output formats

Control output format from CLI:

```bash
# JSON array output
duckdb -json -c "SELECT * FROM 'data.json' LIMIT 10"

# Newline-delimited JSON
duckdb -c ".mode jsonlines" -c "SELECT * FROM 'data.json'"

# Export query results
duckdb -c "COPY (SELECT * FROM 'data.json' WHERE active) TO 'filtered.json'"
```

## jaq patterns

jaq is a Rust reimplementation of jq, 5-10x faster with identical syntax.

### Basic extraction

```bash
# Extract field
jaq '.name' data.json

# Extract from array
jaq '.items[].id' data.json

# Multiple fields
jaq '{id, name, status}' data.json
```

### Filtering and selection

```bash
# Filter array elements
jaq '.events[] | select(.status == "active")' data.json

# Filter with multiple conditions
jaq '.items[] | select(.price > 100 and .inStock == true)' data.json

# Null-safe access
jaq '.optional?.nested?.field // "default"' data.json
```

### Transformation

```bash
# Reshape structure
jaq '{
  id: .id,
  fullName: "\(.firstName) \(.lastName)",
  tags: [.categories[].name]
}' data.json

# Map over arrays
jaq '.items | map({id, displayName: .name | ascii_upcase})' data.json

# Flatten nested arrays
jaq '[.groups[].members[]] | unique' data.json
```

### Recursive descent

Find keys anywhere in nested structures:

```bash
# Find all "id" fields at any depth
jaq '.. | .id? // empty' deeply-nested.json

# Find all objects with specific key
jaq '.. | select(.type? == "error")' logs.json
```

### In-place updates

Modify JSON while preserving structure:

```bash
# Update field
jaq '.version |= . + 1' config.json

# Add field
jaq '.metadata.updatedAt = "2025-01-05"' data.json

# Delete field
jaq 'del(.internal)' data.json

# Conditional update
jaq '(.items[] | select(.status == "pending")).status = "processed"' data.json
```

### Pipeline composition

jaq composes naturally with Unix tools:

```bash
# API response processing
curl -s api.example.com/events | jaq '.data[] | select(.severity == "high") | .id'

# Multi-stage transformation
jaq '.raw' input.json | jaq 'map(select(.valid))' | jaq 'sort_by(.timestamp)'

# Combine with other tools
jaq -r '.items[].url' data.json | xargs -P4 curl -s
```

### Streaming NDJSON

Process large newline-delimited JSON without loading into memory:

```bash
# Filter streaming logs
jaq 'select(.level == "error")' massive.ndjson

# Extract and count
jaq '.event_type' events.ndjson | sort | uniq -c | sort -rn
```

## Common recipes

### Inspect JSON structure

```bash
# DuckDB: show inferred schema
duckdb -c "DESCRIBE SELECT * FROM 'data.json'"

# jaq: show top-level keys
jaq 'keys' data.json

# jaq: show structure with types
jaq 'paths | map(tostring) | join(".")' data.json | head -20
```

### Count and summarize

```bash
# DuckDB: count by field
duckdb -c "SELECT type, COUNT(*) FROM 'events.json' GROUP BY type"

# jaq: count array length
jaq '.items | length' data.json

# jaq: group and count
jaq 'group_by(.type) | map({type: .[0].type, count: length})' data.json
```

### Extract unique values

```bash
# DuckDB
duckdb -c "SELECT DISTINCT category FROM 'products.json'"

# jaq
jaq '[.products[].category] | unique' data.json
```

### Flatten nested arrays

```bash
# DuckDB
duckdb -c "
    SELECT unnest(tags) as tag, COUNT(*) as count
    FROM read_json_auto('items.json')
    GROUP BY tag
"

# jaq
jaq '[.items[].tags[]] | group_by(.) | map({tag: .[0], count: length})' data.json
```

### Join data from multiple files

```bash
# DuckDB: SQL join
duckdb -c "
    SELECT a.*, b.details
    FROM 'main.json' a
    JOIN 'lookup.json' b ON a.ref_id = b.id
"

# jaq: manual join using INDEX
jaq -s '
    (.[1] | INDEX(.id)) as \$lookup |
    .[0].items | map(. + {details: \$lookup[.ref_id].details})
' main.json lookup.json
```

## Performance considerations

### DuckDB strengths

DuckDB excels when:
- Query touches subset of columns (columnar storage)
- Aggregations span large datasets
- Multiple queries against same data (keeps schema cached)
- Complex joins or window functions needed

### jaq strengths

jaq excels when:
- Processing many small files (5ms startup vs DuckDB's overhead)
- Streaming large NDJSON (constant memory)
- Output must remain valid JSON
- Simple transformations in shell pipelines

### Large file strategies

For files over 100MB:
- DuckDB: use explicit schema for faster parsing
- jaq: prefer NDJSON format for streaming
- Both: consider converting to Parquet for repeated queries

```bash
# Convert JSON to Parquet for repeated analysis
duckdb -c "COPY (SELECT * FROM 'large.json') TO 'large.parquet'"

# Then query Parquet (much faster)
duckdb -c "SELECT * FROM 'large.parquet' WHERE condition"
```

## Tool availability

Both tools are available in the nix configuration:
- `duckdb` via `database-packages.nix`
- `jaq` via `development-packages.nix`
- `jq` via `programs.jq.enable` (jaq is drop-in compatible)

jaq uses identical syntax to jq but runs 5-10x faster.
Existing jq scripts work with jaq without modification.
