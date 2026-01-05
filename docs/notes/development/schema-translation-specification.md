---
title: Qlerify to EventCatalog Schema Translation Specification
created: 2026-01-05
status: draft
---

# Qlerify to EventCatalog schema translation specification

This document specifies the translation strategy from Qlerify's JSON export format to EventCatalog's JSON Schema format.
The translation preserves domain semantics while handling incomplete type information through inference rules and validation warnings.

## Overview

Qlerify exports domain models (Commands, Queries, Entities) with varying levels of type information.
Entity schemas contain rich field metadata (dataType, exampleData, primaryKey, cardinality), while Command and Query schemas often contain only field names.
EventCatalog requires JSON Schema draft-07 format with full type specifications.

The translation must:
- Map Qlerify's dataType values to JSON Schema type + format combinations
- Infer types for untyped Command/Query fields using naming conventions
- Transform exampleData arrays into JSON Schema examples
- Handle entity relationships (relatedEntityId) as schema annotations
- Generate required field lists from primaryKey and cardinality metadata
- Produce validation warnings for incomplete or ambiguous data

## Qlerify schema structure

Qlerify exports schemas with this structure:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Human Readable Name",
  "type": "Command|Query|Entity",
  "boundedContext": null,
  "entityId": "uuid-reference|null",
  "fields": [
    {
      "name": "fieldName",
      "description": null,
      "exampleData": ["example1", "example2"],
      "cardinality": "one-to-one|one-to-many|many-to-one|many-to-many|null",
      "relatedEntityId": "uuid-reference|null",
      "primaryKey": true|null,
      "type": null,
      "dataType": "string|uuid|enum|timestamp|int|boolean|null",
      "tags": null,
      "hideInForm": null,
      "fields": null
    }
  ]
}
```

### Field population patterns

**Entity schemas** (36% of corpus):
- Have `dataType` values (string, uuid, timestamp, int, boolean, enum)
- Include `exampleData` arrays for most fields
- Mark `primaryKey: true` for identifier fields
- Specify `cardinality` for relationship fields
- Reference other entities via `relatedEntityId`

**Command schemas**:
- Field names only, `dataType: null` for most fields
- No `exampleData`
- May have `relatedEntityId` references
- Require type inference

**Query schemas**:
- Field names only, `dataType: null`
- Often have `entityId` back-reference to source entity
- Minimal metadata
- Require type inference

**Global patterns**:
- `description` field is always null in current export
- `type` field is always null (not to be confused with schema-level `type`)
- `fields` (nested) is unused
- `tags` and `hideInForm` are always null

## EventCatalog JSON Schema target format

EventCatalog expects JSON Schema draft-07 with this structure:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "SchemaName",
  "description": "Human-readable description",
  "type": "object",
  "properties": {
    "fieldName": {
      "type": "string|number|integer|boolean|object|array",
      "format": "date-time|uuid|email|uri|...",
      "description": "Field description",
      "enum": ["value1", "value2"],
      "examples": ["example1", "example2"],
      "minimum": 0,
      "pattern": "^...$"
    }
  },
  "required": ["field1", "field2"],
  "additionalProperties": false
}
```

### Key requirements

- `$schema` and `title` are mandatory
- `type: "object"` for all schemas
- `properties` contains field definitions
- `required` array lists non-nullable fields
- `additionalProperties: false` enforces strict validation
- Fields have `type` (JSON Schema basic type) and optional `format` (semantic type)
- `description` provides human context (generated from field name when missing)
- `examples` array demonstrates valid values

## Type mapping specification

### Qlerify dataType to JSON Schema type + format

| Qlerify dataType | JSON Schema type | JSON Schema format | Notes |
|------------------|------------------|-------------------|-------|
| uuid | string | uuid | RFC 4122 UUID |
| timestamp | string | date-time | ISO 8601 date-time |
| int | integer | - | Whole numbers |
| boolean | boolean | - | true/false |
| string | string | - | Default text type |
| enum | string | - | Plus `enum` array (see §3.2) |
| null/missing | string | - | Default fallback with comment |

### Handling enum types

Qlerify marks fields as `dataType: "enum"` but does not provide enum values in the schema export.
The translator must:

1. Check for `exampleData` array as potential enum values
2. If `exampleData` exists, use it for the `enum` array
3. Add validation warning: "enum values inferred from exampleData, verify completeness"
4. If no `exampleData`, emit placeholder and warning: "enum values unknown, manual specification required"

