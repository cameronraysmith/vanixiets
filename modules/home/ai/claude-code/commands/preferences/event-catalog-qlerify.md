# Qlerify to EventCatalog transformation

## Purpose

This document provides a self-contained workflow for transforming Qlerify Event Modeling JSON exports into EventCatalog-compatible MDX artifacts with JSON Schema.
The transformation preserves algebraic structure from Event Modeling (events as free monoid elements, commands as validated functions, aggregates as Deciders) while generating discoverable documentation.
Use this document as automatically loaded context when working with Qlerify exports or invoke it as a slash command when beginning transformation work.

## Relationship to other documents

Cross-reference `json-querying.md` for duckdb and jaq query patterns used during structure discovery and extraction.
The transformation phase uses both tools: duckdb for analytical queries (aggregations, counts, relationship analysis) and jaq for structural extraction and JSON reshaping.

Cross-reference `event-catalog-tooling.md` for EventCatalog concepts, algebraic foundations (Decider pattern, free monoid events, module algebra services), and anti-patterns to avoid when generating catalog entries.
The output of this transformation workflow populates an EventCatalog that documents the algebraic structure discovered through Event Modeling.

Cross-reference `schema-versioning.md` for JSON Schema evolution strategies when extending generated schemas beyond initial transformation.

## Qlerify JSON structure

Qlerify exports Event Modeling boards as JSON with the following top-level structure:

```json
{
  "id": "export-uuid",
  "name": "Board Name",
  "version": "1.0.0",
  "domainEvents": [],    // event nodes with embedded cards
  "schemas": [],         // Command/Query/Entity schemas
  "lanes": [],           // swim lanes (service boundaries)
  "boundedContexts": [], // typically empty in current exports
  "groups": []           // visual grouping metadata
}
```

Each `domainEvent` represents a node in the Event Modeling flow and contains:

```json
{
  "id": "event-uuid",
  "description": "Event Past Tense Name",
  "type": "bpmn:Task",
  "laneId": "lane-uuid",
  "parents": ["parent-event-uuid"],  // temporal dependencies
  "cards": [                         // embedded colored cards
    {
      "cardType": {
        "domainModelRole": "Command|AggregateRoot|ReadModel|GivenWhenThen|null",
        "color": "#hex"
      },
      "text": "Card title",
      "schemaId": "schema-uuid-or-null"
    }
  ]
}
```

Card types by domain model role:

| Role | Color | Purpose | Schema Type | EventCatalog Target |
|------|-------|---------|-------------|---------------------|
| Command | Blue | Imperative action request | Command schema | Command |
| AggregateRoot | Yellow | Consistency boundary | Entity schema | Entity (aggregateRoot: true) |
| ReadModel | Green | Query projection | Query schema | Query |
| GivenWhenThen | Purple | Behavior specification | none | Flow step summary (markdown) |
| null (UserStory) | Pink | Actor context | none | Flow step actor |

Schema objects provide type definitions:

```json
{
  "id": "schema-uuid",
  "name": "SchemaName",
  "type": "Command|Query|Entity",
  "entityId": "card-uuid",
  "boundedContext": null,
  "fields": [
    {
      "name": "fieldName",
      "dataType": "uuid|timestamp|int|boolean|string|enum|null",
      "primaryKey": true,
      "cardinality": "one-to-one|one-to-many|many-to-one|many-to-many",
      "relatedEntityId": "entity-schema-uuid-or-null",
      "exampleData": ["value1", "value2"]  // for enums
    }
  ]
}
```

Lanes define service boundaries:

```json
{
  "id": "lane-uuid",
  "name": "LaneName",
  "offset": 0
}
```

Parent-child relationships in the `parents[]` array establish temporal flow, enabling sequential ordering of events into flow steps.

## Discovery queries

Use these queries to understand the structure of an unknown Qlerify export before beginning transformation.

### duckdb exploration

Inspect overall structure and relationships:

