# Architectural patterns

## Purpose

This document describes how to structure applications using functional domain modeling principles.

Topics covered:
- Onion/hexagonal architecture for domain isolation
- Workflow pipeline architecture
- Dependency injection via function parameters
- Commands and events as workflow boundaries
- Effect composition and signature

For domain modeling patterns, see domain-modeling.md.
For theoretical foundations, see theoretical-foundations.md.

## Onion/hexagonal architecture

### Core principle

Structure applications in concentric layers with domain logic at the center and infrastructure at the edges.

```
┌─────────────────────────────────────┐
│  Infrastructure (I/O, external)     │
│  ┌───────────────────────────────┐  │
│  │  Application (workflows)      │  │
│  │  ┌─────────────────────────┐  │  │
│  │  │  Domain (types, logic)  │  │  │
│  │  │                         │  │  │
│  │  └─────────────────────────┘  │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**Layer responsibilities**:

**Domain layer** (innermost):
- Domain types and models
- Domain logic and invariants
- State machines
- Pure functions only, no I/O
- No dependencies on outer layers

**Application layer** (middle):
- Workflows and use cases
- Orchestration of domain logic
- May have effects (Result, Async)
- Depends on domain layer
- Infrastructure passed as dependencies

**Infrastructure layer** (outermost):
- I/O operations (file, network, database)
- External service clients
- Serialization/deserialization
- Framework adapters
- Depends on application and domain
- Implements interfaces defined by inner layers

### Dependency direction

Dependencies point inward only:
```
Infrastructure → Application → Domain
     (I/O)      (workflows)   (pure logic)
```

Never:
```
Domain → Infrastructure  ⊘
Domain → Application     ⊘
```

This ensures:
- Domain logic testable without I/O
- Infrastructure replaceable without changing domain
- Compilation order: domain → application → infrastructure

### Instantiation 1 - Scientific data processing

```
Domain layer:
- Measurement types (Temperature, Pressure, QualityScore)
- Calibration models (CalibrationParams, CalibratedData)
- Validation rules (quality thresholds, range checks)
- State transitions (RawObservations → CalibratedData → ProcessedResults)

Application layer:
- process_observations workflow
- calibrate_measurements workflow
- validate_results workflow
- Coordinates domain logic with I/O dependencies

Infrastructure layer:
- File readers (CSV, HDF5, NetCDF)
- Database clients (save/load results)
- Cloud storage (S3, GCS)
- Plotting/visualization
- CLI argument parsing
```

### Instantiation 2 - Computational model training

```
Domain layer:
- Model architecture types
- Training state machines (Untrained → Training → Converged → Validated)
- Hyperparameter types with constraints
- Convergence criteria

Application layer:
- train_model workflow
- validate_model workflow
- deploy_model workflow
- Orchestrates training steps

Infrastructure layer:
- GPU/TPU allocation
- Checkpoint storage
- Metrics logging (Wandb, TensorBoard)
- Model serving infrastructure
- Data loaders
```

### Instantiation 3 - Order processing

```
Domain layer:
- Order types (UnvalidatedOrder → ValidatedOrder → PricedOrder)
- Product codes, quantities
- Pricing rules
- Validation logic

Application layer:
- place_order workflow
- validate_order workflow
- price_order workflow
- Coordinates validation, pricing, acknowledgment

Infrastructure layer:
- Database access
- Email sending
- Payment gateway
- Address validation service
- Product catalog
```

## Workflow pipeline architecture

### Pattern

Model domain processes as pipelines of transformations where each step:
- Takes domain input (data or command)
- Performs transformation
- Returns domain output (result or events)
- Declares dependencies explicitly
- Documents effects in type signature

```
Input → [Step1] → [Step2] → [Step3] → Output
         ↓dep      ↓dep      ↓dep
       Service1  Service2  Service3
```

### Workflow anatomy

```python
def workflow(
    dependency1: Service1,    # External dependencies first
    dependency2: Service2,
    config: Config,           # Configuration
    input_data: InputType     # Input data last
) -> Result[OutputType, Error]:  # Explicit error handling
    """
    Workflow description.

    Dependencies:
    - dependency1: Purpose of this dependency
    - dependency2: Purpose of this dependency

    Returns:
    - Ok(OutputType): On success
    - Error(...): On failure with reason
    """
    # Implementation
