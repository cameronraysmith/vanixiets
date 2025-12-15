## Panic semantics

Panics in Rust are not exceptions or a form of error communication.
A panic means program termination, a request to stop execution immediately because the system has entered an invalid state from which it cannot meaningfully continue.

### Core principle

Following Microsoft guideline M-PANIC-IS-STOP: panics suggest immediate program termination.
Although code must be panic-safe (survived panics may not lead to inconsistent state), invoking a panic means this program should stop now.
It is never valid to use panics to communicate errors upstream or as a control flow mechanism.

### When panics are appropriate

Panics are appropriate only when:

**1. Detected programming errors (contract violations)** - Following M-PANIC-ON-BUG, when an unrecoverable programming error has been detected, code must panic to request program termination.
No Error type should be introduced or returned, as such errors cannot be acted upon at runtime.

```rust
// Contract violation detected during existing check
pub fn divide_non_zero(numerator: i32, denominator: i32) -> i32 {
    assert!(denominator != 0, "denominator must be non-zero");
    numerator / denominator
}

// Broken invariant in internal state
pub fn get_validated_data(&self) -> &Data {
    self.validated_data.as_ref()
        .expect("invariant broken: validated_data must be Some after validation")
}

// Index known to be in bounds by construction
fn process_matrix_cell(&self, row: usize, col: usize) -> f64 {
    debug_assert!(row < self.rows && col < self.cols,
        "programming error: indices out of bounds");
    self.data[row * self.cols + col]
}
```

**2. Const contexts** - Operations invoked from const contexts that cannot return Result must panic on failure.

```rust
const CONFIG_VERSION: u32 = const {
    parse_version("1.0.0").unwrap()  // Must be valid at compile time
};
```

**3. User-requested panics** - When providing API methods explicitly documented to panic, typically unwrap-style convenience methods.

```rust
impl QualityScore {
    /// Returns the inner value.
    ///
    /// Panics if the Result is an error.
    pub fn unwrap(self) -> f64 {
        match self {
            QualityScore::Valid(value) => value,
            QualityScore::Invalid(reason) => panic!("called unwrap on invalid score: {}", reason),
        }
    }
}
```

**4. Poison detection** - When encountering a poisoned lock, which signals another thread has already panicked.

```rust
let data = lock.lock()
    .unwrap();  // Appropriate: poisoned lock indicates corrupted state
```

### When panics are inappropriate

Never use panics for these scenarios - use Result instead:

**1. User input validation** - Parseable data from users should return validation errors, not panic.

```rust
// BAD: User input should not panic
pub fn create_email(input: &str) -> EmailAddress {
    assert!(input.contains('@'), "email must contain @");
    EmailAddress(input.to_string())
}

// GOOD: Return Result for validation
pub fn create_email(input: &str) -> Result<EmailAddress, ValidationError> {
    if !input.contains('@') {
        return Err(ValidationError::InvalidFormat {
            field: "email".to_string(),
            message: "must contain @".to_string(),
        });
    }
    Ok(EmailAddress(input.to_string()))
}
```

**2. I/O operations** - File operations, network requests, database queries should return Result.

```rust
// BAD: I/O can fail for non-programming reasons
pub fn read_config() -> Config {
    let contents = std::fs::read_to_string("config.toml")
        .expect("config must exist");
    toml::from_str(&contents).expect("config must be valid")
}

// GOOD: I/O failures are infrastructure errors
pub fn read_config() -> Result<Config, ConfigError> {
    let contents = std::fs::read_to_string("config.toml")
        .map_err(|e| ConfigError::ReadFailed(e.to_string()))?;
    toml::from_str(&contents)
        .map_err(|e| ConfigError::ParseFailed(e.to_string()))
}
```

**3. Parseable data** - Parsing structured data that might be malformed should return Result.

```rust
// BAD: Parsing is not a programming error
pub fn parse_uri(s: &str) -> Uri {
    Uri::from_str(s).unwrap()
}

// GOOD: Parsing can fail legitimately
pub fn parse_uri(s: &str) -> Result<Uri, ParseError> {
    Uri::from_str(s)
}
```

### Integration with FDM error classification

Panic semantics align with the three-tier error classification from functional domain modeling:

**Domain errors → Result** - Expected outcomes of domain operations that subject matter experts recognize.

```rust
#[derive(Error, Debug)]
pub enum CalibrationError {
    #[error("quality {quality_score} below threshold {threshold}")]
    BelowThreshold { quality_score: f64, threshold: f64 },
}

pub fn calibrate(
    quality_threshold: f64,
    raw: RawObservations,
) -> Result<CalibratedData, CalibrationError> {
    // Domain error: quality too low (not a panic)
    if quality_score < quality_threshold {
        return Err(CalibrationError::BelowThreshold {
            quality_score,
            threshold: quality_threshold,
        });
    }
    Ok(CalibratedData { /* ... */ })
}
```

**Infrastructure errors → Result or propagate** - Technical failures in supporting systems.

```rust
#[derive(Error, Debug)]
pub enum InfrastructureError {
    #[error("database operation '{operation}' failed: {exception}")]
    DatabaseFailed { operation: String, exception: String },
}

pub async fn save_to_database(
    data: &Data,
) -> Result<SavedData, InfrastructureError> {
    db.execute(/* ... */)
        .await
        .map_err(|e| InfrastructureError::DatabaseFailed {
            operation: "save".to_string(),
            exception: e.to_string(),
        })
}
```

**Panics → true programming bugs only** - Broken invariants, impossible states reached.