```sql
-- Count entities by type
SELECT
    s.type,
    COUNT(*) as count
FROM read_json_auto('export.json') AS root,
    unnest(root.schemas) AS s
GROUP BY s.type
ORDER BY count DESC;

-- Analyze event flow depth (parent chains)
WITH RECURSIVE events AS (
    SELECT
        e.id::VARCHAR as event_id,
        e.description::VARCHAR as description,
        len(e.parents) as parent_count
    FROM read_json_auto('export.json') AS root,
        unnest(root.domainEvents) AS e
)
SELECT
    parent_count,
    COUNT(*) as events_with_this_depth
FROM events
GROUP BY parent_count
ORDER BY parent_count;

-- Find orphaned schemas (no card reference)
SELECT
    s.id::VARCHAR as schema_id,
    s.name::VARCHAR as schema_name,
    s.type::VARCHAR as schema_type
FROM read_json_auto('export.json') AS root,
    unnest(root.schemas) AS s
WHERE s.entityId::VARCHAR NOT IN (
    SELECT c.schemaId::VARCHAR
    FROM unnest(root.domainEvents) AS e,
        unnest(e.cards) AS c
    WHERE c.schemaId IS NOT NULL
);

-- Lane distribution (events per service)
SELECT
    l.name::VARCHAR as lane_name,
    COUNT(e.id) as event_count
FROM read_json_auto('export.json') AS root,
    unnest(root.lanes) AS l
LEFT JOIN unnest(root.domainEvents) AS e ON e.laneId::VARCHAR = l.id::VARCHAR
GROUP BY l.name
ORDER BY event_count DESC;

-- Schema field complexity (average fields per schema type)
SELECT
    s.type::VARCHAR as schema_type,
    COUNT(DISTINCT s.id) as schema_count,
    AVG(len(s.fields)) as avg_fields,
    MAX(len(s.fields)) as max_fields
FROM read_json_auto('export.json') AS root,
    unnest(root.schemas) AS s
GROUP BY s.type;
```

### jaq exploration

Inspect structure and extract metadata:

```bash
# Top-level keys to understand export format version
jaq 'keys' export.json

# Card type distribution by role
jaq '[.domainEvents[].cards[].cardType.domainModelRole] |
     group_by(.) |
     map({role: .[0], count: length})' export.json

# Schema types and names
jaq '.schemas | map({type: .type, name: .name}) |
     group_by(.type) |
     map({type: .[0].type, schemas: map(.name)})' export.json

# Lane names (future service names)
jaq '.lanes | map(.name)' export.json

# Events with no parents (flow entry points)
jaq '[.domainEvents[] | select(.parents | length == 0) | .description]' export.json

# Events with multiple parents (flow joins)
jaq '[.domainEvents[] | select(.parents | length > 1) |
     {event: .description, parent_count: (.parents | length)}]' export.json

# Schema fields requiring type inference (null dataType)
jaq '.schemas[] |
     select(.fields[] | .dataType == null) |
     {schema: .name, fields_needing_inference: [.fields[] | select(.dataType == null) | .name]}' export.json

# Enum fields with example data
jaq '.schemas[].fields[] |
     select(.dataType == "enum") |
     {field: .name, values: .exampleData}' export.json
```

## Entity mapping rules

Map Qlerify elements to EventCatalog types according to this consolidated specification:

| Qlerify Element | EventCatalog Type | Location Pattern | Notes |
|-----------------|-------------------|------------------|-------|
| Lane | Service | `domains/{domain}/services/{service-id}/` | One service per lane, PascalCase ID from lane name |
| domainEvent.description | Event name | `services/{service-id}/events/{event-id}/` | Past tense, extract from containing event |
| Command card + schema | Command | `services/{service-id}/commands/{command-id}/` | Blue card, schema.type = "Command" |
| AggregateRoot card + schema | Entity | `domains/{domain}/entities/{entity-id}/` | Yellow card, schema.type = "Entity", aggregateRoot: true |
| ReadModel card + schema | Query | `services/{service-id}/queries/{query-id}/` | Green card, schema.type = "Query" |
| GivenWhenThen card | Flow step summary | Embedded in flow step markdown | Purple card, no schema |
| UserStory card (role: null) | Flow step actor | Flow step actor field | Pink card, no schema |
| parent-child chain | Flow steps | `domains/{domain}/flows/{flow-id}/` | Sequential ordering via parents[] array |
| export root | Domain | `domains/{domain-id}/` | Single domain per export |

