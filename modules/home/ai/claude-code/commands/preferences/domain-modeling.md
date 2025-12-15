# Functional domain modeling

## Purpose

This document describes how to model problem domains using functional programming techniques that make domain concepts explicit and invalid states impossible by construction.

"Domain" here means any subject matter area requiring precise modeling: scientific data processing, computational models, infrastructure configuration, mathematical structures, or traditional application logic.

## Core principle

Model problem domains using types that:

1. **Speak the domain vocabulary** - use terminology from the subject matter, not generic programmer terms
2. **Capture domain rules** - encode invariants and constraints in the type system
3. **Represent domain processes** - model workflows as composable, type-safe pipelines
4. **Make domain concepts explicit** - entities, aggregates, state machines visible in code structure

## Relationship to other documents

- **Implementation techniques**: See algebraic-data-types.md for sum/product types and railway-oriented-programming.md for error handling
- **Application structure**: See architectural-patterns.md for how to organize domain logic in a larger system
- **Theoretical foundations**: See theoretical-foundations.md for categorical and type-theoretic underpinnings
- **Language-specific examples**: See python-development.md, typescript-nodejs-development.md, rust-development/00-index.md for concrete implementations

## Universal patterns

### Pattern 1: Types as domain vocabulary

Replace primitive types with domain-specific types that make implicit assumptions explicit and prevent mixing incompatible values.

**Abstract definition**:

Instead of using generic types (string, int, float), create wrapper types that encode semantic meaning. Two values of the same primitive type but different semantic domains should not be interchangeable.

**Instantiation 1 - Measurement systems**:

```
Bad:  temperature: float, pressure: float
Good: Temperature(float), Pressure(float)

Why: Prevents accidentally using temperature where pressure expected, documents units implicitly
```

**Instantiation 2 - Identifiers**:

```
Bad:  user_id: str, experiment_id: str, model_id: str
Good: UserId(str), ExperimentId(str), ModelId(str)

Why: Prevents mixing different kinds of identifiers, makes relationships explicit
```

**Instantiation 3 - Validated data**:

```
Bad:  email: str  # hoping it's valid
Good: EmailAddress(str)  # guaranteed valid by construction

Why: Validation happens once at construction, thereafter guaranteed
```

**Structural abstraction**:

```haskell
-- Generic newtype pattern
newtype DomainType = DomainType PrimitiveType

-- Constructor is private, use smart constructor
create :: PrimitiveType -> Result DomainType Error
```

**Implementation guidance**:

- Python: Single-field Pydantic models with validators
- TypeScript: Branded types with smart constructors
- Rust: Newtype pattern with private fields
- SQL: DOMAIN types (PostgreSQL) or CHECK constraints

**See also**: algebraic-data-types.md#newtype-pattern

### Pattern 2: Smart constructors for invariants

Private constructors combined with validation functions that return Result types enforce constraints at creation time and guarantee validity thereafter.

**Abstract definition**:

Make type constructors private. Provide public creation functions that validate inputs and return Result<T, Error>. Once a value exists, it's guaranteed to be valid because immutability prevents modification.

**Instantiation 1 - Scientific measurements with bounds**:

```
Quality score must be in [0, 1]
Uncertainty must be positive
Measurement count must be > 0

Smart constructor validates these, returns Error if violated
Thereafter: all QualityScore values are in [0,1] by construction
```

**Instantiation 2 - Configuration with dependencies**:

```
Network port must be in range [1, 65535]
File path must exist and be readable
Memory allocation must not exceed system limits

Smart constructor checks constraints, returns Error if invalid
Thereafter: all Config values are valid, no need to re-check
```

**Instantiation 3 - Domain constraints**:

```
Order quantity between 1 and 1000
Product code matches regex pattern
Email address contains @ and domain

Smart constructor enforces rules, returns Error if broken
Thereafter: all values satisfy constraints automatically
```

**Structural abstraction**:

```haskell
-- Type with private constructor
data DomainType = private DomainType InnerValue

-- Public smart constructor
create :: RawInput -> Result DomainType ValidationError
create input =
  if isValid input
    then Ok (DomainType (transform input))
    else Error (ValidationError "reason")

-- Accessor for inner value
value :: DomainType -> InnerValue
```

**Implementation guidance**:

- Python: Pydantic validators, private __init__ with public @classmethod
- TypeScript: Private constructor, static factory method returning Either
- Rust: Private struct fields, public associated function returning Result
- F#: Private constructor, module with create function

**See also**: algebraic-data-types.md#constrained-values

### Pattern 3: State machines for entity lifecycles

Model entities that transition through discrete states using discriminated unions where each state has its own type with state-specific data and capabilities.

**Abstract definition**:

An entity with a lifecycle is a state machine where:
- Each state is a distinct type with state-appropriate data
- Transitions are functions: State1 -> Result<State2, Error>
- Invalid transitions are impossible by construction
- The entity is a discriminated union of all possible states

**Instantiation 1 - Data processing pipeline**:

```
States:
- RawObservations: unvalidated measurements, may contain artifacts
- CalibratedData: quality-controlled measurements with uncertainty quantification
- InferredResults: fitted model with estimated parameters
- ValidatedModel: model that passed convergence diagnostics

Transitions:
- calibrate: RawObservations -> Result<CalibratedData, CalibrationError>
- infer: CalibratedData -> Result<InferredResults, InferenceError>
- validate: InferredResults -> Result<ValidatedModel, ValidationError>

Invariants:
- Cannot infer from uncalibrated data (type system prevents it)
- Cannot use model that failed validation (type system prevents it)
```

**Instantiation 2 - Computational model lifecycle**:

```
States:
- SpecifiedModel: architecture defined, parameters uninitialized
- TrainingModel: active optimization with checkpoints
- ConvergedModel: optimization complete, awaiting validation
- DeployedModel: validated and serving predictions

Transitions:
- initialize: SpecifiedModel -> TrainingModel
- train: TrainingModel -> Result<ConvergedModel, TrainingError>
- validate: ConvergedModel -> Result<DeployedModel, ValidationError>

Invariants:
- Cannot deploy unvalidated model
- Cannot resume training from deployed model (one-way transition)
```

**Instantiation 3 - Email verification workflow**:

```
States:
- UnverifiedEmail: email address not yet confirmed
- VerifiedEmail: email confirmed by user clicking link

Transitions:
- sendVerification: UnverifiedEmail -> EmailSent
- confirmClick: EmailSent -> VerifiedEmail

Invariants:
- Password reset only accepts VerifiedEmail (type signature enforces)
- Welcome email only sent to UnverifiedEmail (no spam)
```

**Structural abstraction**:

```haskell
-- State machine as discriminated union
data EntityState
  = State1 State1Data
  | State2 State2Data
  | State3 State3Data

-- Transitions as functions between states
transition1 :: State1Data -> Result State2Data Error
transition2 :: State2Data -> Result State3Data Error

-- Processing based on current state
handleEntity :: EntityState -> Action
handleEntity (State1 data) = processState1 data
handleEntity (State2 data) = processState2 data
handleEntity (State3 data) = processState3 data
```

**Implementation guidance**:

- Python: Discriminated unions (Python 3.10+) with Literal type field
- TypeScript: Discriminated unions with string literal type field
- Rust: Enum with associated data per variant
- F#: Discriminated unions with pattern matching

**Why state machines**:

1. Each state can have different allowable operations
2. All states are explicitly documented in code
3. Forces thinking about edge cases (what if transition fails? what if already in target state?)
4. Self-documenting: reading type definition shows complete lifecycle

**See also**: algebraic-data-types.md#sum-types

### Pattern 4: Workflows as type-safe pipelines

Model domain processes as functions with explicit inputs, outputs, dependencies, and effects in their type signatures.

**Abstract definition**:

A workflow is a function that:
- Takes domain data as input (commands/observations)
- Returns domain data as output (events/results)
- Declares dependencies as function parameters (appears before data input)
- Documents effects in return type (Result for errors, Async for I/O)
- Composes with other workflows via bind/map