```

**Key aspects**:

1. **Dependencies first**: Enables partial application to create specialized versions
2. **Input last**: Allows piping: input |> workflow(dep1, dep2, config)
3. **Explicit effects**: Result type documents possible failures
4. **Pure core**: Domain logic separate from I/O dependencies

### Composition example

```python
# Individual steps with dependencies
def calibrate(
    calibration_model: CalibrationModel,
    quality_threshold: float,
    raw: RawObservations
) -> Result[CalibratedData, CalibrationError]:
    ...

def infer(
    inference_algorithm: InferenceAlgorithm,
    calibrated: CalibratedData
) -> Result[InferredResults, InferenceError]:
    ...

def validate(
    validation_metrics: ValidationMetrics,
    inferred: InferredResults
) -> Result[ValidatedResults, ValidationError]:
    ...

# Composed pipeline
def process_observations(
    calibration_model: CalibrationModel,
    quality_threshold: float,
    inference_algorithm: InferenceAlgorithm,
    validation_metrics: ValidationMetrics,
    raw: RawObservations
) -> Result[ValidatedResults, ProcessingError]:
    """Complete processing pipeline."""
    return (
        calibrate(calibration_model, quality_threshold, raw)
        .map_error(ProcessingError.from_calibration)
        .bind(lambda cal: infer(inference_algorithm, cal))
        .map_error(ProcessingError.from_inference)
        .bind(lambda inf: validate(validation_metrics, inf))
        .map_error(ProcessingError.from_validation)
    )
```

**See also**: railway-oriented-programming.md for Result composition details

## Dependency injection via function parameters

### Pattern

Pass dependencies as function parameters rather than using dependency injection frameworks or global state.

**Benefits**:
1. **Explicit**: Function signature documents all dependencies
2. **Testable**: Easy to pass mocks/stubs
3. **Composable**: Partial application creates specialized functions
4. **Type-safe**: Compiler verifies correct dependency types

### Partial application for specialization

```python
from functools import partial

# Full signature with all dependencies
def process_data(
    calibration_model: CalibrationModel,      # dependency 1
    quality_threshold: QualityThreshold,      # dependency 2
    inference_algo: InferenceAlgorithm,       # dependency 3
    data: RawObservations                     # input
) -> Result[ProcessedData, ProcessingError]:
    """Process observations with given dependencies."""
    ...

# Create specialized version with default dependencies
process_with_defaults = partial(
    process_data,
    default_calibration_model,
    strict_quality_threshold,
    standard_inference_algo
)

# Now just: RawObservations → Result[ProcessedData, Error]
result = process_with_defaults(observations)

# Alternative specialization for testing
process_for_testing = partial(
    process_data,
    mock_calibration_model,
    permissive_threshold,
    fast_test_algo
)
```

### Dependency interfaces

Define dependencies as simple function types, not heavyweight interfaces:

```python
# Instead of interface with many methods:
class IProductCatalog(Protocol):  ⊘
    def get_product(self, code: ProductCode) -> Product: ...
    def list_products(self) -> List[Product]: ...
    def update_stock(self, code: ProductCode, qty: int) -> None: ...
    # ... many methods

# Use specific function types:
GetProductPrice = Callable[[ProductCode], Price]  ●
CheckProductExists = Callable[[ProductCode], bool]

def price_order(
    get_price: GetProductPrice,      # Only what we need
    check_exists: CheckProductExists,
    order: ValidatedOrder
) -> Result[PricedOrder, PricingError]:
    ...
```

**Advantages**:
- Function type documents exactly what's needed
- No mock framework needed (just pass lambdas)
- Can compose functions to create dependencies
- Smaller, focused interfaces

### Example: Reader monad pattern

For workflows with many shared dependencies, use Reader pattern:

```python
@dataclass(frozen=True)
class Dependencies:
    """Shared dependencies for workflows."""
    calibration_model: CalibrationModel
    quality_threshold: float
    inference_algo: InferenceAlgorithm
    database: Database

def process_observations(
    deps: Dependencies,
    raw: RawObservations
) -> Result[ValidatedResults, Error]:
    """Workflow using shared dependencies."""
    return (
        calibrate(deps.calibration_model, deps.quality_threshold, raw)
        .bind(lambda cal: infer(deps.inference_algo, cal))
        .bind(lambda inf: save_results(deps.database, inf))
    )

# Specialize with partial application
process = partial(process_observations, production_dependencies)