Naming conventions for generated IDs:

| Element | ID Convention | Example |
|---------|---------------|---------|
| Domain | kebab-case from name | `data-ingestion` |
| Service | PascalCase from lane.name + "Service" | `AutomationService` |
| Event | PascalCase from domainEvent.description | `InventoryReserved` |
| Command | PascalCase from schema.name | `ReserveInventory` |
| Query | PascalCase from schema.name | `GetInventoryStatus` |
| Entity | PascalCase from schema.name | `Inventory` |
| Flow | kebab-case from description | `reserve-and-confirm-flow` |

## Schema translation rules

Translate Qlerify schema fields to JSON Schema draft-07 according to these condensed rules from `schema-translation-quick-reference.md`:

### Type mapping

| Qlerify dataType | JSON Schema type | JSON Schema format | Notes |
|------------------|------------------|-------------------|-------|
| uuid | string | uuid | High-confidence identifier |
| timestamp | string | date-time | ISO 8601 timestamp |
| int | integer | - | Whole numbers |
| boolean | boolean | - | true/false |
| string | string | - | Text data |
| enum | string | - | Plus `enum: []` array from exampleData |
| null (missing) | (inferred) | (inferred) | Apply field name pattern matching |

### Field name inference patterns

When `dataType: null`, infer types from field name patterns:

| Pattern | Inferred Type | Format | Confidence |
|---------|---------------|--------|-----------|
| `*Id`, `*ID`, `id` | string | uuid | high |
| `*At`, `*Date`, `*Time`, `created*`, `updated*` | string | date-time | high |
| `is*`, `has*`, `can*`, `*Flag` | boolean | - | high |
| `*Count`, `*Quantity`, `*Number`, `*Index` | integer | - | medium |
| `*Amount`, `*Price`, `*Total`, `*Rate` | number | - | medium |
| `email`, `*Email` | string | email | high |
| `url`, `*Url`, `*URL`, `*Link` | string | uri | high |
| `phone`, `*Phone` | string | - | medium |
| `status`, `state`, `*Status`, `*State` | string | - | low (check for enum) |

Generate warnings for medium/low confidence inferences and include them in schema descriptions.

### Required field determination

| Condition | Required? | Notes |
|-----------|-----------|-------|
| `primaryKey: true` | yes | Always required |
| `cardinality: "one-to-one"` | yes | Exactly one relation |
| `cardinality: "one-to-many"` | yes | At least one relation |
| `cardinality: "many-to-one"` | no | Optional foreign key |
| `cardinality: "many-to-many"` | no | Join table handles |
| Field name contains "optional" | no | Explicit marker |
| No metadata (default) | yes | Conservative default |

### JSON Schema template

