# Testing

## Unit tests and test organization

Write unit tests in the same file using `#[cfg(test)]` modules.
This keeps tests close to implementation and allows testing private functions.

```rust
pub fn process_data(input: &[u8]) -> Result<Vec<u8>, ProcessingError> {
    // implementation
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_process_data_valid_input() {
        let input = b"test data";
        let result = process_data(input);
        assert!(result.is_ok());
    }

    #[test]
    fn test_process_data_invalid_input() {
        let input = b"";
        let result = process_data(input);
        assert!(result.is_err());
    }
}
```

Create integration tests in `tests/` directory.
These verify public API works correctly without access to private implementation details.

## Mockable I/O pattern (sans-io)

Any user-facing type doing I/O or system calls with side effects should be mockable to these effects.
This includes file and network access, clocks, entropy sources.
More generally, any operation that is non-deterministic, reliant on external state, depending on hardware or environment, or otherwise fragile should be mockable.

Libraries supporting inherent mocking should implement it using runtime abstraction via enum with `Native` and `Mock` variants.

**Pattern: Library returns (Lib, MockHandle) tuple**

```rust
pub struct Library {
    core: LibraryCore  // Encapsulates syscalls, I/O
}

impl Library {
    pub fn new() -> Self {
        Self {
            core: LibraryCore::Native,
        }
    }

    #[cfg(feature = "test-util")]
    pub fn new_mocked() -> (Self, MockCtrl) {
        let mock_ctrl = MockCtrl::new();
        let lib = Self {
            core: LibraryCore::Mocked(mock_ctrl.clone()),
        };
        (lib, mock_ctrl)
    }

    pub fn read_data(&self) -> Vec<u8> {
        self.core.read_data()
    }
}

// Dispatches calls either to operating system or mocking controller
enum LibraryCore {
    Native,

    #[cfg(feature = "test-util")]
    Mocked(MockCtrl),
}

impl LibraryCore {
    fn read_data(&self) -> Vec<u8> {
        match self {
            Self::Native => {
                // Actual I/O operation
                std::fs::read("data.bin").unwrap_or_default()
            }
            #[cfg(feature = "test-util")]
            Self::Mocked(m) => m.read_data(),
        }
    }
}

#[cfg(feature = "test-util")]
#[derive(Clone)]
pub struct MockCtrl {
    inner: std::sync::Arc<MockCtrlInner>,
}

#[cfg(feature = "test-util")]
impl MockCtrl {
    fn new() -> Self {
        Self {
            inner: std::sync::Arc::new(MockCtrlInner {
                data: std::sync::Mutex::new(Vec::new()),
            }),
        }
    }

    pub fn set_data(&self, data: Vec<u8>) {
        *self.inner.data.lock().unwrap() = data;
    }

    fn read_data(&self) -> Vec<u8> {
        self.inner.data.lock().unwrap().clone()
    }
}

#[cfg(feature = "test-util")]
struct MockCtrlInner {
    data: std::sync::Mutex<Vec<u8>>,
}
```

**Why tuple return `(Lib, MockHandle)` instead of accepting MockHandle**: Prevents state ambiguity if multiple instances shared a single controller.

**When to use traits vs enums for abstraction**:

1. **Enum with Native/Mock variants (preferred for testing)**: If the other implementation is only concerned with providing sans-io implementation for testing, implement your type as an enum.
2. **Traits (for extensibility)**: If users are expected to provide custom implementations beyond just testing, introduce narrow traits.
3. **Dynamic dispatch (last resort)**: Only when generics become a nesting problem, consider `dyn Trait`.

**Sans-io for one-shot I/O**: Functions that only need one-shot I/O during initialization should accept `impl Read` or `impl Write` rather than concrete file types.

```rust
// Good: Accepts File, TcpStream, &[u8], and many more
fn parse_data(data: impl std::io::Read) -> Result<Data, ParseError> {
    // ...
}
```

For async functions targeting multiple runtimes, use `futures::io::AsyncRead` and `futures::io::AsyncWrite`.

## Feature-gated test utilities

Testing functionality must be guarded behind a feature flag to prevent production builds from accidentally bypassing safety checks.

**Use single feature flag named `test-util`**

```toml
# Cargo.toml
[features]
test-util = []
```

**What to gate behind `test-util`**:
- Mocking functionality (mock controllers, mock variants)
- Ability to inspect sensitive data
- Safety check overrides
- Fake data generators

```rust
impl HttpClient {
    pub fn get(&self, url: &str) -> Result<Response, Error> {
        // Normal implementation with certificate verification
    }

    #[cfg(feature = "test-util")]
    pub fn bypass_certificate_checks(&mut self) {
        // Only available in test builds
    }
}

#[cfg(feature = "test-util")]
pub fn generate_fake_user(seed: u64) -> User {
    // Deterministic fake data generation for tests
}
```

## Testing domain models from FDM patterns

### Testing smart constructor validation