Example transformation:

```json
// Qlerify
{
  "name": "status",
  "dataType": "enum",
  "exampleData": ["pending", "approved", "rejected"]
}

// EventCatalog
{
  "status": {
    "type": "string",
    "enum": ["pending", "approved", "rejected"],
    "description": "Status field (enum values inferred from examples)",
    "examples": ["pending"]
  }
}
```

### Handling relatedEntityId (relationships)

When a field has `relatedEntityId`, it represents a foreign key reference.
The translator should:

1. Use the field's `dataType` for the JSON Schema type (usually uuid)
2. Add description annotation: "References [EntityName] entity (ID: {uuid})"
3. Consider adding `$ref` if building a full schema registry (future enhancement)
4. Record relationship in validation metadata for catalog graph generation

Example:

```json
// Qlerify
{
  "name": "customerId",
  "dataType": "uuid",
  "relatedEntityId": "customer-entity-uuid-here"
}

// EventCatalog
{
  "customerId": {
    "type": "string",
    "format": "uuid",
    "description": "References Customer entity (ID: customer-entity-uuid-here)"
  }
}
```

## Type inference rules

For fields with `dataType: null` (common in Command/Query schemas), apply heuristic inference based on field naming conventions.

### Inference heuristic table

| Field name pattern | Inferred type | Inferred format | Confidence |
|-------------------|---------------|----------------|-----------|
| *Id, *ID | string | uuid | high |
| id (exact) | string | uuid | high |
| *At, *Date, *Time | string | date-time | high |
| created, updated, modified | string | date-time | medium |
| is*, has*, can* | boolean | - | high |
| *Count, *Quantity, *Number | integer | - | medium |
| *Amount, *Price, *Total | number | - | medium |
| email, *Email | string | email | high |
| url, *Url, *URL | string | uri | high |
| phone, *Phone | string | - | medium |
| status, state, *Status | string | - (enum likely) | low |
| (default) | string | - | low |

### Inference annotation

When type inference is applied, add a comment in the description field:

```json
{
  "createdAt": {
    "type": "string",
    "format": "date-time",
    "description": "Created at (type inferred from field name)"
  }
}
```

### Validation warnings for inferred types

Generate warnings in a separate validation report:

```yaml
warnings:
  - schema: "PlaceOrderCommand"
    field: "createdAt"
    severity: "medium"
    message: "Type inferred as date-time from field name, verify correctness"
  - schema: "UpdateInventoryCommand"
    field: "status"
    severity: "high"
    message: "Field name suggests enum but no values available, manual specification required"
```

## Required field determination

The `required` array in JSON Schema lists fields that must be present.
Qlerify provides `primaryKey` and `cardinality` hints.

### Rules for required array

1. Include field if `primaryKey: true`
2. Include field if `cardinality` is "one-to-one" or "one-to-many" (mandatory relationship)
3. Exclude field if `cardinality` is "many-to-one" or "many-to-many" (optional relationship)
4. For fields with no metadata, default to required unless field name suggests optional (e.g., "optional*", "*Optional")
5. Generate validation warning for ambiguous cases

Example:

```json
// Qlerify Entity
{
  "fields": [
    {"name": "id", "primaryKey": true, "dataType": "uuid"},
    {"name": "customerId", "cardinality": "one-to-one", "dataType": "uuid"},
    {"name": "notes", "dataType": "string"}
  ]
}

// EventCatalog
{
  "required": ["id", "customerId", "notes"]
}
```

For Command/Query schemas with no metadata, default to all fields required unless inference suggests otherwise.

## Naming conventions

### File naming

EventCatalog uses kebab-case for filenames:

- PlaceOrderCommand → `place-order.json`
- GetInventoryQuery → `get-inventory.json`
- CustomerEntity → `customer.json`

Rules:
1. Convert PascalCase to kebab-case
2. Strip "Command", "Query", "Event", "Entity" suffixes
3. Use `.json` extension

### Schema $id URN

Generate stable URN identifiers:

```
urn:qlerify:schema:{type}:{name}
```

Examples:
- `urn:qlerify:schema:command:place-order`
- `urn:qlerify:schema:query:get-inventory`
- `urn:qlerify:schema:entity:customer`