Generate schemas using this structure:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "urn:qlerify:schema:{type}:{kebab-case-name}",
  "title": "{Original Schema Name}",
  "description": "{Type} schema generated from Qlerify Event Modeling export",
  "type": "object",
  "properties": {
    "{fieldName}": {
      "type": "{json-type}",
      "format": "{format-if-applicable}",
      "description": "{field-description} (source: {confidence-note})",
      "examples": ["{example-value}"]
    }
  },
  "required": ["{required-field-names}"],
  "additionalProperties": false
}
```

Include confidence notes in descriptions:
- Explicit type from Qlerify: `"(source: explicit Qlerify dataType)"`
- High-confidence inference: `"(source: inferred from field name pattern)"`
- Medium-confidence inference: `"(source: inferred with medium confidence - verify)"`
- Low-confidence inference: `"(source: low confidence inference - manual review required)"`

### Enum handling

For fields with `dataType: "enum"`, extract values from `exampleData` array:

```json
{
  "status": {
    "type": "string",
    "enum": ["pending", "confirmed", "cancelled"],
    "description": "Order status (source: enum values from Qlerify examples)",
    "examples": ["pending"]
  }
}
```

Generate high-severity warning if `dataType: "enum"` but `exampleData` is empty or missing.

### Relationship handling

For fields with `relatedEntityId` populated:

```json
{
  "customerId": {
    "type": "string",
    "format": "uuid",
    "description": "References Customer entity (Qlerify entityId: {uuid})"
  }
}
```

Build entity lookup table during transformation to resolve UUIDs to entity names for richer descriptions.

## Transformation workflow

Execute transformation in sequential phases, each building on previous phase outputs.

### Phase 1: Discover structure

Run discovery queries from the "Discovery queries" section to understand:
- How many schemas of each type exist
- Lane distribution and service boundaries
- Event flow depth and complexity
- Fields requiring type inference
- Orphaned schemas or missing relationships

Generate a summary report showing counts, warnings, and structural observations before proceeding to extraction.

### Phase 2: Extract domain

Create the root domain structure.
Since Qlerify exports typically have `boundedContexts: []`, use a single domain derived from export metadata or user input.

Extract domain metadata:

```bash
# Get export name and version
jaq '{name: .name, version: .version, id: .id}' export.json
```

Generate `domains/{domain-id}/index.mdx`:

```yaml
---
id: {kebab-case-name}
name: {Export Name}
version: 1.0.0
summary: Event-driven domain model generated from Qlerify Event Modeling export
owners: []
---

# {Domain Name}

Generated from Qlerify export `{export.name}` version `{export.version}`.

## Services

This domain contains {lane-count} services corresponding to Event Modeling swim lanes.

## Flow

The primary flow consists of {event-count} events organized into sequential steps.
```

### Phase 3: Extract services from lanes

Each lane becomes a service.
Extract lane data and generate service MDX files.

Query for lane-to-event mapping:

```sql
-- duckdb query to map lanes to their events and cards
SELECT
    l.id::VARCHAR as lane_id,
    l.name::VARCHAR as lane_name,
    COUNT(DISTINCT e.id) as event_count,
    list(DISTINCT c.cardType.domainModelRole::VARCHAR) as card_roles
FROM read_json_auto('export.json') AS root,
    unnest(root.lanes) AS l
LEFT JOIN unnest(root.domainEvents) AS e ON e.laneId::VARCHAR = l.id::VARCHAR
LEFT JOIN unnest(e.cards) AS c ON true
GROUP BY l.id, l.name;
```

For each lane, generate `domains/{domain-id}/services/{service-id}/index.mdx`:

```yaml
---
id: {PascalCaseName}Service
name: {Lane Name} Service
version: 0.0.1
summary: Service handling {lane-name} operations in Event Modeling flow
owners: []
sends: []      # populated in later phases
receives: []   # populated in later phases
entities: []   # populated when linking schemas
---

# {Service Name}

Service boundary corresponding to Event Modeling lane "{lane.name}".

## Responsibilities

This service handles {event-count} events in the overall flow.
```

### Phase 4: Extract events from domainEvents

Each domainEvent becomes an Event entity.
Events are named from `domainEvent.description` (past tense).

Query to extract events with their lane associations:

```bash
jaq '.domainEvents | map({
  id: .id,
  name: .description,
  laneId: .laneId,
  parents: .parents
})' export.json
```

For each domainEvent, determine owning service from laneId, then generate `domains/{domain-id}/services/{service-id}/events/{event-id}/index.mdx`:

```yaml
---
id: {PascalCaseDescription}
name: {domainEvent.description}
version: 0.0.1
summary: Event produced when {contextual-description}
producers:
  - {ServiceId}
