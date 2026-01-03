# Python Development

## Architectural patterns alignment

See @~/.claude/commands/preferences/architectural-patterns.md for overarching principles.

Python can approximate functional programming patterns through careful library selection and disciplined type usage.

### Recommended libraries for functional programming
- **Type checking**: `basedpyright` for static analysis, `beartype` for runtime validation
- **Functional utilities**: `Expression` (dbrattli/Expression) for functional composition and monadic patterns
- **Error handling**: Use `Result`/`Option` types from Expression instead of exceptions for composable error handling
- **Immutability**: `attrs` with `frozen=True` or `dataclasses` with `frozen=True` for immutable data structures
- **Type-level programming**: Leverage Python's type system with `typing` module extensions

### Functional programming patterns
- Prefer pure functions without side effects where possible
- Encode effects explicitly in function signatures and return types
- Use `Result[T, E]` and `Option[T]` for error handling instead of exceptions
- Thread state explicitly through function parameters or state monads
- Isolate IO and side effects to specific layers or boundaries

For detailed patterns on Result types, error composition, and ADT modeling in Python:
- **~/.claude/commands/preferences/railway-oriented-programming.md** - Result type implementation, bind/apply, async effects
- **~/.claude/commands/preferences/algebraic-data-types.md** - Discriminated unions with Pydantic, newtypes, domain modeling

## Functional domain modeling in Python

This section demonstrates how to implement functional domain modeling patterns in Python.
For pattern descriptions, see domain-modeling.md.
For theoretical foundations, see theoretical-foundations.md.

### Pattern 1: Smart constructors with Pydantic

Use Pydantic validators to create types with guaranteed invariants.

**Example: Validated measurement types**

```python
from pydantic import BaseModel, field_validator, model_validator
from typing import Self

class QualityScore(BaseModel):
    """Quality score constrained to [0, 1] range."""
    value: float

    @field_validator('value')
    @classmethod
    def must_be_in_range(cls, v: float) -> float:
        if not 0 <= v <= 1:
            raise ValueError(f'quality score must be in [0,1], got {v}')
        return v

    def __repr__(self) -> str:
        return f"QualityScore({self.value})"


class Uncertainty(BaseModel):
    """Uncertainty must be positive."""
    value: float

    @field_validator('value')
    @classmethod
    def must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f'uncertainty must be positive, got {v}')
        return v


class Measurement(BaseModel):
    """Validated measurement with constraints enforced at construction."""
    value: float
    uncertainty: Uncertainty
    quality_score: QualityScore

    @model_validator(mode='after')
    def check_reasonable_uncertainty(self) -> Self:
        """Ensure uncertainty is not larger than measurement itself."""
        if abs(self.uncertainty.value) > abs(self.value) * 10:
            raise ValueError(
                f'uncertainty {self.uncertainty.value} is too large '
                f'relative to value {self.value}'
            )
        return self


# Usage: validation happens at construction
try:
    m = Measurement(
        value=10.0,
        uncertainty=Uncertainty(value=0.5),
        quality_score=QualityScore(value=0.95)
    )
    # m is guaranteed valid - no need to re-check
except ValueError as e:
    # Handle invalid input
    print(f"Invalid measurement: {e}")
```

**Private constructor pattern for Result-based validation**

```python
from expression import Result, Ok, Error
from typing import ClassVar

class EmailAddress(BaseModel):
    """Email address validated at construction."""
    _value: str

    # Make default constructor private by convention
    model_config = {"frozen": True}

    @classmethod
    def create(cls, email: str) -> Result['EmailAddress', str]:
        """
        Smart constructor that returns Result.

        Args:
            email: Raw email string to validate

        Returns:
            Ok(EmailAddress) if valid, Error(str) if invalid
        """
        email = email.strip().lower()

        if not email:
            return Error("email cannot be empty")

        if '@' not in email:
            return Error("email must contain @")

        if '.' not in email.split('@')[1]:
            return Error("email domain must contain .")

        # Validation passed, construct instance
        instance = cls.model_construct(_value=email)
        return Ok(instance)

    @property
    def value(self) -> str:
        """Get the validated email string."""
        return self._value


# Usage
match EmailAddress.create("user@example.com"):
    case Ok(email):
        print(f"Valid: {email.value}")
    case Error(msg):
        print(f"Invalid: {msg}")
```