# Or create Reader
from expression import Reader

def process_observations_reader(
    raw: RawObservations
) -> Reader[Dependencies, Result[ValidatedResults, Error]]:
    return Reader(lambda deps: process_observations(deps, raw))
```

**See also**: theoretical-foundations.md#monad-transformers

## Commands and events as workflow boundaries

### Commands as inputs

Commands represent intent to perform an action:

```python
@dataclass(frozen=True)
class ProcessObservationsCommand:
    """Command to process raw observations."""
    observations: RawObservations
    timestamp: datetime
    user_id: UserId
    request_id: RequestId  # For idempotency, logging

@dataclass(frozen=True)
class TrainModelCommand:
    """Command to train a model."""
    training_data: TrainingDataset
    architecture: ModelArchitecture
    hyperparameters: HyperParameters
    timestamp: datetime
    user_id: UserId
```

**Characteristics**:
- Immutable (frozen dataclass)
- Contains all data needed for workflow
- Includes metadata (timestamp, user, request ID)
- Named in imperative (ProcessObservations, TrainModel)

### Events as outputs

Events represent facts about what happened:

```python
@dataclass(frozen=True)
class ObservationsProcessed:
    """Event: observations were successfully processed."""
    results: ValidatedResults
    processing_time: timedelta
    timestamp: datetime

@dataclass(frozen=True)
class ProcessingFailed:
    """Event: processing failed."""
    error: ProcessingError
    timestamp: datetime

# Union of possible events
ProcessingEvent = ObservationsProcessed | ProcessingFailed

@dataclass(frozen=True)
class ModelTrained:
    """Event: model training completed."""
    model_id: ModelId
    final_metrics: Metrics
    checkpoint_path: Path
    timestamp: datetime
```

**Characteristics**:
- Immutable (frozen dataclass)
- Named in past tense (ObservationsProcessed, ModelTrained)
- Contain result data
- Multiple events may be emitted from one workflow

### Workflow signature with commands/events

```python
def process_observations_workflow(
    deps: Dependencies,
    command: ProcessObservationsCommand
) -> AsyncResult[list[ProcessingEvent], WorkflowError]:
    """
    Process observations workflow.

    Input: ProcessObservationsCommand
    Output: List of events (ObservationsProcessed, etc.)
    Effects: Async I/O, may fail
    """
    ...

# At application boundary (HTTP API, message queue):
async def handle_command(command_json: dict) -> Response:
    # Deserialize command
    command = ProcessObservationsCommand.from_dict(command_json)

    # Execute workflow
    result = await process_observations_workflow(deps, command)

    # Handle result
    match result:
        case Ok(events):
            # Publish events, return success
            for event in events:
                await event_bus.publish(event)
            return Response(status=200, body={"events": events})

        case Error(error):
            # Log error, return failure
            logger.error(f"Workflow failed: {error}")
            return Response(status=500, body={"error": str(error)})
```

### Benefits

1. **Explicit contracts**: Commands document inputs, events document outputs
2. **Asynchronous workflows**: Commands can be queued, events can trigger other workflows
3. **Event sourcing**: Events as system of record
4. **Testing**: Easy to create command instances for testing
5. **Audit trail**: Commands + events provide complete history

**See also**:
- `domain-modeling.md#workflows-as-type-safe-pipelines`
- `event-sourcing.md` for full event sourcing patterns where events become the authoritative source of truth

## Effect composition and signatures

### Explicit effects in type signatures

Document all effects in function signatures:

```python
# No effects (pure function)
def calculate_quality(
    measurement: Measurement,
    baseline: Baseline
) -> QualityScore:
    ...

# May fail
def validate_measurement(
    measurement: Measurement
) -> Result[ValidatedMeasurement, ValidationError]:
    ...

# Async I/O
async def fetch_calibration_data(
    experiment_id: ExperimentId
) -> CalibrationData:
    ...

# Async + may fail
async def save_results(
    database: Database,
    results: Results
) -> AsyncResult[SaveConfirmation, DatabaseError]:
    ...

# Multiple effects combined
async def process_with_retry(
    max_retries: int,
    operation: Callable[[T], AsyncResult[U, E]],
    input: T
) -> AsyncResult[U, E]:
    ...
```

### Common effect combinations