consumers: []  # populated from parent-child flow analysis
schemaPath: schema.json
---

# {Event Name}

This event is produced by {Service} when {trigger-description}.

## Temporal context

This event follows: {parent-event-names}
This event precedes: {child-event-names}
```

Generate minimal `schema.json` (events typically carry state deltas, not full schemas in Qlerify):

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "urn:qlerify:schema:event:{kebab-event-name}",
  "title": "{EventName}",
  "description": "Event schema (generated, extend as needed)",
  "type": "object",
  "properties": {
    "eventId": {
      "type": "string",
      "format": "uuid",
      "description": "Unique event identifier"
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "Event occurrence timestamp"
    }
  },
  "required": ["eventId", "timestamp"],
  "additionalProperties": true
}
```

Note: Events in Event Modeling boards often don't have explicit schemas in Qlerify exports.
Generate placeholder schemas and mark them for manual extension based on aggregate state requirements.

### Phase 5: Extract commands from Command cards

Filter schemas with `type: "Command"` and their associated cards.

Query to extract command schemas:

```bash
jaq '.schemas | map(select(.type == "Command")) |
     map({
       id: .id,
       name: .name,
       entityId: .entityId,
       fields: .fields
     })' export.json
```

For each command schema, determine owning service from the card's domainEvent.laneId, then generate `domains/{domain-id}/services/{service-id}/commands/{command-id}/index.mdx`:

```yaml
---
id: {SchemaName}
name: {Humanized Schema Name}
version: 0.0.1
summary: Command to {action-description}
producers: []  # inferred from flow (who triggers this command)
consumers:
  - {ServiceId}  # service in lane containing this command's card
schemaPath: schema.json
---

# {Command Name}

Imperative command validated and processed by {Service}.

## Validation

Validation rules enforced before command acceptance (extend based on business rules).
```

Generate `schema.json` using type translation rules:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "urn:qlerify:schema:command:{kebab-command-name}",
  "title": "{SchemaName}",
  "description": "Command schema generated from Qlerify",
  "type": "object",
  "properties": {
    // Map each field from schema.fields[] using type mapping table
  },
  "required": [
    // Fields marked required per required field determination rules
  ],
  "additionalProperties": false
}
```

### Phase 6: Extract queries from ReadModel cards

Filter schemas with `type: "Query"` and their associated ReadModel cards.

Query pattern identical to commands but filtering for `type: "Query"`:

```bash
jaq '.schemas | map(select(.type == "Query")) |
     map({
       id: .id,
       name: .name,
       entityId: .entityId,
       fields: .fields
     })' export.json
```

Generate `domains/{domain-id}/services/{service-id}/queries/{query-id}/index.mdx`:

```yaml
---
id: {SchemaName}
name: {Humanized Schema Name}
version: 0.0.1
summary: Query to retrieve {data-description}
producers:
  - {ServiceId}  # service providing the read model
consumers: []    # services consuming this query
schemaPath: schema.json
---

# {Query Name}

Read model query exposing projection of event-sourced state.

## Projection

This query returns data projected from events: {related-events}.
```

Generate `schema.json` using identical type translation as commands.

### Phase 7: Extract entities from AggregateRoot cards

Filter schemas with `type: "Entity"` and their associated AggregateRoot cards.

Query to extract entity schemas:

```bash
jaq '.schemas | map(select(.type == "Entity")) |
     map({
       id: .id,
       name: .name,
       entityId: .entityId,
       fields: .fields
     })' export.json
```

Generate `domains/{domain-id}/entities/{entity-id}/index.mdx`:

```yaml
---
id: {SchemaName}
name: {Schema Name}
version: 0.0.1
summary: Aggregate root representing {domain-concept}
owners: []
aggregateRoot: true
identifier: {primary-key-field-name}
properties:
  - name: {field.name}
    type: {json-type}
    required: {true|false}
    summary: {field-description}
---

# {Entity Name}

Aggregate root establishing consistency boundary for {related-operations}.