**Instantiation 1 - Data processing workflow**:

```
Workflow: Process observations through calibration and inference

Input: RawObservations
Output: Result<InferredDynamics, ProcessingError>
Dependencies:
  - calibrationModel: RawValue -> (Value, Uncertainty)
  - qualityThreshold: Float
  - inferenceAlgorithm: CalibrationData -> Parameters
Effects: May fail (Result), performs I/O (Async)

Type signature:
processObservations ::
  CalibrationModel ->      -- dependency
  QualityThreshold ->      -- dependency
  InferenceAlgorithm ->    -- dependency
  RawObservations ->       -- input
  AsyncResult<InferredDynamics, ProcessingError>  -- output with effects

Composition:
  rawData
  |> calibrate(calibrationModel, qualityThreshold)
  |> Result.bind(infer(inferenceAlgorithm))
  |> Result.bind(validate)
```

**Instantiation 2 - Model training workflow**:

```
Workflow: Train and validate predictive model

Input: TrainingData
Output: Result<DeployedModel, TrainingError>
Dependencies:
  - architecture: ModelSpec
  - hyperparameters: HyperParams
  - validationMetric: Model -> Score
Effects: May fail, performs I/O, long-running

Type signature:
trainModel ::
  ModelSpec ->
  HyperParams ->
  ValidationMetric ->
  TrainingData ->
  AsyncResult<DeployedModel, TrainingError>
```

**Instantiation 3 - Order processing workflow**:

```
Workflow: Validate, price, and fulfill order

Input: UnvalidatedOrder
Output: Result<OrderEvents, OrderError>
Dependencies:
  - checkProductExists: ProductCode -> Bool
  - checkAddressValid: Address -> AsyncResult<ValidAddress, AddressError>
  - getPrice: ProductCode -> Price
Effects: May fail, calls remote services

Type signature:
processOrder ::
  CheckProductExists ->
  CheckAddressValid ->
  GetPrice ->
  UnvalidatedOrder ->
  AsyncResult<OrderEvents, OrderError>
```

**Structural abstraction**:

```haskell
-- General workflow pattern
type Workflow input output error =
  Dependency1 ->
  Dependency2 ->
  input ->
  AsyncResult<output, error>

-- Composition via bind
workflow :: Input -> AsyncResult<Output, Error>
workflow input =
  input
  |> step1(dep1, dep2)
  |> AsyncResult.bind(step2(dep3))
  |> AsyncResult.bind(step3)
```

**Why dependencies as parameters**:

1. **Explicit documentation**: Signature shows what external services needed
2. **Testability**: Easy to inject mocks/stubs for testing
3. **Partial application**: Can create specialized versions with dependencies pre-filled
4. **Dependency injection**: Functional equivalent without framework magic

**Why effects in signature**:

1. **Honest documentation**: Signature shows exactly what can happen
2. **Composability**: Effect types compose (AsyncResult, AsyncOption, etc.)
3. **Type safety**: Compiler prevents ignoring errors or forgetting await
4. **Refactoring safety**: Changing effects forces update of all callers

**See also**:
- railway-oriented-programming.md for Result composition
- architectural-patterns.md#workflow-pipeline-architecture

### Pattern 5: Aggregates as consistency boundaries

Group related entities that must change together atomically, with a root entity managing the group's invariants.

**Abstract definition**:

An aggregate is:
- A cluster of related entities and value objects
- A root entity that controls access to the cluster
- A consistency boundary: invariants enforced within aggregate
- A transaction boundary: persisted/loaded as atomic unit
- Connected to other aggregates only by root entity IDs, not direct references

**Instantiation 1 - Experimental dataset with observations**:

```
Aggregate: Dataset
Root: Dataset entity with DatasetId
Members: Collection of Observation entities

Invariants enforced by root:
- Dataset must have at least one observation
- All observations must use same measurement protocol
- Observation timestamps must be monotonically increasing
- Removing observation recalculates summary statistics

Why aggregate:
- Changing observation affects dataset statistics (must update together)
- Observations have no meaning outside their dataset
- Loading/saving must be atomic to prevent inconsistent state

References to other aggregates:
- Dataset.protocol_id -> Protocol (different aggregate, reference by ID only)
- Don't embed full Protocol object, fetch separately when needed
```

**Instantiation 2 - Computational model with training state**:

```
Aggregate: Model
Root: Model entity with ModelId
Members: Collection of Checkpoint entities, TrainingMetrics entity

Invariants enforced by root:
- Latest checkpoint must match current model parameters
- Training metrics must correspond to checkpoint history
- Cannot delete checkpoint if it's the only one
- Restoring checkpoint updates metrics to that point

Why aggregate:
- Checkpoints meaningless without parent model
- Metrics must stay synchronized with checkpoint history
- Loading must be atomic (model + checkpoints + metrics together)

References to other aggregates:
- Model.dataset_id -> Dataset (reference by ID)
- Model.architecture_id -> Architecture (reference by ID)
```

**Instantiation 3 - Order with order lines**:

```
Aggregate: Order
Root: Order entity with OrderId
Members: Collection of OrderLine entities

Invariants enforced by root:
- Order must have at least one line
- Total amount equals sum of line amounts
- All lines reference valid products
- Changing line price updates order total

Why aggregate:
- Lines meaningless without parent order
- Total must stay synchronized with lines
- Saving must be atomic (order + all lines in same transaction)

References to other aggregates:
- Order.customer_id -> Customer (reference by ID, not embedded)
- OrderLine.product_id -> Product (reference by ID)
```

**Structural abstraction**:

```haskell
-- Aggregate with root and members
data Aggregate = Aggregate
  { rootId :: RootId
  , rootData :: RootData
  , members :: List MemberEntity
  , computedData :: DerivedData  -- maintained by aggregate
  }

-- Updates go through root, enforcing invariants
updateMember :: Aggregate -> MemberId -> MemberUpdate -> Result Aggregate Error
updateMember agg memberId update =
  let updatedMember = applyUpdate memberId update
      updatedMembers = replaceInList agg.members updatedMember
      newComputedData = recomputeInvariants agg.rootData updatedMembers
  in if checkInvariants newComputedData
     then Ok (Aggregate agg.rootId agg.rootData updatedMembers newComputedData)
     else Error "Invariant violation"
```

**When to use aggregates**:

1. **Consistency required**: Changes to one entity affect others (recalculate totals)
2. **Lifecycle coupling**: Members created/deleted with parent
3. **Invariants span entities**: Rules involve multiple entities (min 1 order line)
4. **Transaction boundary**: Must save/load together for data integrity

**When to use separate aggregates**:

1. **Independent lifecycles**: Entities created/deleted independently
2. **Different consistency needs**: Don't need to update together
3. **Scalability**: Locking entire aggregate for one member update is too coarse
4. **Bounded context crossing**: Entities in different domains/teams

**Aggregate references**:

Use IDs, not embedded objects:
```
Good: Order.customer_id: CustomerId
Bad:  Order.customer: Customer  # Creates coupling, forces loading together
```

Load related aggregates separately when needed:
```
order = loadOrder(orderId)
customer = loadCustomer(order.customer_id)
```

**See also**: theoretical-foundations.md#aggregates-and-optics

### Pattern 6: Domain errors vs infrastructure errors

Classify errors by their role in the domain model to determine how to handle them.

**Abstract definition**:

Errors fall into three categories:

1. **Domain errors**: Expected outcomes of domain processes, part of domain model
2. **Infrastructure errors**: Technical failures in supporting systems
3. **Panics**: Unrecoverable system errors or programmer mistakes

Each category requires different handling strategy.

**Domain errors**:

Characteristics:
- Subject matter experts can describe them
- Have established procedures for handling
- Part of normal workflow, not exceptional
- Should be modeled as sum types in domain

