## Unsafe code

Rust's safety guarantees make it ideal for implementing the type-safe foundations described in domain-modeling.md.
However, `unsafe` code deliberately lowers the compiler's guardrails, transferring correctness responsibilities to the programmer.
This section defines when unsafe is permissible and the validation requirements that apply.

### Fundamental principle: unsafe implies undefined behavior risk

The `unsafe` keyword may only mark functions and traits where misuse creates risk of undefined behavior (UB).
Never use `unsafe` to mark functions that are merely dangerous for other reasons.

```rust
// Valid: dereferencing raw pointer risks UB if pointer invalid
unsafe fn print_string(x: *const String) {
    println!("{}", *x);
}

// Invalid: deleting database is dangerous but cannot cause UB
unsafe fn delete_database() {
    std::fs::remove_dir_all("/var/db")
}
```

Use clear, descriptive names and documentation to communicate danger that does not involve undefined behavior.
Reserve `unsafe` exclusively for its technical meaning in Rust's memory safety model.

### Valid reasons for unsafe code

You must have one of exactly three valid reasons to use `unsafe`:

**1. Novel abstractions** - Creating new foundational types the standard library does not provide:
- Custom smart pointers (Arc variants, intrusive linked lists)
- Custom allocators or memory management
- Low-level data structures (lock-free queues, concurrent maps)

**2. Performance optimization** - Removing bounds checks or other safety overhead after proving correctness:
- Using `.get_unchecked()` in hot paths after validating indices
- Bypassing UTF-8 validation when constructing known-valid strings
- Manual vectorization or SIMD operations

**3. FFI and platform calls** - Interfacing with external code:
- Calling C libraries or system APIs
- Implementing bindings to native libraries
- Direct kernel interactions

If your use case does not fit these categories, find a safe alternative.

### Invalid reasons for unsafe code

Never use ad-hoc `unsafe` (embedded in otherwise unrelated code) to:

**Bypass type system constraints** - Type bounds exist to prevent misuse:
```rust
// NEVER: Bypassing Send bounds
struct NotSendable {
    ptr: *const u8,
}

// This is unsound - creates undefined behavior
unsafe impl Send for NotSendable {}
```

**Simplify safe operations** - Convenience never justifies unsafe:
```rust
// NEVER: Transmuting enums for "simplicity"
enum Status {
    Pending = 0,
    Active = 1,
    Done = 2,
}

fn status_from_int_bad(x: u8) -> Status {
    // Unsound if x > 2
    unsafe { std::mem::transmute(x) }
}

// ALWAYS: Use safe matching
fn status_from_int_good(x: u8) -> Option<Status> {
    match x {
        0 => Some(Status::Pending),
        1 => Some(Status::Active),
        2 => Some(Status::Done),
        _ => None,
    }
}
```

**Bypass lifetime requirements** - Lifetimes encode essential relationships:
```rust
// NEVER: Extending lifetimes via transmute
fn extend_lifetime_bad<'a, 'b, T>(x: &'a T) -> &'b T {
    // Creates dangling references
    unsafe { std::mem::transmute(x) }
}

// ALWAYS: Respect lifetime bounds or redesign API
```

Ad-hoc unsafe is never acceptable.
If you need these capabilities, design a proper abstraction with sound encapsulation.

### Relationship to functional domain modeling

Good type design reduces the need for unsafe code.
The patterns in domain-modeling.md show how to make invalid states unrepresentable using safe Rust:

**Smart constructors eliminate unsafe validation shortcuts**:
```rust
// Instead of bypassing validation with transmute
pub struct QualityScore(f64); // Could use unsafe to skip checks

// Use smart constructor pattern (safe)
impl QualityScore {
    pub fn new(value: f64) -> Result<Self, String> {
        if !(0.0..=1.0).contains(&value) {
            return Err(format!("quality score must be in [0,1], got {}", value));
        }
        Ok(QualityScore(value))
    }
}
```

