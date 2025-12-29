# Type-level programming

This document covers strategic library extensions for type-level programming beyond Rust's native capabilities.
For native patterns (smart constructors, typestate, phantom types), see 01-functional-domain-modeling.md.

## The pragmatic philosophy

Native Rust features handle most type-level programming needs: ownership semantics provide typestate, const generics enable compile-time numeric bounds, and phantom types track invariants at zero runtime cost.
Libraries fill specific gaps where native features have concrete limitations.

The goal is 80% of dependent-type safety benefits with 20% of complexity.
Reach for libraries when native features have *concrete* limitations, not for theoretical completeness.

Key questions before adopting a library:
- Can const generics express this? (Often yes for fixed numeric bounds)
- Can phantom types + typestate express this? (Often yes for state machines)
- Is type-level computation actually needed, or is runtime validation acceptable?

## Tier overview

### Native patterns (covered elsewhere)

The following patterns form Tier 0 and should be considered first:
- Smart constructors with newtype pattern (01-functional-domain-modeling.md, Pattern 1)
- Const generics for compile-time constraints (01-functional-domain-modeling.md, Pattern 1a)
- Phantom types for zero-cost state tracking (01-functional-domain-modeling.md, Pattern 2a)
- Emergent typestate from affine + nominal + phantom types (11-concurrency.md)

These native capabilities handle the vast majority of type-level programming needs without external dependencies.

### Strategic extensions

When native features hit concrete walls, these libraries provide targeted solutions:
- **typenum**: Type-level arithmetic on stable Rust, signed integers, type-level comparisons
- **frunk**: Generic programming primitives (HLists, Coproducts, LabelledGeneric)

### Ergonomic tooling

Libraries that provide the same guarantees as manual patterns with reduced boilerplate:
- **nutype**: Refinement types via derive macros

## typenum: Type-level arithmetic

typenum encodes integers as types, enabling arithmetic operations that are evaluated by the compiler rather than at runtime.
This complements const generics for scenarios where stable Rust's const evaluation falls short.

### When typenum complements const generics

| Capability | Const Generics | typenum |
|------------|----------------|---------|
| Arithmetic in type position | Nightly only | Stable |
| Signed type-level integers | Not supported | Full support |
| Type-level comparisons | Not available | IsLess, IsGreater, etc. |
| Power-of-two constraints | Complex workarounds | PowerOfTwo trait |

Const generics work well for simple bounds where the value flows through as-is.
typenum shines when you need to compute with type-level values or express relationships between them.

### Key patterns

**Matrix dimension checking**: Enforce compatible dimensions at compile time, preventing shape mismatches that would otherwise surface as runtime panics.

```rust
use typenum::{U2, U3, Unsigned};
use std::marker::PhantomData;

struct Matrix<Rows: Unsigned, Cols: Unsigned> {
    data: Vec<f64>,
    _phantom: PhantomData<(Rows, Cols)>,
}

// Multiplication requires inner dimensions to match
impl<M: Unsigned, N: Unsigned, P: Unsigned> Matrix<M, N> {
    fn multiply(self, other: Matrix<N, P>) -> Matrix<M, P> {
        // Inner dimension N enforced by type signature
        Matrix { data: vec![], _phantom: PhantomData }
    }
}

// Matrix<U2, U3> * Matrix<U3, U4> compiles
// Matrix<U2, U3> * Matrix<U2, U4> rejected: expected U3, found U2
```

**Physical units with dimensional analysis**: Signed type-level integers enable negative exponents for derived units.
Velocity is length per time (L^1 T^-1), acceleration is length per time squared (L^1 T^-2).