```python
# Result + Async
AsyncResult[T, E] = Async[Result[T, E]]

# Option + Async
AsyncOption[T] = Async[Option[T]]

# Result + Option (rare, usually use Result with error for "not found")
ResultOption[T, E] = Result[Option[T], E]
```

### Effect composition guidelines

1. **Keep stacks shallow**: Maximum 2-3 combined effects
2. **Use type aliases**: `AsyncResult` instead of `Async[Result[T, E]]`
3. **Document effect semantics**: What does each effect mean?
4. **Prefer specialized types**: Custom `AsyncResult` over generic transformer
5. **Avoid effect soup**: Don't mix too many effects

**Example of effect overload (avoid)**:

```python
# Too many effects - hard to reason about
ReaderStateAsyncResultOption[Config, State, T, E] = ...  ⊘
```

**Better approach**:

```python
# Limit to essential effects
WorkflowResult[T] = AsyncResult[T, WorkflowError]  ●

# Pass config/state as parameters
def workflow(
    config: Config,
    initial_state: State,
    input: Input
) -> WorkflowResult[Output]:
    ...
```

**See also**:
- railway-oriented-programming.md for Result composition
- theoretical-foundations.md#effect-systems-as-indexed-monads

## Cross-language integration

### Principles for multi-language systems

When integrating code across languages (Python ↔ Rust ↔ TypeScript):

1. **Preserve effect signatures**: Effects explicit at language boundaries
2. **Use standard serialization**: JSON, Protocol Buffers, MessagePack
3. **Share type definitions**: Generate types from schemas (JSON Schema, Protobuf)
4. **Validate at boundaries**: Don't trust data crossing language boundaries
5. **Document effect transformations**: How effects map between languages

### Example: Python calling Rust

```python
# Python wrapper for Rust function
def calibrate_rust(
    params: CalibrationParams,
    data: ndarray
) -> Result[CalibratedData, CalibrationError]:
    """
    Call Rust calibration function.

    Effect transformation:
    - Rust: Result<CalibratedData, CalibrationError>
    - Python: Result[CalibratedData, CalibrationError]

    Serialization:
    - params: JSON
    - data: NumPy → zero-copy buffer
    - result: JSON
    """
    try:
        # Serialize inputs
        params_json = params.to_json()
        data_buffer = data.tobytes()

        # Call Rust via FFI/subprocess
        result_json = _rust_calibrate(params_json, data_buffer)

        # Deserialize output
        if result_json["ok"]:
            return Ok(CalibratedData.from_json(result_json["value"]))
        else:
            return Error(CalibrationError.from_json(result_json["error"]))

    except Exception as e:
        # Infrastructure error (FFI failure, serialization error)
        return Error(CalibrationError(f"FFI failed: {e}"))
```

### Shared type definitions

Use schema to generate types in multiple languages:

```json
// calibration.schema.json
{
  "CalibrationParams": {
    "type": "object",
    "properties": {
      "baseline": {"type": "number"},
      "threshold": {"type": "number"}
    },
    "required": ["baseline", "threshold"]
  },
  "CalibrationError": {
    "type": "object",
    "oneOf": [
      {"type": "object", "properties": {"InvalidParams": {"type": "string"}}},
      {"type": "object", "properties": {"InsufficientData": {"type": "string"}}}
    ]
  }
}
```

Generate code:
- Python: dataclasses with Pydantic validators
- TypeScript: type definitions
- Rust: structs with serde

## Strategic architecture

Architectural decisions should align with the strategic importance of different domains rather than applying uniform approaches across the entire system.
The Core/Supporting/Generic domain classification described in *strategic-domain-analysis.md* directly influences architectural choices about integration patterns, deployment topology, and team boundaries.

### Domain classification shapes architecture

Core domains warrant the most sophisticated architectural treatment because they represent competitive advantage.
These contexts receive dedicated infrastructure, independent deployment pipelines, and careful isolation from other system components.
The hexagonal architecture patterns described earlier in this document apply most rigorously to core domains, with explicit ports and adapters ensuring that domain logic remains insulated from infrastructure concerns.

Supporting sub-domains receive solid but less elaborate architectural treatment.
These contexts often share infrastructure with other supporting contexts, deploy together in service groups, and use standardized integration patterns.
The workflow pipeline patterns remain appropriate, but the level of isolation and custom infrastructure investment is reduced compared to core domains.