**State machines prevent unsafe state manipulation**:
```rust
// Instead of unsafely setting state flags
struct Model {
    state: u8, // 0=training, 1=validated, would need unsafe casts
}

// Use enum state machine (safe)
enum ModelState {
    Training(TrainingData),
    Validated(ValidationResult),
}
```

**Type-level invariants reduce unchecked operations**:
```rust
// Instead of get_unchecked assuming non-empty
fn first_element<T>(vec: &Vec<T>) -> &T {
    unsafe { vec.get_unchecked(0) } // UB if empty
}

// Use NonEmpty type with guaranteed length (safe)
pub struct NonEmpty<T> {
    head: T,
    tail: Vec<T>,
}

impl<T> NonEmpty<T> {
    pub fn first(&self) -> &T {
        &self.head // Always safe, no bounds check needed
    }
}
```

Before reaching for unsafe, ask: "Can I encode this invariant in the type system?"
Good domain modeling eliminates entire classes of unsafe operations.

### Novel abstractions: validation requirements

When building foundational abstractions requiring unsafe, follow these requirements without exception:

**1. Verify no established alternative exists**

Search crates.io and consult with team.
Prefer proven libraries over custom implementations.

**2. Design must be minimal and testable**

Extract the unsafe core into the smallest possible module.
Provide safe wrappers for all public APIs.

```rust
// Bad: Large unsafe module with mixed concerns
mod database {
    pub unsafe fn raw_query(sql: *const u8, len: usize) -> QueryResult { }
    pub unsafe fn raw_insert(data: *const u8) -> bool { }
}

// Good: Minimal unsafe core with safe wrapper
mod ffi {
    // Private unsafe core
    unsafe fn raw_query(sql: *const u8, len: usize) -> i32 { }
}

pub mod database {
    // Public safe API
    pub fn query(sql: &str) -> Result<QueryResult, DbError> {
        unsafe { ffi::raw_query(sql.as_ptr(), sql.len()) }
        // ... error handling ...
    }
}
```

**3. Harden against adversarial code**

Assume all safe traits can misbehave.
Your unsafe code must remain sound even when:

- Closures panic mid-execution
- `Deref` implementations return different values each call
- `Clone` implementations produce invalid copies
- `Drop` implementations panic or access global state

Test with intentionally misbehaving implementations:

```rust
#[cfg(test)]
mod adversarial_tests {
    struct PanicOnSecondDeref {
        count: Cell<usize>,
        value: String,
    }

    impl Deref for PanicOnSecondDeref {
        type Target = String;
        fn deref(&self) -> &String {
            let count = self.count.get();
            self.count.set(count + 1);
            if count > 0 {
                panic!("adversarial deref");
            }
            &self.value
        }
    }

    #[test]
    fn custom_type_handles_panicking_deref() {
        let adversarial = PanicOnSecondDeref {
            count: Cell::new(0),
            value: "test".to_string(),
        };

        // Your unsafe abstraction must not cause UB here
        let result = std::panic::catch_unwind(|| {
            your_unsafe_abstraction(&adversarial)
        });

        // Either succeeds or panics, but never UB
        assert!(result.is_ok() || result.is_err());
    }
}
```

If a closure panics, your abstraction must become invalid (e.g., poisoned like `Mutex`), but must never cause undefined behavior.

**4. Document safety invariants in plain text**

Every `unsafe` block requires a comment explaining:
- What invariants must hold for safety
- Why those invariants are satisfied in this context
- What would happen if they were violated

```rust
pub fn process_measurements(data: &[f64]) -> f64 {
    if data.is_empty() {
        return 0.0;
    }

    // SAFETY: data.len() > 0 verified by check above.
    // get_unchecked avoids redundant bounds check in tight loop.
    // Would cause UB if data were empty, but that case handled.
    unsafe {
        data.get_unchecked(0)
    }
}
```

Insufficient documentation:
```rust
unsafe { data.get_unchecked(0) } // SAFETY: should be fine
```

The reasoning must be detailed enough for reviewers to verify correctness.

**5. Pass Miri including adversarial tests**