```rust
use typenum::{Integer, P1, N1, N2, Z0};
use typenum::operator_aliases::Sub1;
use std::marker::PhantomData;
use std::ops::Div;

// Dimensions: Length, Time (signed exponents)
struct Quantity<L: Integer, T: Integer> {
    value: f64,
    _phantom: PhantomData<(L, T)>,
}

type Length = Quantity<P1, Z0>;       // m^1 s^0
type Time = Quantity<Z0, P1>;         // m^0 s^1
type Velocity = Quantity<P1, N1>;     // m^1 s^-1
type Acceleration = Quantity<P1, N2>; // m^1 s^-2

// Division subtracts exponents: L1-L2, T1-T2
impl<L1, T1, L2, T2> Div<Quantity<L2, T2>> for Quantity<L1, T1>
where
    L1: Integer + std::ops::Sub<L2>,
    T1: Integer + std::ops::Sub<T2>,
    L2: Integer,
    T2: Integer,
    <L1 as std::ops::Sub<L2>>::Output: Integer,
    <T1 as std::ops::Sub<T2>>::Output: Integer,
{
    type Output = Quantity<
        <L1 as std::ops::Sub<L2>>::Output,
        <T1 as std::ops::Sub<T2>>::Output
    >;

    fn div(self, rhs: Quantity<L2, T2>) -> Self::Output {
        Quantity { value: self.value / rhs.value, _phantom: PhantomData }
    }
}

// distance / time yields velocity, enforced by compiler
// velocity / time yields acceleration
// distance / velocity would yield time (correct inversion)
```

This pattern extends naturally to more dimensions (mass, temperature, current) for complete SI unit tracking.

**Bounds via trait constraints**: PowerOfTwo and comparison operators work as trait bounds.

```rust
use typenum::{PowerOfTwo, IsGreater, True, U64, U8};

// Buffer size must be power of two and at least 64
fn allocate_buffer<N>() -> Buffer<N>
where
    N: PowerOfTwo + IsGreater<U64, Output = True>,
{
    // Size known at compile time, optimizations apply
}
```

### Limitations

Compile times increase with complex type-level computations, though usually not dramatically.
Error messages involving typenum bounds can be opaque; the `tnfilt` tool post-processes compiler output to improve readability.
Type-level values cap at U65535 by default.
The library has a learning curve for developers unfamiliar with type-level programming idioms.

## frunk: Generic programming primitives

frunk provides heterogeneous lists (HLists), coproducts (type-level sum types), and LabelledGeneric for structural type conversions.
These primitives enable generic programming patterns that Rust's native generics cannot express.

### When frunk adds value

Use frunk's LabelledGeneric when you have genuine structural isomorphism between types.
This commonly occurs at layer boundaries: API DTOs, domain models, and persistence entities often share field structure but are distinct types for good reasons.

Frunk eliminates the repetitive `From` implementations that accumulate when the same data traverses multiple layers.

### Key patterns

**Structural conversion with transmogrify**: Convert between structs with matching field names regardless of field order.

```rust
use frunk::{LabelledGeneric, transmogrify};

#[derive(LabelledGeneric)]
struct ApiUser { email: String, name: String, age: u32 }

#[derive(LabelledGeneric)]
struct DomainUser { name: String, email: String, age: u32 }

// Fields match by name, order irrelevant
let api_user = ApiUser { email: "a@b.com".into(), name: "Jo".into(), age: 30 };
let domain_user: DomainUser = transmogrify(api_user);
// Compiler verifies all required fields exist with matching types
```

**HLists for heterogeneous data**: Type-safe access to mixed-type collections without boxing or trait objects.
The `pluck` operation retrieves a value by type, returning both the value and the remaining list.
The `sculpt` operation reorders an HList to match a target shape.

```rust
use frunk::{hlist, HList};
use frunk::hlist::Plucker;

// Type-safe configuration container
let config = hlist![
    DatabaseConfig { url: "postgres://...".into() },
    CacheConfig { ttl_seconds: 300 },
    LogLevel::Info,
];

// Pluck by type - compiler knows exactly what's available
let (db_config, remaining): (DatabaseConfig, _) = config.pluck();
let (cache_config, remaining): (CacheConfig, _) = remaining.pluck();

// Attempting to pluck a type not in the list is a compile error
```

These primitives enable type-safe dependency injection or configuration systems where available dependencies are tracked at the type level.

**Validated for error accumulation**: Collects all validation errors instead of short-circuiting on the first failure.
This provides applicative-style validation without implementing the pattern manually.

```rust
use frunk::validated::{Validated, IntoValidated};

fn validate_age(age: i32) -> Result<u32, &'static str> {
    if age >= 0 { Ok(age as u32) } else { Err("negative age") }
}

fn validate_name(name: &str) -> Result<String, &'static str> {
    if !name.is_empty() { Ok(name.into()) } else { Err("empty name") }
}

// Accumulates both errors if both validations fail
let result = validate_age(-5).into_validated()
    .and(validate_name("").into_validated());
// Returns Validated::HList with errors: ["negative age", "empty name"]
```

