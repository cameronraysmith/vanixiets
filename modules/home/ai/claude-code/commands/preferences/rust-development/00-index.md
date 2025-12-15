# Rust development

This guide integrates functional domain modeling (FDM) with pragmatic Rust practices from Microsoft engineers.

**Primary lens:** Functional domain modeling - type-driven design encoding business logic in the type system, making invariants explicit and violations compile-time errors.

**Complementary guidance:** Microsoft Pragmatic Rust Guidelines - industry best practices for API design, testing, performance, and safety.

**Philosophical reconciliations:**

- *Panic semantics*: Panics for true programming bugs only (contract violations, impossible states).
Domain and infrastructure errors use Result types.
Good type design reduces both panic surface and error handling complexity.
- *Dependency injection*: Prefer concrete types for domain logic, enums for testable I/O (sans-io), generics for algorithm parameters, dyn Trait only for true runtime polymorphism.
This hierarchy complements FDM's emphasis on explicit, type-safe dependencies.
- *Type-driven design*: Both approaches emphasize making invalid states unrepresentable.
Smart constructors, state machines, and strong types eliminate bug categories.

**Role in multi-language architectures:** Rust often serves as the base IO/Result layer in multi-language monad transformer stacks, providing memory-safe, high-performance foundations for effect composition.

## Contents

This guide is organized into focused topic files for easy navigation and AI agent efficiency.

| File | Description |
|------|-------------|
| [01-functional-domain-modeling.md](./01-functional-domain-modeling.md) | Core FDM patterns: smart constructors, state machines, workflows, aggregates, error classification; advanced patterns: phantom types, const generics, NonEmpty collections |
| [02-error-handling.md](./02-error-handling.md) | Canonical error structs, thiserror/anyhow/miette, Result composition, railway-oriented programming, applicative validation, #[must_use] enforcement |
| [03-panic-semantics.md](./03-panic-semantics.md) | When to panic vs return Result, programming bugs vs domain errors |
| [04-api-design.md](./04-api-design.md) | Naming, dependency injection hierarchy, builders, sans-io pattern, serialization boundaries, command/event struct patterns |
| [05-testing.md](./05-testing.md) | Mockable I/O, property-based testing, feature-gated test utilities |
| [06-documentation.md](./06-documentation.md) | Canonical doc sections, module docs, doc tests |
| [07-performance.md](./07-performance.md) | Hot paths, throughput optimization, async yield points, allocators |
| [08-structured-logging.md](./08-structured-logging.md) | Tracing, message templates, OpenTelemetry conventions |
| [09-unsafe-code.md](./09-unsafe-code.md) | Validation requirements, Miri testing, soundness guarantees |
| [10-tooling.md](./10-tooling.md) | Code quality, linting, dependency management |

## References

### Primary sources

This document integrates guidance from:

- **Functional domain modeling**: See `~/.claude/commands/preferences/domain-modeling.md` for universal patterns, `~/.claude/commands/preferences/architectural-patterns.md` for application structure, `~/.claude/commands/preferences/railway-oriented-programming.md` for error composition
- **Microsoft Pragmatic Rust Guidelines**: https://microsoft.github.io/rust-guidelines/agents/all.txt - comprehensive production Rust guidance from Microsoft engineers
- **Rust API Guidelines**: https://rust-lang.github.io/api-guidelines/ - official Rust API design checklist

### Related documents

- `~/.claude/commands/preferences/theoretical-foundations.md` - category-theoretic underpinnings
- `~/.claude/commands/preferences/algebraic-data-types.md` - sum/product type patterns