Generic sub-domains receive minimal custom architecture, favoring integration with third-party services or shared platform capabilities.
These contexts are often thin adapter layers that translate between internal domain models and external service interfaces.
The dependency injection patterns enable swapping providers without modifying domain logic, but the domain logic itself is minimal.

### Context boundaries as architectural units

Bounded contexts, detailed in *bounded-context-design.md*, serve as the fundamental architectural unit in domain-driven systems.
Each context represents a deployment unit, an ownership boundary, and an integration interface.

The context relationship patterns (Partnership, Customer-Supplier, Anti-Corruption Layer) directly influence architectural decisions about synchronous versus asynchronous communication, data replication versus service calls, and tight versus loose coupling.
Anti-Corruption Layers manifest as adapter modules that translate between external types and internal domain types, implementing the functor mappings that preserve semantic relationships across context boundaries.

When multiple contexts are owned by the same team, they may share deployment infrastructure while maintaining logical separation.
When contexts are owned by different teams, deployment independence becomes more valuable, trading some efficiency for reduced coordination overhead.

### Team topology alignment

Architectural patterns should support the communication patterns implied by team structure.
Conway's Law ensures that architecture and organization will eventually align, so deliberate design should anticipate this alignment rather than fighting it.

Stream-aligned teams owning core domain contexts need architectural patterns that maximize autonomy and minimize dependencies on other teams.
Platform teams providing generic capabilities need architectural patterns that emphasize stability, backward compatibility, and clear versioning.
Enabling teams helping multiple teams adopt new patterns need architectural patterns that are portable and technology-agnostic.

The Team Topologies interaction modes (Collaboration, X-as-a-Service, Facilitating) map to context relationship patterns.
Collaboration implies Partnership or Shared Kernel relationships with tight coupling.
X-as-a-Service implies Open Host Service with stable, versioned interfaces.
Facilitating implies enabling teams help stream-aligned teams design their own context architectures.

### See also

*strategic-domain-analysis.md* for detailed Core/Supporting/Generic classification frameworks and investment prioritization.

*bounded-context-design.md* for context relationship patterns and the Bounded Context Canvas.

*discovery-process.md* for how strategic and organizational analysis fits into the broader discovery workflow.

## Theoretical ideal

In the ideal case, all systems—regardless of language—would integrate as a coherent monad transformer stack in the category of functional effects.

**Ideal properties**:

- Emphasize type-safety and functional programming patterns as feasible within each programming language or framework's ecosystem
- Use relevant libraries to achieve functional programming and type-safety where languages don't natively support it (e.g., basedpyright, beartype, and dbrattli/Expression in Python, Effect-TS in TypeScript, ZIO in Scala)
- Balance practical implementation constraints against the theoretical ideal of composable, lawful abstractions
- Design cross-language integrations to preserve functional composition, monadic structure, and explicit effect handling at API/FFI boundaries
- Encode all effects explicitly in type signatures at language boundaries to avoid hidden side effects or runtime surprises
- Ensure `bind`/`flatMap` operations satisfy monad laws across language boundaries when composing multi-language systems
- Implement lift operations to allow values to traverse effect transformer stacks between language layers (`liftIO`, `liftState`, etc.)
- Structure multi-language systems as monad transformer stacks where each language implements a specific effect transformer over the layers below it (e.g., Rust base `IO`/`Result`, TypeScript middle `StateT s (EitherT e IO)`, Python top `ReaderT config (StateT s (EitherT e IO))`)
- Use `Result`/`Either`/`Option` types for error handling that composes vertically through all layers rather than runtime exceptions
- Thread state explicitly through function parameters or state monads rather than hiding it in global mutable variables
- Isolate IO and unsafe effects to specific layers or boundaries rather than scattering them throughout the codebase
- Compose async/concurrency via effect systems or monad transformers rather than ad-hoc callbacks or unstructured promises
- Maintain the ideal that multi-language system integration should behave as a coherent monad transformer stack in the category of functional effects, preserving referential transparency end-to-end

**Practical path to ideal**:

Start with:
1. Onion architecture (domain/application/infrastructure layers)
2. Explicit effect signatures
3. Simple effect types (Result, Async)
4. Dependency injection via parameters

Progress toward:
5. Effect systems (Effect-TS, ZIO) where available
6. Monad transformers for 2-3 effects
7. Indexed monads for critical safety properties
8. Full monad transformer stack for complete effect tracking

**See also**: theoretical-foundations.md#indexed-monad-transformer-stacks-in-practice