**Coproducts**: Ad-hoc sum types without defining enums.
Coproducts are rarely needed in practice because standard Rust enums are almost always preferable.
Enums have better error messages, IDE support, and exhaustive match checking.
Coproducts occasionally prove useful in highly generic library code that must work with caller-provided type sets, but this situation is uncommon.

### Complexity assessment

Error messages are frunk's primary weakness.
Deeply nested generic types produce compiler errors that require careful reading.
The `LabelledGeneric` derive macro adds compile time overhead proportional to struct complexity.

frunk is worth adopting when you have many genuinely isomorphic struct conversions across layer boundaries.
It is not worth the complexity for 2-3 types with simple relationships where manual `From` implementations are clearer.

## nutype: Refinement types via derive

nutype transforms multi-line smart constructors into concise derive declarations while maintaining identical safety guarantees.
The macro generates the newtype struct, validation logic, and accessor methods from attribute annotations.

### The value proposition

Manual smart constructor:

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Percentage(f64);

impl Percentage {
    pub fn new(value: f64) -> Result<Self, &'static str> {
        if value < 0.0 || value > 100.0 {
            return Err("percentage must be between 0 and 100");
        }
        Ok(Percentage(value))
    }

    pub fn value(&self) -> f64 { self.0 }
}
```

Equivalent with nutype:

```rust
use nutype::nutype;

#[nutype(validate(greater_or_equal = 0.0, less_or_equal = 100.0))]
pub struct Percentage(f64);
```

Both provide identical guarantees: construction only succeeds with valid values, the inner value is inaccessible except through controlled means.

### Key patterns

**Range constraints**: `greater_or_equal`, `less_or_equal`, `greater`, `less` for numeric bounds.
The `finite` validator enables `Eq` and `Ord` on float types by rejecting NaN and infinity.

```rust
#[nutype(validate(finite, greater = 0.0))]
pub struct PositiveFinite(f64); // Eq, Ord derivable
```

**String sanitization combined with validation**: Apply transformations before validation.

```rust
#[nutype(
    sanitize(trim, lowercase),
    validate(not_empty, regex = r"^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$")
)]
pub struct Email(String);
```

**Custom validators**: Use `with = function` for domain-specific rules, optionally with custom error types.

```rust
fn validate_username(s: &str) -> Result<(), UsernameError> {
    if s.len() < 3 { return Err(UsernameError::TooShort); }
    if s.contains(char::is_whitespace) { return Err(UsernameError::ContainsWhitespace); }
    Ok(())
}

#[nutype(validate(with = validate_username))]
pub struct Username(String);
```

**Serde integration**: Validation runs automatically during deserialization, rejecting invalid payloads at the boundary.

```rust
#[nutype(
    validate(greater_or_equal = 1, less_or_equal = 100),
    derive(Deserialize, Serialize)
)]
pub struct PageSize(u32);

// JSON {"page_size": 0} fails deserialization with validation error
```

### When to use nutype vs manual smart constructors

| Scenario | Recommendation |
|----------|----------------|
| Simple range or string constraints | nutype |
| Serde integration needed | nutype |
| Cross-field validation | Manual (nutype validates single fields) |
| Maximum compile-time control | Manual |
| Complex custom error types | Either (nutype supports `with = fn`) |

### Limitations

Proc macros add compile time, though nutype is relatively lightweight compared to larger derive macro ecosystems.
Cross-field validation is not supported; if fields have interdependencies, use a manual smart constructor at the aggregate level that composes nutype-validated fields.

## Compile-time assertions

### Native patterns (preferred)

Modern Rust provides compile-time assertion capabilities without external crates.

**Rust 1.79+ (const blocks)**: Inline assertions with clear syntax.

```rust
const SIZE: usize = 64;
const MAX: usize = 128;

const { assert!(SIZE <= MAX, "SIZE exceeds maximum allowed value"); }
```

**Rust 1.57+ (const item)**: Module-level assertions for global invariants.

```rust
const _: () = assert!(std::mem::size_of::<MyStruct>() <= 64);
```

These native patterns handle most compile-time assertion needs.

### When external crates were needed

The `static_assertions` crate provided `assert_impl_all!` for verifying trait implementations at compile time.

```rust
use static_assertions::assert_impl_all;