Examples across domains:
- Scientific: "Calibration failed: quality below threshold"
- Computational: "Model training diverged: loss increased"
- Infrastructure: "Configuration validation failed: circular dependency"

Handling:
- Model explicitly as Result types
- Include in type signatures
- Create choice types for error variants
- Return descriptive error information for handling

**Infrastructure errors**:

Characteristics:
- Technical/architectural concerns
- Not part of domain logic
- May be transient (retry can help)
- Outside domain expert's vocabulary

Examples across domains:
- Network timeouts calling remote services
- Database connection failures
- Authentication/authorization failures
- Disk full, out of memory

Handling strategy:
- May model as Result if need explicit handling
- May use exceptions if want to fail fast
- Consider retry logic, circuit breakers
- Log with context for debugging

**Panics**:

Characteristics:
- System in unknown state
- Usually programmer error
- Cannot meaningfully continue
- Should never happen in correct code

Examples:
- Division by zero
- Array index out of bounds
- Null/None when value guaranteed
- Stack overflow, out of memory

Handling:
- Let fail with exception
- Catch at top level only
- Log for debugging
- Fix the bug, don't handle in domain

**Instantiation 1 - Data processing**:

```
Domain errors:
- ValidationError: measurements outside expected range
- CalibrationError: insufficient quality control samples
- ConvergenceError: optimization failed to converge

Infrastructure errors:
- DatabaseError: failed to save results
- NetworkError: timeout fetching reference data
- StorageError: disk full, cannot write output

Panics:
- Should never happen: empty array where guaranteed non-empty
- Programming error: forgot to initialize critical state
```

**Instantiation 2 - Model lifecycle**:

```
Domain errors:
- TrainingError: training diverged, loss NaN
- ValidationError: metrics below acceptance threshold
- DeploymentError: model incompatible with serving infrastructure

Infrastructure errors:
- CheckpointError: failed to save checkpoint to storage
- ServiceError: metrics service unavailable
- ResourceError: insufficient GPU memory

Panics:
- Invalid state: model claimed converged but has NaN parameters
- Logic error: attempted operation on wrong model state
```

**Structural abstraction**:

```haskell
-- Domain error as explicit sum type
data DomainError
  = ValidationFailed ValidationError
  | ProcessingFailed ProcessingError
  | ConstraintViolated ConstraintError

-- Workflow returns domain errors explicitly
workflow :: Input -> Result<Output, DomainError>

-- Infrastructure error may be explicit or exception
handleInfrastructure :: IO a -> Result<a, InfrastructureError>
-- or
handleInfrastructure :: IO a -> IO a  -- throws exception on failure

-- Panic is always exception, caught at top level only
main :: IO ()
main = catch runWorkflow $ \exc -> do
  logError exc
  exitFailure
```

**Decision tree**:

Ask: "If I explained this to a subject matter expert, would they recognize it?"
- Yes → Domain error, model explicitly
- No → Ask: "Can we meaningfully continue after this error?"
  - Yes → Infrastructure error, consider explicit modeling
  - No → Panic, use exceptions

**Error composition**:

When combining workflows with different error types:
```
type WorkflowError
  = Validation ValidationError
  | Processing ProcessingError
  | Infrastructure InfrastructureError

step1 :: Input -> Result<A, ValidationError>
step2 :: A -> Result<Output, ProcessingError>

combined :: Input -> Result<Output, WorkflowError>
combined input =
  input
  |> step1
  |> Result.mapError Validation
  |> Result.bind (\a -> step2 a |> Result.mapError Processing)
```

**See also**: railway-oriented-programming.md#working-with-domain-errors

## Anti-patterns to avoid

### Primitive obsession

**Problem**: Using raw primitives throughout code instead of domain types

```
Bad:
  def process_data(user_id: str, temp: float, pressure: float) -> float:
    # Which string is which? What units? What happens if swapped?
    ...

Good:
  def process_data(
    user: UserId,
    temp: Temperature,
    pressure: Pressure
  ) -> Result[ProcessedValue, ProcessingError]:
    # Types document meaning, prevent mistakes
    ...
```