## Decider pattern

This aggregate implements decide and evolve functions:
- `decide`: Validates commands against current state, produces events
- `evolve`: Applies events to update aggregate state

## State reconstruction

Aggregate state is reconstructed by replaying events in temporal order.
```

Generate `schema.json` if properties array is insufficient for complex types:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "urn:qlerify:schema:entity:{kebab-entity-name}",
  "title": "{SchemaName}",
  "description": "Entity schema for aggregate root",
  "type": "object",
  "properties": {
    // Map fields using type translation with special handling for primaryKey
  },
  "required": [
    // Always include primaryKey field
  ],
  "additionalProperties": false
}
```

Identify primary key from field with `primaryKey: true` or infer from patterns (`id`, `{entityName}Id`, first uuid field).

### Phase 8: Generate flow from parent-child chains

Reconstruct temporal flow from domainEvent parent-child relationships.

Query to extract flow topology:

```sql
-- duckdb query to map event sequences
WITH event_graph AS (
    SELECT
        e.id::VARCHAR as event_id,
        e.description::VARCHAR as event_name,
        e.laneId::VARCHAR as lane_id,
        unnest(e.parents)::VARCHAR as parent_id
    FROM read_json_auto('export.json') AS root,
        unnest(root.domainEvents) AS e
)
SELECT * FROM event_graph ORDER BY parent_id NULLS FIRST;
```

Identify flow entry points (events with empty `parents[]` array) and traverse forward, generating flow steps in sequence.

For each card type in a domainEvent, create flow step elements:

| Card Type | Flow Step Field | Mapping |
|-----------|----------------|---------|
| UserStory (null role) | actor.name | card.text |
| GivenWhenThen | summary | card.text (markdown formatted) |
| Command | message.id | schema.name (PascalCase) |
| Event | (implicit) | domainEvent.description becomes step transition |

Generate `domains/{domain-id}/flows/{flow-id}/index.mdx`:

```yaml
---
id: {flow-name-from-context}
name: {Flow Display Name}
version: 0.0.1
summary: End-to-end flow from {entry-point} to {terminal-event}
owners: []
steps:
  - id: step-1
    title: {domainEvent.description}
    summary: {GivenWhenThen.text}
    actor:
      name: {UserStory.text}
    message:
      id: {CommandOrEvent.name}
      version: "0.0.1"
    service:
      id: {ServiceId}
      version: "0.0.1"
    next_step:
      id: step-2
      label: "on success"
  # ... subsequent steps following parent-child chain
---

# {Flow Name}

Sequential flow reconstructed from Event Modeling parent-child relationships.

## Flow visualization

This flow represents the temporal ordering discovered during Event Modeling sessions.
```

Handle branching flows (events with multiple children) by using `next_steps` array instead of `next_step`:

```yaml
steps:
  - id: step-n
    # ... step fields
    next_steps:
      - id: step-success
        label: "validation passed"
      - id: step-failure
        label: "validation failed"
```

### Phase 9: Cross-reference and validate

Link all generated artifacts through cross-references.

Update service `sends` and `receives` arrays:
- A service `sends` an event if that event's domainEvent.laneId matches the service's lane
- A service `receives` a command if that command's card appears in a domainEvent within the service's lane
- A service `receives` an event if that event is a parent of any domainEvent in the service's lane

Update service `entities` arrays:
- Link entities whose schemas have `entityId` pointing to AggregateRoot cards in domainEvents within the service's lane

Update event `consumers` arrays:
- An event is consumed by services whose lanes contain domainEvents listing this event in their `parents[]` array

Validation checklist:
- [ ] All schemas referenced in MDX frontmatter exist as `schema.json` files
- [ ] All service cross-references (`sends`, `receives`) point to existing commands/events/queries
- [ ] All entity cross-references use correct PascalCase IDs
- [ ] All flow steps reference valid messages and services
- [ ] All inferred types have confidence notes in schema descriptions
- [ ] All enum fields have populated `enum` arrays
- [ ] All aggregate roots have `aggregateRoot: true` and `identifier` fields
- [ ] Primary keys are included in `required` arrays