[Miri](https://github.com/rust-lang/miri) is Rust's undefined behavior detector.
All unsafe code must pass Miri without warnings:

```bash
cargo +nightly miri test
```

Run Miri on:
- Normal test cases
- Edge cases (empty collections, zero values, maximum sizes)
- Adversarial tests (panicking traits, misbehaving implementations)

Miri failures indicate undefined behavior that must be fixed before merging.

**6. Follow official unsafe code guidelines**

Study and follow the [Rust Unsafe Code Guidelines](https://rust-lang.github.io/unsafe-code-guidelines/).
Key resources:
- [The Rustonomicon](https://doc.rust-lang.org/nightly/nomicon/)
- [Unsafe Code Guidelines Reference](https://rust-lang.github.io/unsafe-code-guidelines/)
- [Adversarial Code Patterns](https://cheats.rs/#adversarial-code)

### Performance: validation requirements

Using unsafe for performance requires the same rigor as novel abstractions plus benchmark evidence:

**1. Benchmark first**

Prove the unsafe optimization provides meaningful benefit:

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_safe_version(c: &mut Criterion) {
    let data: Vec<f64> = (0..1000).map(|x| x as f64).collect();
    c.bench_function("safe_get", |b| {
        b.iter(|| {
            black_box(&data)[black_box(500)]
        })
    });
}

fn bench_unsafe_version(c: &mut Criterion) {
    let data: Vec<f64> = (0..1000).map(|x| x as f64).collect();
    c.bench_function("unsafe_get", |b| {
        b.iter(|| {
            unsafe { black_box(&data).get_unchecked(black_box(500)) }
        })
    });
}

criterion_group!(benches, bench_safe_version, bench_unsafe_version);
criterion_main!(benches);
```

Only proceed if:
- The unsafe version shows significant improvement (>20% faster)
- The operation is in a verified hot path (profiling data)
- Safe alternatives have been exhausted

**2. Document safety reasoning**

Same requirements as novel abstractions: plain-text explanation of invariants.

**3. Pass Miri**

Performance-related unsafe must pass Miri.
Use Miri to verify the optimization is sound across all inputs.

**4. Consider safe alternatives first**

Before using unsafe for performance:
- Profile to identify actual bottlenecks
- Try algorithmic improvements
- Use better data structures
- Enable link-time optimization (LTO)
- Try `#[inline]` and other safe optimizations

Many "necessary" unsafe optimizations become unnecessary with proper profiling and algorithm choice.

### FFI: validation requirements

When calling foreign functions, follow these requirements:

**1. Prefer established interop libraries**

Use proven bindings when available:
- Windows API: `windows` crate
- POSIX systems: `libc` crate
- Common C libraries: search crates.io first

Only create custom FFI bindings when no maintained alternative exists.

**2. Document permissible call patterns**

Generated bindings are unsafe by default.
Document which patterns are safe in practice:

```rust
extern "C" {
    // SAFETY: ptr must point to valid, initialized MyStruct.
    // The struct must remain valid for the entire call.
    // Not thread-safe: must not be called concurrently with other API calls.
    fn external_process(ptr: *mut MyStruct) -> i32;
}

pub fn process(data: &mut MyStruct) -> Result<(), ExternalError> {
    // SAFETY: data is a valid reference, therefore points to valid MyStruct.
    // Borrow checker ensures it remains valid for the call.
    // We hold the mutex, so no concurrent calls possible.
    let result = unsafe { external_process(data as *mut MyStruct) };

    if result == 0 {
        Ok(())
    } else {
        Err(ExternalError::from_code(result))
    }
}
```

**3. Follow unsafe code guidelines**

FFI code must follow the same safety requirements as novel abstractions.

### Zero-tolerance policy for unsound code

Unsound code is _safe-looking_ code that can cause undefined behavior when called from safe code.

**What is unsoundness**:

A function is unsound if:
1. Its signature does not use the `unsafe` keyword, AND
2. Any calling pattern can cause undefined behavior

This applies even if causing UB requires "weird code" or "remote theoretical possibility."
The standard is strict: if UB is possible from safe code, the abstraction is unsound.

**Examples of unsound code**:

```rust
// Unsound: safe signature, but causes UB if T is smaller than u128
fn unsound_ref<T>(x: &T) -> &u128 {
    unsafe { std::mem::transmute(x) }
}

// Unsound: safe signature, but violates Send contract
struct AlwaysSend<T>(T);
unsafe impl<T> Send for AlwaysSend<T> {}
// If T is !Send (e.g., contains Rc), this creates data races

// Unsound: safe signature, but assumes Vec is non-empty
pub fn first_element<T>(vec: &Vec<T>) -> &T {
    unsafe { vec.get_unchecked(0) }
    // UB when called with empty Vec
}
```

**How to fix unsound code**:

If you cannot safely encapsulate something, expose an `unsafe` function and document proper usage:

```rust
// Sound: unsafe signature documents requirements
pub unsafe fn first_element_unchecked<T>(vec: &Vec<T>) -> &T {
    // SAFETY: Caller must ensure vec.len() > 0
    vec.get_unchecked(0)
}

// Or better: use safe wrapper with Result
pub fn first_element<T>(vec: &Vec<T>) -> Option<&T> {
    vec.first()
}

// Or best: use NonEmpty type to encode requirement
pub fn first_element<T>(vec: &NonEmpty<T>) -> &T {
    vec.first() // Always safe
}
```

**No exceptions**:

While most guidelines permit exceptions with sufficient justification, unsoundness has no exceptions.
Unsound code is never acceptable under any circumstances.

If you discover unsound code:
1. File a critical bug immediately
2. Mark affected code `unsafe` if temporary fix is needed
3. Redesign the abstraction to be sound or remove it

The zero-tolerance policy exists because unsound abstractions create undefined behavior without warning, making debugging nearly impossible and creating severe security vulnerabilities.

### Summary: unsafe checklist

Before using `unsafe`, verify:

- [ ] I have one of the three valid reasons (novel abstraction, performance, FFI)
- [ ] I have verified no safe alternative exists
- [ ] I have benchmarked if using for performance
- [ ] The unsafe code is in a minimal, isolated module
- [ ] Every unsafe block has detailed safety documentation
- [ ] I have written adversarial test cases
- [ ] All tests pass under Miri
- [ ] The public API is safe (no unsafe leaking to callers)
- [ ] The abstraction is sound (cannot cause UB from safe code)

If any item is unchecked, do not proceed with unsafe.
The burden of proof is on the author to demonstrate safety.

### Relationship to other type-safety patterns

The type-safety principles in domain-modeling.md and rust-development.md work together:

1. **Smart constructors** (domain-modeling.md): Encode validation in types to avoid runtime checks that might tempt unsafe shortcuts
2. **State machines** (domain-modeling.md): Make invalid states unrepresentable, eliminating need to unsafely manipulate state
3. **Result types** (rust-development.md): Explicit error handling prevents bypassing safety with unwrap/expect in unsafe contexts
4. **Ownership and borrowing** (rust-development.md): Core safety guarantees that unsafe code must preserve

Good type design makes unsafe code unnecessary in most domains.
When unsafe is genuinely required, these patterns help isolate it in minimal, well-tested modules with safe public interfaces.

### Further reading

**Official Rust resources**:
- [The Rustonomicon](https://doc.rust-lang.org/nightly/nomicon/) - The dark arts of unsafe Rust
- [Unsafe Code Guidelines](https://rust-lang.github.io/unsafe-code-guidelines/) - Official reference
- [Miri documentation](https://github.com/rust-lang/miri) - UB detection tool

**Safety concepts**:
- [Unsafe, Unsound, Undefined](https://cheats.rs/#unsafe-unsound-undefined) - Terminology reference
- [Adversarial Code Patterns](https://cheats.rs/#adversarial-code) - Testing malicious inputs

**Related documentation**:
- domain-modeling.md - Type-safe domain modeling patterns
- architectural-patterns.md - Isolating effects and unsafe code at boundaries
- theoretical-foundations.md - Category-theoretic foundations for safety reasoning