### Boolean blindness

**Problem**: Using bool for domain states instead of explicit types

```
Bad:
  class Email:
    is_verified: bool  # What does True mean? Can spam if wrong.

Good:
  EmailState = UnverifiedEmail | VerifiedEmail
  # Type system prevents sending password reset to unverified
```

### Stringly-typed code

**Problem**: Using strings for things that should be types

```
Bad:
  state: str  # Could be "pending", "active", "done", or typo "activ"

Good:
  State = Pending | Active | Done  # Typos caught at compile time
```

### Implicit state machines

**Problem**: State tracked by flags instead of explicit state types

```
Bad:
  class Order:
    is_validated: bool
    is_priced: bool
    price: Optional[Price]  # When is this None? When required?

Good:
  OrderState = Unvalidated | Validated | Priced(price: Price)
  # State explicit, illegal combinations impossible
```

### God classes/aggregates

**Problem**: Aggregates that are too large or unrelated entities grouped

```
Bad:
  class System:
    users: List[User]
    experiments: List[Experiment]
    models: List[Model]
    # All updated together? No clear invariants.

Good:
  UserAggregate, ExperimentAggregate, ModelAggregate
  # Each with clear boundaries and invariants
```

### Missing smart constructors

**Problem**: Types without validation, checks scattered throughout code

```
Bad:
  email = Email(raw_input)  # Hope it's valid
  # Checks scattered everywhere email used: if '@' in email.value ...

Good:
  email_result = Email.create(raw_input)  # Validated once
  # If have Email object, it's guaranteed valid
```

## Testing domain models

### Property-based testing for invariants

Use property-based testing to verify invariants hold across many examples:

```python
from hypothesis import given, strategies as st

# Test that smart constructor maintains invariant
@given(st.floats(min_value=0, max_value=1))
def test_quality_score_in_range(value: float):
    score = QualityScore.create(value)
    assert score.is_ok()
    assert 0 <= score.unwrap().value <= 1

# Test that aggregate maintains invariant
@given(st.lists(st.data(), min_size=1))
def test_dataset_never_empty(observations: list):
    dataset = Dataset.create(observations)
    assert len(dataset.observations) >= 1
```

### State machine testing

Test all transitions and verify impossible transitions prevented:

```python
def test_cannot_deploy_unvalidated_model():
    model = SpecifiedModel.create(architecture)
    # This should not compile / should return Error
    result = deploy(model)
    assert result.is_error()

def test_valid_transition_sequence():
    model = SpecifiedModel.create(architecture)
    training = initialize(model)
    converged = train(training, data)
    validated = validate(converged)
    deployed = deploy(validated)
    assert deployed.is_ok()
```

### Example-based testing for domain errors

Test that domain errors are returned in expected scenarios:

```python
def test_calibration_fails_low_quality():
    raw = RawObservations(low_quality_data)
    result = calibrate(strict_threshold, raw)
    assert result.is_error()
    assert isinstance(result.error, CalibrationError)
    assert "quality" in result.error.message.lower()
```

## Language-specific implementations

For concrete code examples in each language:

- **Python**: See python-development.md#functional-domain-modeling
  - Pydantic for smart constructors and validation
  - Discriminated unions with Literal types
  - Expression library for Result types

- **TypeScript**: See typescript-nodejs-development.md#functional-domain-modeling
  - Branded types for newtypes
  - Discriminated unions with string literal types
  - Effect-TS for effect composition

- **Rust**: See rust-development/01-functional-domain-modeling.md
  - Newtype pattern with tuple structs
  - Enums for sum types
  - Native Result and Option types

## Further reading

- **Theoretical foundations**: See theoretical-foundations.md for category-theoretic underpinnings
- **Error handling composition**: See railway-oriented-programming.md
- **Type system techniques**: See algebraic-data-types.md
- **Application architecture**: See architectural-patterns.md
- **Original source**: "Domain Modeling Made Functional" by Scott Wlaschin
