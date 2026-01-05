---
title: Schema Translation Quick Reference
created: 2026-01-05
---

# Schema translation quick reference

One-page reference for Qlerify to EventCatalog JSON Schema translation.
See `schema-translation-specification.md` for complete details.

## Type mapping

| Qlerify dataType | JSON Schema | Format | Example |
|-----------------|------------|--------|---------|
| uuid | string | uuid | `"550e8400-e29b-41d4-a716-446655440000"` |
| timestamp | string | date-time | `"2024-01-15T10:30:00Z"` |
| int | integer | - | `42` |
| boolean | boolean | - | `true` |
| string | string | - | `"hello"` |
| enum | string + enum | - | `{"enum": ["a", "b", "c"]}` |
| null | string (inferred) | - | ⚠️ requires inference |

## Field name inference patterns

| Pattern | Type | Format | Confidence |
|---------|------|--------|-----------|
| `*Id`, `*ID`, `id` | string | uuid | high |
| `*At`, `*Date`, `*Time`, `created`, `updated` | string | date-time | high |
| `is*`, `has*`, `can*` | boolean | - | high |
| `*Count`, `*Quantity`, `*Number` | integer | - | medium |
| `*Amount`, `*Price`, `*Total` | number | - | medium |
| `email`, `*Email` | string | email | high |
| `url`, `*Url`, `*URL` | string | uri | high |
| `phone`, `*Phone` | string | - | medium |
| `status`, `state`, `*Status` | string | (enum likely) | low |

## Required field rules

| Condition | Required? |
|-----------|----------|
| `primaryKey: true` | ✅ Yes |
| `cardinality: "one-to-one"` | ✅ Yes |
| `cardinality: "one-to-many"` | ✅ Yes |
| `cardinality: "many-to-one"` | ❌ No |
| `cardinality: "many-to-many"` | ❌ No |
| Field name contains "optional" | ❌ No |
| No metadata (default) | ✅ Yes |

## Naming conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Filename | kebab-case.json | `place-order.json` |
| Schema $id | urn:qlerify:schema:{type}:{name} | `urn:qlerify:schema:command:place-order` |
| Title | Original Qlerify name | `"PlaceOrderCommand"` |

## Translation template

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "urn:qlerify:schema:{type}:{kebab-name}",
  "title": "{Original Name}",
  "description": "{Type} schema",
  "type": "object",
  "properties": {
    "{fieldName}": {
      "type": "{json-type}",
      "format": "{format-if-applicable}",
      "description": "{field name} (type inferred from field name)",
      "examples": ["{example-values}"]
    }
  },
  "required": ["{required-fields}"],
  "additionalProperties": false
}
```

## Validation severity

| Level | Meaning | Action |
|-------|---------|--------|
| error | Invalid output | Fix before proceeding |
| high | Likely incorrect | Manual review required |
| medium | Uncertain inference | Human verification recommended |
| low | Best practice | Consider review |

## Common warnings

| Scenario | Severity | Resolution |
|----------|----------|-----------|
| All types inferred | medium | Review inferred types |
| Enum without values | high | Specify enum values manually |
| Unknown relatedEntityId | medium | Verify entity reference |
| Example doesn't match type | high | Fix example or type |
| No primary key (Entity) | medium | Add primary key field |

## Implementation checklist

- [ ] Phase 1: Entity schemas (full metadata)
- [ ] Phase 2: Type inference (Command/Query)
- [ ] Phase 3: Relationship handling
- [ ] Phase 4: Validation and quality checks

## Example transformations

### Entity (full metadata)

```json
// Qlerify
{"name": "customerId", "dataType": "uuid", "primaryKey": true}

// EventCatalog
{
  "customerId": {
    "type": "string",
    "format": "uuid",
    "description": "Customer id (primary key)"
  }
}
```

### Command (inferred types)

```json
// Qlerify
{"name": "orderDate", "dataType": null}

// EventCatalog
{
  "orderDate": {
    "type": "string",
    "format": "date-time",
    "description": "Order date (type inferred from field name)"
  }
}
```

### Enum field

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
    "description": "Status (enum values inferred from examples)",
    "examples": ["pending"]
  }
}
```

### Relationship

```json
// Qlerify
{
  "name": "customerId",
  "dataType": "uuid",
  "relatedEntityId": "customer-entity-uuid"
}

// EventCatalog
{
  "customerId": {
    "type": "string",
    "format": "uuid",
    "description": "References Customer entity (ID: customer-entity-uuid)"
  }
}
```

## Quick diagnosis

**Problem: Field has no type**
- Check field name patterns
- Apply inference heuristic
- Generate warning
- Default to `string` if no match

**Problem: Enum without values**
- Check `exampleData` array
- Use as enum values if present
- Generate high-severity warning if absent

**Problem: Can't determine if required**
- Check `primaryKey` and `cardinality`
- Check field name for "optional"
- Default to required for safety

**Problem: Related entity unknown**
- Use relatedEntityId as-is in description
- Generate medium-severity warning
- Build entity lookup table in later phase