Generate validation report listing warnings by severity (error, high, medium, low).

## EventCatalog output structure

Complete directory tree for transformed artifacts:

```
domains/
  {domain-id}/
    index.mdx                          # Domain overview
    services/
      {service-id}/
        index.mdx                      # Service overview
        commands/
          {command-id}/
            index.mdx                  # Command metadata
            schema.json                # Command JSON Schema
        events/
          {event-id}/
            index.mdx                  # Event metadata
            schema.json                # Event JSON Schema
        queries/
          {query-id}/
            index.mdx                  # Query metadata
            schema.json                # Query JSON Schema
    entities/
      {entity-id}/
        index.mdx                      # Entity metadata with properties
        schema.json                    # Entity JSON Schema (optional)
    flows/
      {flow-id}/
        index.mdx                      # Flow with steps array
```

File naming conventions:
- Directory names: kebab-case for domains/flows, PascalCase for services/entities
- MDX files: always `index.mdx`
- Schema files: always `schema.json`

## MDX frontmatter templates

### Domain

```yaml
---
id: {kebab-case-id}
name: {Display Name}
version: 1.0.0
summary: {Description}
owners: []
---
```

### Service

```yaml
---
id: {PascalCaseId}
name: {Display Name}
version: 0.0.1
summary: {Description}
owners: []
sends:
  - id: {EventId}
    version: "0.0.1"
receives:
  - id: {CommandOrEventId}
    version: "0.0.1"
entities:
  - id: {EntityId}
    version: "0.0.1"
---
```

### Event

```yaml
---
id: {PascalCaseId}
name: {Display Name}
version: 0.0.1
summary: {Description}
producers:
  - {ServiceId}
consumers:
  - {ServiceId}
schemaPath: schema.json
---
```

### Command

```yaml
---
id: {PascalCaseId}
name: {Display Name}
version: 0.0.1
summary: {Description}
producers:
  - {ServiceId}
consumers:
  - {ServiceId}
schemaPath: schema.json
---
```

### Query

```yaml
---
id: {PascalCaseId}
name: {Display Name}
version: 0.0.1
summary: {Description}
producers:
  - {ServiceId}
consumers:
  - {ServiceId}
schemaPath: schema.json
---
```

### Entity

```yaml
---
id: {PascalCaseId}
name: {Display Name}
version: 0.0.1
summary: {Description}
owners: []
aggregateRoot: true
identifier: {primaryKeyFieldName}
properties:
  - name: {fieldName}
    type: {jsonSchemaType}
    required: {true|false}
    summary: {description}
---
```

### Flow

```yaml
---
id: {kebab-case-id}
name: {Display Name}
version: 0.0.1
summary: {Description}
owners: []
steps:
  - id: {step-id}
    title: {Step Title}
    summary: {Optional GivenWhenThen text}
    actor:
      name: {UserStory actor name}
    message:
      id: {CommandOrEventId}
      version: "0.0.1"
    service:
      id: {ServiceId}
      version: "0.0.1"
    next_step:        # single transition
      id: {next-step-id}
      label: {transition-label}
    # OR next_steps for branching
    next_steps:
      - id: {step-id}
        label: {branch-label}
---
```

## Algebraic structure preservation

The transformation must preserve algebraic relationships discovered during Event Modeling.

Events form a free monoid under concatenation.
The parent-child chains in Qlerify exports encode this temporal ordering.
Flow steps preserve sequential composition, and the flow visualization communicates that events are elements in a temporal sequence, not isolated messages.

Commands are validated functions producing events.
Command MDX should describe validation rules (preconditions) and the events produced on success versus failure.
Use railway-oriented composition language: "validation rules enforced before command acceptance" rather than "command validation".