Smart constructors enforce invariants at creation time.
Test both valid construction and validation failures.

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quality_score_accepts_valid_range() {
        let score = QualityScore::new(0.5);
        assert!(score.is_ok());
        assert_eq!(score.unwrap().value(), 0.5);
    }

    #[test]
    fn quality_score_rejects_above_one() {
        let score = QualityScore::new(1.5);
        assert!(score.is_err());
    }

    #[test]
    fn measurement_enforces_cross_field_validation() {
        // Uncertainty too large relative to value should fail
        let result = Measurement::new(10.0, 150.0, 0.95);
        assert!(result.is_err());
    }
}
```

### Testing state machine transitions

Test valid transitions and verify impossible transitions are prevented by the type system.

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_transition_raw_to_calibrated() {
        let raw = RawObservations {
            values: vec![1.0, 2.0, 3.0],
            metadata: HashMap::new(),
        };

        let calibration_model = |v: f64, _: &HashMap<String, String>| {
            (v * 1.1, v * 0.05, 0.95)
        };

        let result = calibrate(calibration_model, 0.8, raw);
        assert!(result.is_ok());
    }

    #[test]
    fn calibration_fails_below_quality_threshold() {
        let raw = RawObservations {
            values: vec![1.0],
            metadata: HashMap::new(),
        };

        // Model returns quality below threshold
        let calibration_model = |v: f64, _: &HashMap<String, String>| {
            (v, v * 0.05, 0.5)  // quality = 0.5
        };

        let result = calibrate(calibration_model, 0.8, raw);
        assert!(result.is_err());
        match result {
            Err(CalibrationError::QualityBelowThreshold(quality, threshold)) => {
                assert_eq!(quality, 0.5);
                assert_eq!(threshold, 0.8);
            }
            _ => panic!("Expected QualityBelowThreshold error"),
        }
    }

    // Note: Invalid transitions like "deploy unvalidated model" are
    // prevented by the type system and won't compile, so no test needed
}
```

### Property-based testing for invariants

Use `proptest` or `quickcheck` to verify invariants hold across many generated examples.

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn quality_score_always_in_range(value in 0.0f64..=1.0) {
        let score = QualityScore::new(value).unwrap();
        prop_assert!(score.value() >= 0.0 && score.value() <= 1.0);
    }

    #[test]
    fn dataset_statistics_consistent(
        values in prop::collection::vec(any::<f64>(), 1..100)
    ) {
        let observations: Vec<Observation> = values.iter().map(|&v| {
            Observation {
                timestamp: Utc::now(),
                value: v,
                metadata: HashMap::new(),
            }
        }).collect();

        let dataset = Dataset::new(
            DatasetId::new("test".to_string()).unwrap(),
            observations,
            "protocol-001".to_string(),
        ).unwrap();

        let stats = dataset.statistics();
        prop_assert_eq!(stats.count, values.len());

        // Mean should be between min and max
        prop_assert!(stats.mean >= stats.min_value);
        prop_assert!(stats.mean <= stats.max_value);
    }
}
```

Property-based testing is especially valuable for:
- Smart constructor invariants (value ranges, format constraints)
- Aggregate consistency (computed values match underlying data)
- Workflow composition (chaining operations maintains type safety)
- Round-trip properties (serialize then deserialize equals original)

### Testing domain errors vs infrastructure errors

Test that domain errors are returned in expected scenarios and contain appropriate context.

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn domain_error_calibration_low_quality() {
        let raw = create_low_quality_observations();
        let result = calibrate(calibration_model, 0.95, raw);

        assert!(result.is_err());
        let err = result.unwrap_err();

        match err {
            CalibrationError::QualityBelowThreshold { quality_score, threshold } => {
                assert!(quality_score < threshold);
            }
            _ => panic!("Expected CalibrationError::QualityBelowThreshold"),
        }
    }

    #[test]
    #[cfg(feature = "test-util")]
    fn infrastructure_error_database_unavailable() {
        let (mut repo, mock) = Repository::new_mocked();
        mock.set_database_available(false);

        let result = repo.save_model(test_model());

        assert!(matches!(
            result,
            Err(InfrastructureError::Database(_))
        ));
    }
}
```

## Test execution and tooling

Use `cargo test` to run all tests before committing.

Consider `cargo nextest` for faster test execution with better output:

```bash
cargo nextest run
```

Benefits: runs tests in parallel more efficiently, cleaner output, better failure reporting, JUnit output for CI.

## Doc tests

Write doc tests to ensure documentation examples stay current and compile.

```rust
/// Processes observations through calibration pipeline.
///
/// # Examples
///
/// ```
/// use my_crate::{RawObservations, calibrate};
///
/// let raw = RawObservations {
///     values: vec![1.0, 2.0, 3.0],
///     metadata: Default::default(),
/// };
///
/// let result = calibrate(
///     |v, _| (v * 1.1, v * 0.05, 0.95),
///     0.8,
///     raw,
/// );
/// assert!(result.is_ok());
/// ```
pub fn calibrate<F>(
    calibration_model: F,
    quality_threshold: f64,
    raw: RawObservations,
) -> Result<CalibratedData, CalibrationError>
where
    F: Fn(f64, &HashMap<String, String>) -> (f64, f64, f64),
{
    // implementation
}
```

Doc tests automatically run with `cargo test` and serve dual purpose as documentation and verification.

## Test coverage

Aim for high test coverage, especially for:
- Public APIs (all public functions should have tests)
- Smart constructor validation logic
- State transition functions
- Error handling paths
- Domain invariant enforcement

Use `cargo tarpaulin` or `cargo llvm-cov` to measure coverage:

```bash
# Using tarpaulin
cargo tarpaulin --out Html

# Using llvm-cov
cargo llvm-cov --html
```

Focus coverage efforts on domain logic, public API surface, error paths, and boundary conditions.
Less critical: simple getters/setters, trivial type conversions, generated code.

## Testing patterns summary

- **Unit tests**: Same file, `#[cfg(test)]` modules, test private implementation
- **Integration tests**: `tests/` directory, verify public API
- **Mockable I/O**: Enum with `Native`/`Mock` variants, feature-gated mock utilities
- **Sans-io**: Accept `impl Read`/`impl Write` for composability
- **Smart constructors**: Test valid construction and validation failures
- **State machines**: Test valid transitions, rely on type system to prevent invalid ones
- **Property-based**: Use proptest/quickcheck to verify invariants
- **Domain errors**: Test expected failure scenarios return appropriate error variants
- **Doc tests**: Ensure examples compile and demonstrate correct usage
- **Coverage**: Focus on domain logic, public APIs, and error paths