**See also**: domain-modeling.md#pattern-2-smart-constructors-for-invariants

### Pattern 2: State machines with discriminated unions

Use discriminated unions (Python 3.10+) to model entity lifecycles.

**Example: Data processing pipeline states**

```python
from typing import Literal
from pydantic import BaseModel
from dataclasses import dataclass

# State 1: Raw observations
class RawObservations(BaseModel):
    """Unvalidated measurements, may contain artifacts."""
    type: Literal["raw"] = "raw"
    values: list[float]
    metadata: dict[str, str]


# State 2: Calibrated data
class CalibratedData(BaseModel):
    """Quality-controlled measurements with uncertainty quantification."""
    type: Literal["calibrated"] = "calibrated"
    measurements: list[Measurement]
    calibration_params: dict[str, float]


# State 3: Inferred results
@dataclass(frozen=True)
class InferredResults:
    """Fitted model with estimated parameters."""
    type: Literal["inferred"] = "inferred"
    parameters: dict[str, float]
    log_likelihood: float
    convergence_info: dict[str, bool]


# State 4: Validated model
@dataclass(frozen=True)
class ValidatedModel:
    """Model that passed convergence diagnostics."""
    type: Literal["validated"] = "validated"
    parameters: dict[str, float]
    diagnostics: dict[str, float]
    validation_timestamp: str


# Discriminated union of all states
DataState = RawObservations | CalibratedData | InferredResults | ValidatedModel


# Pattern matching based on state
def get_state_description(state: DataState) -> str:
    """Pattern match on current state."""
    match state:
        case RawObservations(values=vals):
            return f"Raw: {len(vals)} observations"
        case CalibratedData(measurements=meas):
            return f"Calibrated: {len(meas)} measurements"
        case InferredResults(parameters=params):
            return f"Inferred: {len(params)} parameters"
        case ValidatedModel(diagnostics=diag):
            return f"Validated: {len(diag)} diagnostics"
```

**State transitions as functions**