```rust
pub struct Dataset {
    observations: Vec<Observation>,
    statistics: SummaryStatistics,
}

impl Dataset {
    /// Smart constructor enforces invariant: at least one observation
    pub fn new(observations: Vec<Observation>) -> Result<Self, String> {
        if observations.is_empty() {
            return Err("must provide at least one observation".to_string());
        }
        Ok(Self {
            observations,
            statistics: Self::compute_stats(&observations),
        })
    }

    /// This method's precondition is guaranteed by smart constructor
    pub fn mean(&self) -> f64 {
        // Panic is appropriate here: empty dataset violates invariant
        assert!(!self.observations.is_empty(),
            "invariant broken: dataset cannot be empty");
        self.statistics.mean
    }
}
```

### The relationship between types and panics

Good type design reduces panic surface by making invalid states unrepresentable.

**Anti-pattern: Runtime checks with panics**

```rust
pub struct PositiveFloat(f64);

impl PositiveFloat {
    pub fn new(value: f64) -> Self {
        assert!(value > 0.0, "must be positive");
        PositiveFloat(value)
    }

    pub fn value(&self) -> f64 {
        assert!(self.0 > 0.0, "invariant: must be positive");  // Redundant!
        self.0
    }
}
```

**Better: Smart constructor guarantees invariant**

```rust
pub struct PositiveFloat(f64);

impl PositiveFloat {
    /// Smart constructor validates once
    pub fn new(value: f64) -> Result<Self, String> {
        if value <= 0.0 {
            return Err(format!("must be positive, got {}", value));
        }
        Ok(PositiveFloat(value))
    }

    /// No assertion needed: constructor guarantees invariant
    pub fn value(&self) -> f64 {
        self.0  // Safe by construction
    }
}
```

**Best: Type system enforces constraint**

```rust
use std::num::NonZeroU32;

pub struct PositiveCount(NonZeroU32);

impl PositiveCount {
    pub fn new(value: u32) -> Result<Self, String> {
        NonZeroU32::new(value)
            .map(PositiveCount)
            .ok_or_else(|| "count must be positive".to_string())
    }

    pub fn value(&self) -> u32 {
        self.0.get()  // Type system guarantees non-zero
    }
}
```

### Decision tree for error handling

When designing error handling, follow this decision process:

**Step 1: Can the caller prevent this?**
- Yes, with correct input → Document precondition, return Result for validation
- No, it's a logic error → Panic

**Step 2: Would a subject matter expert recognize this error?**
- Yes → Domain error, model explicitly with Result
- No → Continue to step 3

**Step 3: Can the program meaningfully continue?**
- Yes → Infrastructure error, consider Result or propagate exception
- No → Panic

Examples applying this tree:

```rust
// 1. Caller can prevent: return Result
pub fn create_user(email: &str, age: i32) -> Result<User, ValidationError> {
    if age < 0 {
        return Err(ValidationError::OutOfRange {
            field: "age".to_string(),
            message: "must be non-negative".to_string(),
        });
    }
    // ...
}

// 2. Domain expert recognizes: return Result
pub fn train_model(data: &TrainingData) -> Result<Model, TrainingError> {
    if !converged {
        return Err(TrainingError::FailedToConverge {
            iterations,
            final_loss,
        });
    }
    // ...
}

// 3. Cannot continue (broken invariant): panic
pub fn process_validated_batch(&self) -> Summary {
    assert!(!self.items.is_empty(),
        "invariant broken: batch must have items after validation");
    // ...
}
```

### What constitutes a violation is situational

Following M-PANIC-ON-BUG, APIs are not expected to go out of their way to detect contract violations, as such checks can be impossible or expensive.

Encountering `must_be_even == 3` during an already existing check clearly warrants a panic, while a function `parse(&str)` clearly must return a Result.

The principle: if you would already be checking this condition for correctness, and it fails, that's a programming error.
If you would need to add expensive validation solely to panic, return Result instead.

```rust
// Already checking index bounds for correctness
pub fn get_cell(&self, row: usize, col: usize) -> f64 {
    assert!(row < self.rows && col < self.cols,
        "index out of bounds");
    self.data[row * self.cols + col]
}

// Would be expensive to validate entire URI grammar just to panic
pub fn parse_uri(s: &str) -> Result<Uri, ParseError> {
    // Return Result instead of adding expensive checks + panic
    // ...
}
```

### Make it correct by construction

While panicking on a detected programming error is the least bad option, your panic might still ruin someone's day.
For any user input or calling sequence that would otherwise panic, explore using the type system to avoid panicking code paths altogether.

```rust
// Anti-pattern: panics possible
pub fn process_data(values: Vec<f64>, count: usize) -> Summary {
    assert!(count > 0, "count must be positive");
    assert!(values.len() == count, "length must match count");
    // ...
}

// Better: smart constructor prevents panics
pub struct ValidatedInput {
    values: NonEmptyVec<f64>,
}

impl ValidatedInput {
    pub fn new(values: Vec<f64>) -> Result<Self, ValidationError> {
        NonEmptyVec::new(values)
            .map(|v| Self { values: v })
            .map_err(|_| ValidationError::EmptyInput)
    }
}

pub fn process_data(input: ValidatedInput) -> Summary {
    // No panics possible: type guarantees valid state
    // ...
}
```

### Integration with testing

Use should_panic tests for operations that document panic conditions:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[should_panic(expected = "denominator must be non-zero")]
    fn test_divide_zero_panics() {
        divide_non_zero(10, 0);
    }

    #[test]
    fn test_divide_non_zero_succeeds() {
        assert_eq!(divide_non_zero(10, 2), 5);
    }
}
```

### Further reading

See domain-modeling.md Pattern 6 for error classification framework.
See railway-oriented-programming.md for Result composition patterns.
See architectural-patterns.md for effect isolation at boundaries.
See Microsoft Rust Guidelines M-PANIC-IS-STOP and M-PANIC-ON-BUG for authoritative guidance.