Use lowercase kebab-case for name segment.
This provides stable, globally-unique identifiers for schema references.

### Title field

Use the original Qlerify `name` field as-is for the `title` property:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "PlaceOrderCommand",
  "type": "object"
}
```

## Complete translation examples

### Example 1: Entity schema with full metadata

**Qlerify input:**

```json
{
  "id": "customer-entity-id",
  "name": "Customer",
  "type": "Entity",
  "fields": [
    {
      "name": "id",
      "dataType": "uuid",
      "primaryKey": true,
      "exampleData": ["550e8400-e29b-41d4-a716-446655440000"]
    },
    {
      "name": "email",
      "dataType": "string",
      "exampleData": ["customer@example.com", "test@test.com"]
    },
    {
      "name": "status",
      "dataType": "enum",
      "exampleData": ["active", "suspended", "deleted"]
    },
    {
      "name": "createdAt",
      "dataType": "timestamp",
      "exampleData": ["2024-01-15T10:30:00Z"]
    },
    {
      "name": "accountBalance",
      "dataType": "int",
      "exampleData": ["1000", "2500"]
    }
  ]
}
```

**EventCatalog output:**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "urn:qlerify:schema:entity:customer",
  "title": "Customer",
  "description": "Customer entity schema",
  "type": "object",
  "properties": {
    "id": {
      "type": "string",
      "format": "uuid",
      "description": "Unique identifier (primary key)",
      "examples": ["550e8400-e29b-41d4-a716-446655440000"]
    },
    "email": {
      "type": "string",
      "description": "Email field",
      "examples": ["customer@example.com", "test@test.com"]
    },
    "status": {
      "type": "string",
      "description": "Status field (enum values inferred from examples)",
      "enum": ["active", "suspended", "deleted"],
      "examples": ["active"]
    },
    "createdAt": {
      "type": "string",
      "format": "date-time",
      "description": "Created at timestamp",
      "examples": ["2024-01-15T10:30:00Z"]
    },
    "accountBalance": {
      "type": "integer",
      "description": "Account balance field",
      "examples": [1000, 2500]
    }
  },
  "required": ["id", "email", "status", "createdAt", "accountBalance"],
  "additionalProperties": false
}
```

### Example 2: Command schema requiring type inference

**Qlerify input:**

```json
{
  "id": "place-order-command-id",
  "name": "PlaceOrderCommand",
  "type": "Command",
  "fields": [
    {
      "name": "orderId",
      "dataType": null
    },
    {
      "name": "customerId",
      "dataType": null,
      "relatedEntityId": "customer-entity-id"
    },
    {
      "name": "orderDate",
      "dataType": null
    },
    {
      "name": "totalAmount",
      "dataType": null
    },
    {
      "name": "isExpedited",
      "dataType": null
    }
  ]
}
```

**EventCatalog output:**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "urn:qlerify:schema:command:place-order",
  "title": "PlaceOrderCommand",
  "description": "Place order command schema (contains inferred types, requires validation)",
  "type": "object",
  "properties": {
    "orderId": {
      "type": "string",
      "format": "uuid",
      "description": "Order id (type inferred from field name)"
    },
    "customerId": {
      "type": "string",
      "format": "uuid",
      "description": "References Customer entity (ID: customer-entity-id) (type inferred from field name)"
    },
    "orderDate": {
      "type": "string",
      "format": "date-time",
      "description": "Order date (type inferred from field name)"
    },
    "totalAmount": {
      "type": "number",
      "description": "Total amount (type inferred from field name)"
    },
    "isExpedited": {
      "type": "boolean",
      "description": "Is expedited (type inferred from field name)"
    }
  },
  "required": ["orderId", "customerId", "orderDate", "totalAmount", "isExpedited"],
  "additionalProperties": false
}
```

**Validation warnings:**

```yaml
- schema: "PlaceOrderCommand"
  severity: "medium"
  message: "All field types inferred from naming conventions, manual review recommended"
  fields_inferred: ["orderId", "customerId", "orderDate", "totalAmount", "isExpedited"]