```python
from expression import Result, Ok, Error

# Error types for each transition
class CalibrationError(Exception):
    """Calibration failed."""
    pass


class InferenceError(Exception):
    """Inference failed."""
    pass


class ValidationError(Exception):
    """Validation failed."""
    pass


# Transition 1: Raw → Calibrated
def calibrate(
    calibration_model: Callable[[float, dict], tuple[float, float, float]],
    quality_threshold: float,
    raw: RawObservations
) -> Result[CalibratedData, CalibrationError]:
    """
    Transform raw observations into calibrated measurements.

    Args:
        calibration_model: Function mapping (raw_value, metadata) →
                          (value, uncertainty, quality)
        quality_threshold: Minimum acceptable quality score
        raw: Raw observations to calibrate

    Returns:
        Ok(CalibratedData) if all measurements pass quality threshold
        Error(CalibrationError) if calibration fails
    """
    try:
        measurements = []
        for raw_value in raw.values:
            val, unc, qual = calibration_model(raw_value, raw.metadata)

            if qual < quality_threshold:
                return Error(CalibrationError(
                    f"Quality {qual} below threshold {quality_threshold}"
                ))

            measurements.append(Measurement(
                value=val,
                uncertainty=Uncertainty(value=unc),
                quality_score=QualityScore(value=qual)
            ))

        return Ok(CalibratedData(
            type="calibrated",
            measurements=measurements,
            calibration_params={"model": calibration_model.__name__}
        ))

    except Exception as e:
        return Error(CalibrationError(f"Calibration failed: {e}"))


# Transition 2: Calibrated → Inferred
def infer(
    inference_algorithm: Callable[[list[Measurement]], dict],
    calibrated: CalibratedData
) -> Result[InferredResults, InferenceError]:
    """
    Infer model parameters from calibrated data.

    Args:
        inference_algorithm: Function mapping measurements → parameters
        calibrated: Calibrated data

    Returns:
        Ok(InferredResults) if inference succeeds
        Error(InferenceError) if inference fails
    """
    try:
        result = inference_algorithm(calibrated.measurements)

        return Ok(InferredResults(
            type="inferred",
            parameters=result["parameters"],
            log_likelihood=result["log_likelihood"],
            convergence_info=result["convergence"]
        ))

    except Exception as e:
        return Error(InferenceError(f"Inference failed: {e}"))


# Transition 3: Inferred → Validated
def validate_model(
    validation_metrics: dict[str, Callable],
    inferred: InferredResults
) -> Result[ValidatedModel, ValidationError]:
    """
    Validate inferred model against diagnostics.

    Args:
        validation_metrics: Dict of metric_name → validation_function
        inferred: Inferred results to validate

    Returns:
        Ok(ValidatedModel) if all diagnostics pass
        Error(ValidationError) if validation fails
    """
    try:
        diagnostics = {}
        for name, metric_fn in validation_metrics.items():
            diagnostics[name] = metric_fn(inferred.parameters)

        # Check all diagnostics pass threshold
        if not all(v > 0.9 for v in diagnostics.values()):
            return Error(ValidationError(
                f"Diagnostics failed: {diagnostics}"
            ))

        from datetime import datetime
        return Ok(ValidatedModel(
            type="validated",
            parameters=inferred.parameters,
            diagnostics=diagnostics,
            validation_timestamp=datetime.now().isoformat()
        ))

    except Exception as e:
        return Error(ValidationError(f"Validation failed: {e}"))
```

**See also**: domain-modeling.md#pattern-3-state-machines-for-entity-lifecycles

### Pattern 3: Workflows with dependencies

Model workflows as functions with explicit dependencies, input, and output.

**Example: Complete processing workflow**

```python
from functools import partial
from typing import Callable

# Define dependency types
CalibrationModel = Callable[[float, dict], tuple[float, float, float]]
InferenceAlgorithm = Callable[[list[Measurement]], dict]
ValidationMetrics = dict[str, Callable]


# Unified error type for entire workflow
class ProcessingError(Exception):
    """Error in processing pipeline."""

    @classmethod
    def from_calibration(cls, e: CalibrationError) -> 'ProcessingError':
        return cls(f"Calibration: {e}")

    @classmethod
    def from_inference(cls, e: InferenceError) -> 'ProcessingError':
        return cls(f"Inference: {e}")

    @classmethod
    def from_validation(cls, e: ValidationError) -> 'ProcessingError':
        return cls(f"Validation: {e}")


def process_observations(
    calibration_model: CalibrationModel,      # dependency 1
    quality_threshold: float,                 # dependency 2
    inference_algorithm: InferenceAlgorithm,  # dependency 3
    validation_metrics: ValidationMetrics,    # dependency 4
    raw: RawObservations                      # input
) -> Result[ValidatedModel, ProcessingError]: # output
    """
    Complete processing pipeline with all dependencies explicit.

    Dependencies:
    - calibration_model: Maps raw values to calibrated measurements
    - quality_threshold: Minimum acceptable quality score
    - inference_algorithm: Infers parameters from calibrated data
    - validation_metrics: Validates inferred model

    Args:
        raw: Raw observations to process

    Returns:
        Ok(ValidatedModel) if entire pipeline succeeds
        Error(ProcessingError) if any step fails
    """
    # Compose steps using bind (>>=)
    return (
        calibrate(calibration_model, quality_threshold, raw)
        .map_error(ProcessingError.from_calibration)
        .bind(lambda calibrated: infer(inference_algorithm, calibrated))
        .map_error(ProcessingError.from_inference)
        .bind(lambda inferred: validate_model(validation_metrics, inferred))
        .map_error(ProcessingError.from_validation)
    )


# Create specialized version with default dependencies
def create_default_calibration_model(
    raw: float,
    metadata: dict
) -> tuple[float, float, float]:
    """Default calibration: simple scaling."""
    value = raw * 1.1
    uncertainty = abs(value) * 0.05
    quality = 0.95
    return (value, uncertainty, quality)


def create_default_inference_algorithm(
    measurements: list[Measurement]
) -> dict:
    """Default inference: simple statistics."""
    values = [m.value for m in measurements]
    return {
        "parameters": {"mean": sum(values) / len(values)},
        "log_likelihood": -10.0,
        "convergence": {"converged": True}
    }


# Partial application creates specialized workflow
process_with_defaults = partial(
    process_observations,
    create_default_calibration_model,  # calibration_model
    0.8,                               # quality_threshold
    create_default_inference_algorithm, # inference_algorithm
    {"metric1": lambda p: 0.95}        # validation_metrics
)

# Now just: RawObservations → Result[ValidatedModel, ProcessingError]
raw_data = RawObservations(
    type="raw",
    values=[1.0, 2.0, 3.0],
    metadata={"source": "sensor_1"}
)
result = process_with_defaults(raw_data)
```