Aggregates implement the Decider pattern.
Entity MDX for AggregateRoot cards must reference the Decider structure explicitly: `decide` function (command → state → events) and `evolve` function (state → event → state).
Do not document aggregates as "entities with behavior" (object-oriented framing).

Services are module boundaries with explicit effects.
Service MDX should list effects at the boundary (event store writes, external calls) and emphasize that internal logic is pure.
Following Debasish Ghosh's module algebra pattern, services expose signatures (abstract interfaces), algebras (implementations), and interpreters (effect handlers).

Avoid anti-patterns from `event-catalog-tooling.md`:
- Do not organize by "entities" (organize by services and aggregates)
- Do not frame commands as "requests" and events as "responses"
- Do not imply class hierarchies in event documentation
- Do not document events without Decider context
- Do not hide effects in implicit descriptions

## Validation and quality checks

After completing transformation, validate output quality.

### Structural validation

Run these checks programmatically:

```bash
# Verify all schema.json files are valid JSON Schema draft-07
fd -e json -x jaq 'if ."$schema" == "http://json-schema.org/draft-07/schema#"
                    then "valid" else "invalid: " + . end' {} \;

# Verify all MDX files have required frontmatter fields
fd index.mdx -x sh -c 'echo "=== {} ===" && head -20 {} | grep "^id:"'

# Count generated artifacts by type
echo "Services: $(fd -t d . domains/*/services | wc -l)"
echo "Events: $(fd index.mdx domains/*/services/*/events | wc -l)"
echo "Commands: $(fd index.mdx domains/*/services/*/commands | wc -l)"
echo "Queries: $(fd index.mdx domains/*/services/*/queries | wc -l)"
echo "Entities: $(fd index.mdx domains/*/entities | wc -l)"
echo "Flows: $(fd index.mdx domains/*/flows | wc -l)"
```

### Semantic validation

Check for completeness and correctness:

- [ ] Every schema file has a corresponding MDX file in the same directory
- [ ] Every service `sends` reference points to an existing event or command
- [ ] Every service `receives` reference points to an existing command or event
- [ ] Every service `entities` reference points to an existing entity
- [ ] Every flow step `message.id` points to an existing command, event, or query
- [ ] Every flow step `service.id` points to an existing service
- [ ] Every entity marked `aggregateRoot: true` has an `identifier` field
- [ ] Every entity schema includes the identifier field in `required` array
- [ ] All inferred types (medium/low confidence) are documented in schema descriptions
- [ ] All enum fields have non-empty `enum` arrays

### Quality metrics

Generate quality report:

```bash
# Type inference statistics
jaq '.schemas[].fields[] |
     select(.dataType == null) |
     .name' export.json | wc -l
# Report: {count} fields required type inference

# Schema complexity distribution
jaq '.schemas | map({name, field_count: (.fields | length)}) |
     sort_by(.field_count) | reverse' export.json
# Report: Most complex schemas for review

# Flow coverage
# Compare: number of domainEvents vs number of flow steps
# Report: {coverage}% of events incorporated into flows
```

## Future extensions

This workflow can be extended to handle additional Qlerify features as they become available.

Bounded context support: When Qlerify exports include populated `boundedContexts` arrays, extend Phase 2 to generate multiple domains with context mapping documentation per `bounded-context-design.md`.

Channel extraction: EventCatalog supports channels (message buses, topics, queues) as first-class entities.
Currently we generate placeholder channels (command-bus-channel, event-bus-channel).
Future versions could extract channel metadata from Qlerify if exports include infrastructure details.

AsyncAPI integration: Generate AsyncAPI specifications alongside EventCatalog MDX for machine-readable event contracts that support runtime validation.

Schema registry integration: Export generated JSON Schemas to Confluent Schema Registry, AWS Glue Schema Registry, or EventCatalog's schema versioning features per `schema-versioning.md`.

Decider code generation: Use entity schemas and command/event mappings to generate Decider skeleton code in target languages (Rust, TypeScript, Haskell) following patterns from `domain-modeling.md` and language-specific preferences.