```

### Example 3: Query schema with minimal metadata

**Qlerify input:**

```json
{
  "id": "get-customer-query-id",
  "name": "GetCustomerQuery",
  "type": "Query",
  "entityId": "customer-entity-id",
  "fields": [
    {
      "name": "customerId",
      "dataType": null
    }
  ]
}
```

**EventCatalog output:**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "urn:qlerify:schema:query:get-customer",
  "title": "GetCustomerQuery",
  "description": "Get customer query schema (queries Customer entity ID: customer-entity-id)",
  "type": "object",
  "properties": {
    "customerId": {
      "type": "string",
      "format": "uuid",
      "description": "Customer id (type inferred from field name)"
    }
  },
  "required": ["customerId"],
  "additionalProperties": false
}
```

## Validation rules and warnings

The translation process must generate a validation report alongside the translated schemas.

### Validation severity levels

- **error**: Translation cannot proceed or produces invalid JSON Schema
- **high**: Likely incorrect translation requiring manual intervention
- **medium**: Uncertain inference requiring human review
- **low**: Minor issues or best-practice recommendations

### Common validation scenarios

| Scenario | Severity | Message |
|----------|----------|---------|
| Field has `dataType: null`, inference failed | high | "Unable to infer type for field {name}, defaulting to string" |
| Enum without exampleData | high | "Enum type specified but no values available for field {name}" |
| Multiple fields with same name | error | "Duplicate field name {name} in schema" |
| Missing primaryKey in Entity | medium | "Entity schema has no primary key field" |
| relatedEntityId references unknown entity | medium | "Field {name} references unknown entity ID {id}" |
| Command/Query with all inferred types | medium | "All types inferred, manual review recommended" |
| exampleData doesn't match inferred type | high | "Example value '{value}' doesn't match type {type} for field {name}" |
| Field name suggests enum but dataType is string | low | "Field {name} may be enum, consider review" |

### Validation report format

```yaml
translation_summary:
  total_schemas: 150
  entities: 54
  commands: 48
  queries: 48
  total_fields: 1247
  fields_with_types: 450
  fields_inferred: 797

validation_results:
  errors: 0
  high_severity: 23
  medium_severity: 145
  low_severity: 67

warnings:
  - schema_id: "place-order-command-id"
    schema_name: "PlaceOrderCommand"
    schema_type: "Command"
    severity: "medium"
    category: "type_inference"
    message: "All field types inferred from naming conventions"
    affected_fields: ["orderId", "customerId", "orderDate"]

  - schema_id: "customer-entity-id"
    schema_name: "Customer"
    schema_type: "Entity"
    field: "status"
    severity: "medium"
    category: "enum_values"
    message: "Enum values inferred from exampleData, verify completeness"
    inferred_values: ["active", "suspended", "deleted"]
```

## Translation algorithm pseudocode

```python
def translate_qlerify_to_eventcatalog(qlerify_schema: dict) -> dict:
    """
    Translate a Qlerify schema to EventCatalog JSON Schema format.

    Returns tuple of (json_schema, validation_warnings)
    """
    warnings = []

    # Base schema structure
    json_schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": generate_schema_urn(qlerify_schema),
        "title": qlerify_schema["name"],
        "description": generate_description(qlerify_schema),
        "type": "object",
        "properties": {},
        "required": [],
        "additionalProperties": false
    }

    # Translate each field
    for field in qlerify_schema["fields"]:
        field_schema, field_warnings = translate_field(
            field,
            qlerify_schema["type"]
        )
        json_schema["properties"][field["name"]] = field_schema
        warnings.extend(field_warnings)

        # Determine if required
        if should_be_required(field, qlerify_schema["type"]):
            json_schema["required"].append(field["name"])

    return json_schema, warnings


def translate_field(field: dict, schema_type: str) -> tuple[dict, list]:
    """Translate a single Qlerify field to JSON Schema property."""
    warnings = []

    # Check if type is explicitly provided
    if field["dataType"] is not None:
        json_type, json_format = map_datatype(field["dataType"])
        description = f"{field['name']} field"
    else:
        # Type inference required
        json_type, json_format, confidence = infer_type_from_name(field["name"])
        description = f"{field['name']} (type inferred from field name)"
        warnings.append({
            "field": field["name"],
            "severity": "medium" if confidence == "high" else "high",
            "message": f"Type inferred as {json_type}, verify correctness"
        })

    # Build base field schema
    field_schema = {
        "type": json_type,
        "description": description
    }

    if json_format:
        field_schema["format"] = json_format

    # Handle enum types
    if field["dataType"] == "enum":
        if field["exampleData"]:
            field_schema["enum"] = field["exampleData"]
            warnings.append({
                "field": field["name"],
                "severity": "medium",
                "message": "Enum values inferred from exampleData"
            })
        else:
            warnings.append({
                "field": field["name"],
                "severity": "high",
                "message": "Enum type but no values available"
            })

    # Handle examples
    if field["exampleData"]:
        field_schema["examples"] = convert_examples(
            field["exampleData"],
            json_type
        )

    # Handle relationships
    if field["relatedEntityId"]:
        field_schema["description"] += f" (References entity {field['relatedEntityId']})"

    return field_schema, warnings


def should_be_required(field: dict, schema_type: str) -> bool:
    """Determine if field should be in required array."""
    # Primary keys always required
    if field.get("primaryKey"):
        return True

    # One-to-one and one-to-many relationships required
    if field.get("cardinality") in ["one-to-one", "one-to-many"]:
        return True

    # Many-to-* relationships optional
    if field.get("cardinality") in ["many-to-one", "many-to-many"]:
        return False

    # Field name heuristics
    if "optional" in field["name"].lower():
        return False

    # Default to required for Entity, Query, Command
    return True


def generate_schema_urn(schema: dict) -> str:
    """Generate stable URN identifier."""
    schema_type = schema["type"].lower()  # "command", "query", "entity"
    kebab_name = to_kebab_case(
        schema["name"].replace("Command", "")
                     .replace("Query", "")
                     .replace("Entity", "")
    )
    return f"urn:qlerify:schema:{schema_type}:{kebab_name}"
```