**Async workflows with AsyncResult**

```python
from expression import AsyncResult
import asyncio

async def fetch_calibration_params(
    experiment_id: str
) -> Result[dict, str]:
    """Fetch calibration parameters from remote service."""
    # Simulate async I/O
    await asyncio.sleep(0.1)
    return Ok({"baseline": 1.0, "threshold": 0.8})


async def process_observations_async(
    experiment_id: str,
    raw: RawObservations
) -> AsyncResult[ValidatedModel, ProcessingError]:
    """
    Async workflow that fetches dependencies remotely.

    Args:
        experiment_id: ID to fetch calibration params
        raw: Raw observations

    Returns:
        AsyncResult with ValidatedModel or ProcessingError
    """
    # Fetch dependencies asynchronously
    params_result = await fetch_calibration_params(experiment_id)

    # Map over result to continue pipeline
    return params_result.bind(lambda params:
        process_with_defaults(raw)
    )
```

**See also**:
- domain-modeling.md#pattern-4-workflows-as-type-safe-pipelines
- architectural-patterns.md#workflow-pipeline-architecture

### Pattern 4: Aggregates with consistency

Group related entities that must change together atomically.

**Example: Dataset aggregate with observations**

```python
from typing import Protocol
from datetime import datetime

class Observation(BaseModel):
    """Individual observation in dataset."""
    timestamp: datetime
    value: float
    metadata: dict[str, str]

    model_config = {"frozen": True}


class DatasetId(BaseModel):
    """Unique identifier for dataset."""
    value: str

    model_config = {"frozen": True}


class SummaryStatistics(BaseModel):
    """Computed statistics over observations."""
    count: int
    mean: float
    std_dev: float
    min_value: float
    max_value: float

    model_config = {"frozen": True}


class Dataset(BaseModel):
    """
    Aggregate: dataset with observations and computed statistics.

    Invariants:
    - Must have at least one observation
    - Statistics must match observations
    - Observations must be in chronological order
    """
    id: DatasetId
    observations: list[Observation]
    statistics: SummaryStatistics
    protocol_id: str  # Reference to other aggregate (by ID only)

    model_config = {"frozen": True}

    @model_validator(mode='after')
    def check_invariants(self) -> Self:
        """Enforce aggregate invariants."""
        # Must have at least one observation
        if len(self.observations) == 0:
            raise ValueError("dataset must have at least one observation")

        # Observations must be chronologically ordered
        for i in range(len(self.observations) - 1):
            if self.observations[i].timestamp > self.observations[i + 1].timestamp:
                raise ValueError("observations must be in chronological order")

        # Statistics must match observations
        values = [obs.value for obs in self.observations]
        expected_count = len(values)
        if self.statistics.count != expected_count:
            raise ValueError(
                f"statistics count {self.statistics.count} != "
                f"observation count {expected_count}"
            )

        return self

    @classmethod
    def create(
        cls,
        dataset_id: DatasetId,
        observations: list[Observation],
        protocol_id: str
    ) -> Result['Dataset', str]:
        """
        Smart constructor that computes statistics.

        Args:
            dataset_id: Unique identifier
            observations: List of observations (at least one required)
            protocol_id: Reference to protocol aggregate

        Returns:
            Ok(Dataset) if valid, Error(str) if invariants violated
        """
        if not observations:
            return Error("must provide at least one observation")

        # Sort observations chronologically
        sorted_obs = sorted(observations, key=lambda o: o.timestamp)

        # Compute statistics
        values = [obs.value for obs in sorted_obs]
        statistics = SummaryStatistics(
            count=len(values),
            mean=sum(values) / len(values),
            std_dev=(sum((x - sum(values)/len(values))**2 for x in values) / len(values))**0.5,
            min_value=min(values),
            max_value=max(values)
        )

        try:
            instance = cls(
                id=dataset_id,
                observations=sorted_obs,
                statistics=statistics,
                protocol_id=protocol_id
            )
            return Ok(instance)
        except ValueError as e:
            return Error(str(e))

    def add_observation(
        self,
        observation: Observation
    ) -> Result['Dataset', str]:
        """
        Add observation and recompute statistics (returns new dataset).

        Args:
            observation: New observation to add

        Returns:
            Ok(new Dataset) with updated observations and statistics
            Error(str) if adding would violate invariants
        """
        new_observations = self.observations + [observation]
        return Dataset.create(self.id, new_observations, self.protocol_id)


# Usage
obs1 = Observation(
    timestamp=datetime(2024, 1, 1, 10, 0),
    value=10.0,
    metadata={"sensor": "A"}
)
obs2 = Observation(
    timestamp=datetime(2024, 1, 1, 10, 5),
    value=12.0,
    metadata={"sensor": "A"}
)

dataset_result = Dataset.create(
    DatasetId(value="dataset-001"),
    [obs1, obs2],
    protocol_id="protocol-001"
)

match dataset_result:
    case Ok(dataset):
        print(f"Dataset created with {dataset.statistics.count} observations")
        print(f"Mean: {dataset.statistics.mean}")

        # Add new observation
        obs3 = Observation(
            timestamp=datetime(2024, 1, 1, 10, 10),
            value=11.0,
            metadata={"sensor": "A"}
        )
        updated_result = dataset.add_observation(obs3)

    case Error(msg):
        print(f"Failed to create dataset: {msg}")
```

