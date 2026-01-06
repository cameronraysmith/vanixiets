---
argument-hint: <qlerify-json-export-path>
description: Transform Qlerify JSON export to EventCatalog MDX artifacts
---

Transform a Qlerify Event Modeling JSON export into EventCatalog-compatible MDX artifacts with JSON Schema.

This command loads all relevant preferences for: Qlerify to EventCatalog transformation workflow, EventCatalog tooling (schema documentation), json querying (duckdb, jaq), functional domain modeling (DDD aggregates, Decider pattern), and schema versioning.

## Prerequisites

1. Qlerify JSON export file from Event Modeling session
2. Target EventCatalog project directory (or will create structure)

## Workflow

### Phase 1: Export Discovery

If $ARGUMENTS provided, use that as the JSON export path.
Otherwise, ask user to provide the path to the Qlerify JSON export.

Use discovery queries to understand export structure:
```bash
jaq 'keys' export.json
jaq '[.domainEvents[].cards[].cardType.domainModelRole] | group_by(.) | map({role: .[0], count: length})' export.json
jaq '.lanes | map(.name)' export.json
```

### Phase 2: Structure Analysis

Analyze with duckdb for relationships:
- Count entities by type (Command, Query, Entity)
- Analyze event flow depth (parent chains)
- Check lane distribution (events per service)
- Identify schema field complexity

### Phase 3: EventCatalog Generation

Generate MDX artifacts for each domain element:

**Events** (from domainEvents with orange cards):
```
/events/[EventName]/index.mdx
/events/[EventName]/schema.json
```

**Commands** (from Command role cards):
```
/commands/[CommandName]/index.mdx
/commands/[CommandName]/schema.json
```

**Queries** (from ReadModel role cards):
```
/queries/[QueryName]/index.mdx
/queries/[QueryName]/schema.json
```

**Services** (from lanes/bounded contexts):
```
/services/[ServiceName]/index.mdx
```

**Flows** (from event parent relationships):
```
/flows/[FlowName]/index.mdx
```

### Phase 4: Schema Generation

For each entity with fields, generate JSON Schema:
- Map Qlerify data types to JSON Schema types
- Include required fields based on primaryKey
- Add relationship references via $ref
- Include enum values from exampleData

### Phase 5: Validation

Verify generated artifacts:
- All events have corresponding MDX files
- All commands reference valid events
- All schemas are valid JSON Schema
- Flow steps maintain temporal ordering

## Output Structure

```
eventcatalog/
├── events/
│   └── [EventName]/
│       ├── index.mdx
│       └── schema.json
├── commands/
│   └── [CommandName]/
│       ├── index.mdx
│       └── schema.json
├── queries/
│   └── [QueryName]/
│       └── index.mdx
├── services/
│   └── [ServiceName]/
│       └── index.mdx
└── flows/
    └── [FlowName]/
        └── index.mdx
```

## User Input

$ARGUMENTS