## Implementation phases

### Phase 1: Core translation (Entity schemas)

Implement translation for Entity schemas with full metadata:
- Direct dataType mapping
- exampleData to examples
- primaryKey to required
- Validate output against JSON Schema draft-07

### Phase 2: Type inference (Command/Query schemas)

Implement heuristic type inference:
- Field name pattern matching
- Confidence scoring
- Warning generation
- Human-in-the-loop review workflow

### Phase 3: Relationship handling

Implement relationship graph extraction:
- relatedEntityId resolution
- Entity name lookup
- Graph metadata for EventCatalog
- Cross-reference validation

### Phase 4: Validation and quality

Implement comprehensive validation:
- Schema well-formedness checks
- Type consistency validation
- Example value validation
- Completeness scoring
- Human review prioritization

## Future enhancements

### Schema registry integration

Build a full schema registry with `$ref` support:
- Convert relatedEntityId to `$ref` URNs
- Generate schema dependency graph
- Support schema composition and inheritance

### Bidirectional sync

Enable round-trip translation:
- EventCatalog → Qlerify format
- Change detection and merge
- Version control integration

### LLM-assisted type inference

Use language models to improve inference:
- Analyze field names in context of schema
- Infer enum values from domain knowledge
- Generate human-readable descriptions
- Suggest validation rules (patterns, ranges)

### EventCatalog markdown generation

Generate complete EventCatalog entries:
- Markdown frontmatter from schema metadata
- Algebraic documentation (Decider pattern)
- Command/event relationships
- Service boundaries and ownership

## Alignment with preference documents

This translation strategy aligns with the following principles:

**From event-catalog-tooling.md:**
- Schemas document algebraic structure (events as monoid elements)
- Commands document functional signatures with validation
- Service boundaries explicit in schema ownership
- Schema versioning through EventCatalog version metadata

**From schema-versioning.md:**
- JSON Schema as type-safe contract
- Schema evolution through additive changes only
- Cross-language compatibility via standard JSON Schema
- Validation at boundaries (translation time)

**From data-modeling.md:**
- Type safety through explicit schemas
- Illegal states unrepresentable (additionalProperties: false)
- Validation at boundaries (Qlerify → EventCatalog)
- Schema as executable contract

**From algebraic-data-types.md:**
- Enums as sum types (JSON Schema enum)
- Product types as object properties
- Required fields enforce totality
- Type inference preserves semantic meaning

## References

- JSON Schema Draft-07: https://json-schema.org/draft-07/schema
- EventCatalog documentation: (via context7 MCP `/websites/eventcatalog_dev`)
- EventCatalog examples: `/Users/crs58/projects/lakescope-workspace/eventcatalog/examples/`
- Qlerify schema analysis: (Phase 1 analysis document, to be linked)