**See also**: domain-modeling.md#pattern-5-aggregates-as-consistency-boundaries

### Pattern 5: Error classification

Distinguish domain errors from infrastructure errors.

**Example: Error type hierarchy**

```python
from enum import Enum
from dataclasses import dataclass

# Domain errors: Part of problem domain logic
class ValidationErrorReason(str, Enum):
    """Specific validation failure reasons."""
    OUT_OF_RANGE = "out_of_range"
    INVALID_FORMAT = "invalid_format"
    MISSING_REQUIRED = "missing_required"


@dataclass(frozen=True)
class DomainValidationError:
    """Domain error: validation failed per domain rules."""
    field: str
    reason: ValidationErrorReason
    message: str


@dataclass(frozen=True)
class DomainCalibrationError:
    """Domain error: calibration failed per domain criteria."""
    reason: str
    quality_score: float
    threshold: float


@dataclass(frozen=True)
class DomainConvergenceError:
    """Domain error: model failed to converge."""
    iterations: int
    final_loss: float
    message: str


# Infrastructure errors: Technical/architectural concerns
@dataclass(frozen=True)
class InfrastructureDatabaseError:
    """Infrastructure error: database operation failed."""
    operation: str
    exception: str


@dataclass(frozen=True)
class InfrastructureNetworkError:
    """Infrastructure error: network request failed."""
    url: str
    status_code: int | None
    exception: str


# Unified error type for workflow
DomainError = (
    DomainValidationError |
    DomainCalibrationError |
    DomainConvergenceError
)

InfrastructureError = (
    InfrastructureDatabaseError |
    InfrastructureNetworkError
)

WorkflowError = DomainError | InfrastructureError


# Functions returning specific error types
def validate_input(
    data: dict
) -> Result[RawObservations, DomainValidationError]:
    """
    Validate input data.

    Returns domain error if validation fails per domain rules.
    """
    if "values" not in data:
        return Error(DomainValidationError(
            field="values",
            reason=ValidationErrorReason.MISSING_REQUIRED,
            message="values field is required"
        ))

    if not isinstance(data["values"], list):
        return Error(DomainValidationError(
            field="values",
            reason=ValidationErrorReason.INVALID_FORMAT,
            message="values must be a list"
        ))

    return Ok(RawObservations(
        type="raw",
        values=data["values"],
        metadata=data.get("metadata", {})
    ))


async def save_to_database(
    dataset: Dataset
) -> Result[str, InfrastructureDatabaseError]:
    """
    Save dataset to database.

    Returns infrastructure error if save fails.
    """
    try:
        # Simulate database save
        await asyncio.sleep(0.01)
        return Ok(f"saved-{dataset.id.value}")
    except Exception as e:
        return Error(InfrastructureDatabaseError(
            operation="save_dataset",
            exception=str(e)
        ))


# Composing workflows with different error types
def process_and_save(
    data: dict
) -> AsyncResult[str, WorkflowError]:
    """
    Validate, process, and save data.

    Returns unified WorkflowError combining domain and infrastructure errors.
    """
    # Validate input (may return DomainValidationError)
    validation_result = validate_input(data)

    match validation_result:
        case Ok(raw):
            # Process (may return DomainCalibrationError, etc.)
            processing_result = process_with_defaults(raw)

            match processing_result:
                case Ok(validated_model):
                    # Save (may return InfrastructureDatabaseError)
                    # Note: Would need to convert ValidatedModel to Dataset
                    # This is simplified
                    return Error(InfrastructureDatabaseError(
                        operation="save",
                        exception="not implemented"
                    ))

                case Error(e):
                    # Domain error from processing
                    return Error(e)

        case Error(e):
            # Domain error from validation
            return Error(e)
```