assert_impl_all!(MyType: Send, Sync, Clone);
```

No direct native equivalent exists for compile-time trait checking.
For new code, prefer native patterns where possible.
Use `static_assertions` if you specifically need compile-time trait verification and accept that the crate is now unmaintained.

## Anti-patterns to avoid

**Deep higher-rank trait bound nesting**: Type inference breaks down with deeply nested HRTBs.
If you find yourself writing `for<'a> for<'b> ...` chains, the design likely needs reconsideration.
Simplify by introducing intermediate types or accepting some runtime dynamism.

**Recursive type-level computation**: The compiler imposes recursion limits on type-level evaluation.
Toy examples like type-level fibonacci work, but real-world usage hits these limits and produces confusing errors.
Compute values at const-time instead when possible.

**Trait bound pyramids**: Complex where clauses with many bounds cause exponential compile time growth as the solver explores combinations.
If bounds span multiple lines, the abstraction may be too complex.
Consider whether some bounds could become runtime checks or whether the generic should be split.

**Proc macros for everything**: Debugging proc macro code is difficult, IDE support suffers, and compile times increase.
Use proc macros for genuine boilerplate reduction (like nutype) rather than capabilities achievable with regular generics.
Prefer declarative macros (`macro_rules!`) when they suffice.

**Emulating full dependent types**: Rust's type system is optimized for ownership and borrowing, not dependent function types.
Heroic encodings of dependent types fight the compiler rather than leveraging its strengths.
Accept that some invariants are better expressed as runtime checks with clear error messages than as complex type-level machinery.

## Decision framework

Before reaching for a type-level programming library:

1. **Can const generics express this?**
   Often yes for fixed numeric bounds, array sizes, and simple parameterization.

2. **Can phantom types + typestate express this?**
   Often yes for state machines, capability tracking, and zero-cost invariant encoding.

3. **Is the type-level computation actually needed?**
   Runtime validation with good error messages is often more maintainable than complex type-level encodings.

Reach for libraries when:
- You need arithmetic *in type position* on stable Rust (typenum)
- You have many isomorphic struct conversions across layers (frunk)
- You want smart constructor guarantees with less boilerplate (nutype)
- You need compile-time trait verification (static_assertions, accepting unmaintained status)

The best type-level programming is the simplest approach that provides the required guarantees.

## Integration patterns

### Combining libraries effectively

Libraries in this document compose well when used judiciously.
A common effective pattern combines nutype for field-level validation with manual smart constructors for cross-field invariants.

```rust
use nutype::nutype;

#[nutype(validate(greater = 0.0, finite))]
pub struct PositiveAmount(f64);

#[nutype(validate(greater = 0.0, less_or_equal = 1.0, finite))]
pub struct DiscountRate(f64);

// Cross-field validation at aggregate level
pub struct PricedItem {
    amount: PositiveAmount,
    discount: DiscountRate,
}

impl PricedItem {
    pub fn new(amount: PositiveAmount, discount: DiscountRate) -> Result<Self, &'static str> {
        // Cross-field invariant: discounted price must remain positive
        let discounted = amount.into_inner() * (1.0 - discount.into_inner());
        if discounted < 0.01 {
            return Err("discount would reduce price below minimum");
        }
        Ok(PricedItem { amount, discount })
    }
}
```

### Migration path from runtime to compile-time

When evolving code from runtime validation toward compile-time guarantees:

1. Start with runtime validation using Result types
2. Identify invariants that are always known at compile time
3. Extract those invariants into const generics or phantom types
4. Use nutype to reduce boilerplate for remaining runtime-validated fields
5. Reserve typenum/frunk for genuine gaps in native expressiveness

This incremental approach maintains working code at each step while progressively strengthening type-level guarantees.

## See also

- [01-functional-domain-modeling.md](./01-functional-domain-modeling.md): Native patterns for smart constructors, typestate, phantom types
- [11-concurrency.md](./11-concurrency.md): Emergent typestate from affine + nominal + phantom types
- [02-error-handling.md](./02-error-handling.md): Result composition and railway-oriented programming
- [theoretical-foundations.md](../theoretical-foundations.md): Category-theoretic underpinnings