**See also**: domain-modeling.md#pattern-7-domain-errors-vs-infrastructure-errors

### Complete example: Temporal data processing

This example brings all patterns together:

```python
"""
Complete example: Temporal data processing pipeline

Demonstrates:
- Smart constructors (validated types)
- State machines (pipeline stages)
- Workflows (composed transformations)
- Aggregates (dataset with observations)
- Error handling (domain vs infrastructure)
"""

from typing import Protocol, Callable
from pydantic import BaseModel
from expression import Result, Ok, Error
from dataclasses import dataclass
from datetime import datetime


# ============================================================================
# Domain types (smart constructors)
# ============================================================================

class ObservationValue(BaseModel):
    """Validated observation value."""
    value: float

    @field_validator('value')
    @classmethod
    def must_be_finite(cls, v: float) -> float:
        if not math.isfinite(v):
            raise ValueError('observation must be finite')
        return v

    model_config = {"frozen": True}


# ============================================================================
# State machine (pipeline stages)
# ============================================================================

# [States defined earlier: RawObservations, CalibratedData, etc.]

# ============================================================================
# Workflows (dependencies + composition)
# ============================================================================

@dataclass(frozen=True)
class ProcessingDependencies:
    """All dependencies for processing workflow."""
    calibration_model: CalibrationModel
    quality_threshold: float
    inference_algorithm: InferenceAlgorithm
    validation_metrics: ValidationMetrics


def create_processing_workflow(
    deps: ProcessingDependencies
) -> Callable[[RawObservations], Result[ValidatedModel, ProcessingError]]:
    """
    Create processing workflow with dependencies injected.

    Args:
        deps: All required dependencies

    Returns:
        Function: RawObservations → Result[ValidatedModel, ProcessingError]
    """
    return partial(
        process_observations,
        deps.calibration_model,
        deps.quality_threshold,
        deps.inference_algorithm,
        deps.validation_metrics
    )


# ============================================================================
# Application: Command and event handling
# ============================================================================

@dataclass(frozen=True)
class ProcessDataCommand:
    """Command to process observations."""
    raw_data: RawObservations
    timestamp: datetime
    user_id: str
    request_id: str


@dataclass(frozen=True)
class DataProcessed:
    """Event: data processing completed."""
    model: ValidatedModel
    processing_time: float
    timestamp: datetime


@dataclass(frozen=True)
class ProcessingFailedEvent:
    """Event: processing failed."""
    error: ProcessingError
    timestamp: datetime


ProcessingEvent = DataProcessed | ProcessingFailedEvent


async def handle_process_data_command(
    deps: ProcessingDependencies,
    command: ProcessDataCommand
) -> list[ProcessingEvent]:
    """
    Handle process data command.

    Args:
        deps: Processing dependencies
        command: Command to execute

    Returns:
        List of events emitted
    """
    import time
    start = time.time()

    # Execute workflow
    workflow = create_processing_workflow(deps)
    result = workflow(command.raw_data)

    # Convert result to events
    match result:
        case Ok(validated_model):
            return [DataProcessed(
                model=validated_model,
                processing_time=time.time() - start,
                timestamp=datetime.now()
            )]

        case Error(error):
            return [ProcessingFailedEvent(
                error=error,
                timestamp=datetime.now()
            )]


# ============================================================================
# Usage example
# ============================================================================

async def main():
    """Example usage of complete pipeline."""

    # Setup dependencies
    deps = ProcessingDependencies(
        calibration_model=create_default_calibration_model,
        quality_threshold=0.8,
        inference_algorithm=create_default_inference_algorithm,
        validation_metrics={"convergence": lambda p: 0.95}
    )

    # Create command
    command = ProcessDataCommand(
        raw_data=RawObservations(
            type="raw",
            values=[1.0, 2.0, 3.0, 4.0, 5.0],
            metadata={"source": "sensor_A", "experiment": "exp_001"}
        ),
        timestamp=datetime.now(),
        user_id="user_123",
        request_id="req_456"
    )

    # Handle command
    events = await handle_process_data_command(deps, command)

    # Process events
    for event in events:
        match event:
            case DataProcessed(model=model, processing_time=pt):
                print(f"Success! Processed in {pt:.3f}s")
                print(f"Parameters: {model.parameters}")
                print(f"Diagnostics: {model.diagnostics}")

            case ProcessingFailedEvent(error=error):
                print(f"Failed: {error}")


if __name__ == "__main__":
    import math  # for isfinite
    asyncio.run(main())
```

**Key takeaways**:

1. **Types enforce invariants**: QualityScore, Uncertainty validated at construction
2. **State machines explicit**: RawObservations → CalibratedData → InferredResults → ValidatedModel
3. **Dependencies explicit**: ProcessingDependencies passed to workflow
4. **Errors typed**: DomainError vs InfrastructureError
5. **Pure core**: Domain logic in pure functions, I/O at edges
6. **Composable**: Workflows built from smaller functions with bind/map

**See also**:
- domain-modeling.md for pattern details
- architectural-patterns.md for application structure
- railway-oriented-programming.md for Result composition

## Development practices

- Add type annotations to all public functions and classes
- Use `basedpyright` for static type checking and beartype for runtime type checking
- Create tests using `pytest` in a src/package/tests/ directory
- Use `ruff` for linting and formatting Python code
- Use src-based layout for python projects
- Add docstrings (Google style) to public functions and classes
- Use `uv run` to execute Python scripts, not `python` or `python3`
