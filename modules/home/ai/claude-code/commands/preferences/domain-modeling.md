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

## Pre-implementation discovery

The patterns in this document assume that domain discovery has occurred before implementation begins.
Attempting to apply these patterns without prior discovery often results in domains modeled around technical convenience rather than business structure, missing essential domain concepts that domain experts would surface, and premature commitment to boundaries that require expensive refactoring.

The discovery process described in *discovery-process.md* precedes the implementation patterns here.
Discovery produces informal artifacts like event storm boards, domain stories, and context maps that this document's patterns formalize into type systems.

### Discovery outputs as implementation inputs

EventStorming sessions produce orange sticky notes representing domain events that become sum type variants in this document's Pattern 3 (state machines) and in event-sourcing.md.
Blue command sticky notes become function signatures in Pattern 4 (workflows as pipelines).
Yellow aggregate sticky notes become the consistency boundaries in Pattern 5 (aggregates).

Domain Storytelling produces narratives that reveal workflow sequences directly applicable to Pattern 4.
The actors, work objects, and activities in domain stories map to types, entities, and functions in the domain model.

Example Mapping produces concrete examples of business rules that inform smart constructor validation in Pattern 2 and property-based test cases for Pattern invariants.

### When to skip discovery

Certain scenarios warrant abbreviated or skipped discovery.
Bug fixes in well-understood domains do not require fresh EventStorming sessions.
Small features extending existing bounded contexts can rely on prior discovery documentation.
Maintenance work within stable domains operates on established understanding.

Even in these cases, verify that prior discovery artifacts remain current.
Domains evolve, and stale discovery documentation misleads more than no documentation.

### Linking workflows to EventStorming

Pattern 4 (workflows as type-safe pipelines) directly implements the command and event flows surfaced during EventStorming.
Each blue command sticky note becomes a workflow function taking validated input and producing events or errors.
The sequence of commands and events on the event storm board suggests pipeline composition order.

For example, an EventStorming session might surface the sequence "Validate Order → Calculate Price → Apply Discounts → Confirm Order" as commands triggering events.
This sequence becomes a composed pipeline:

```
validateOrder :: UnvalidatedOrder -> Validation ValidatedOrder
calculatePrice :: ValidatedOrder -> PricedOrder
applyDiscounts :: PricedOrder -> DiscountedOrder
confirmOrder :: DiscountedOrder -> Validation (OrderConfirmed, List Event)

processOrder = validateOrder
  >=> (pure . calculatePrice)
  >=> (pure . applyDiscounts)
  >=> confirmOrder
```

The workflow directly traces to EventStorming artifacts, maintaining traceability from discovery through implementation.

### See also

*discovery-process.md* for the complete discovery workflow including EventStorming facilitation, context mapping, and strategic domain analysis.

*collaborative-modeling.md* for detailed guidance on EventStorming, Domain Storytelling, and Example Mapping techniques that produce the events, commands, aggregates, and policies this document's patterns implement as algebraic types, smart constructors, and workflows.

*strategic-domain-analysis.md* for Core/Supporting/Generic classification that determines the type sophistication applied to each domain.

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

**Algebra of API design**:

A module is a collection of functions operating on types while honoring invariants.
These invariants are laws—verifiable properties that should hold for all valid uses of the API.
This algebraic structure makes APIs predictable, composable, and testable through property-based testing.

Smart constructors establish the initial algebra: they are the "generators" that produce valid values.
The invariants they enforce are the laws of the algebra.
All other module functions must preserve these laws—they are homomorphisms over the algebra structure.

```rust
// Example: NonEmptyList algebra
// Law: length must always be >= 1

// Smart constructor establishes the law
impl<T> NonEmptyList<T> {
    pub fn new(head: T, tail: Vec<T>) -> Self {
        NonEmptyList { head, tail }
        // Invariant: guaranteed non-empty by construction
    }

    // All operations preserve the law
    pub fn push(&mut self, item: T) {
        self.tail.push(item);
        // Still non-empty: law preserved
    }

    pub fn map<U>(self, f: impl Fn(T) -> U) -> NonEmptyList<U> {
        NonEmptyList {
            head: f(self.head),
            tail: self.tail.into_iter().map(f).collect(),
        }
        // Law preserved: non-empty maps to non-empty
    }
}

// Property-based test verifying the law
#[cfg(test)]
mod tests {
    use quickcheck::quickcheck;

    quickcheck! {
        fn non_empty_list_never_empty(head: i32, tail: Vec<i32>) -> bool {
            let list = NonEmptyList::new(head, tail);
            list.len() >= 1  // Law holds
        }

        fn map_preserves_non_empty(head: i32, tail: Vec<i32>) -> bool {
            let list = NonEmptyList::new(head, tail);
            let mapped = list.map(|x| x * 2);
            mapped.len() >= 1  // Law preserved under map
        }
    }
}
```

These laws form the algebra of the module.
When all functions preserve the laws, users can reason algebraically about code: if input satisfies laws, output will too.
This is why "making illegal states unrepresentable" works—the type system enforces the algebraic structure.

**See also**: `algebraic-laws.md` for formal treatment of algebraic laws and their categorical interpretation.

**See also**: algebraic-data-types.md#newtype-pattern for constrained value types

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

**See also**: algebraic-data-types.md#sum-types-discriminated-unions

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

**Functional aggregate updates with lenses**:

For complex aggregates with deeply nested structures, lenses provide compositional getters and setters that preserve immutability and compose elegantly.
Rather than writing verbose nested record updates, lenses enable focused modifications that clearly express intent.

```rust
// Without lenses: verbose nested update
fn update_city(dataset: Dataset, new_city: String) -> Dataset {
    Dataset {
        protocol: Protocol {
            facility: Facility {
                address: Address {
                    city: new_city,
                    ..dataset.protocol.facility.address
                },
                ..dataset.protocol.facility
            },
            ..dataset.protocol
        },
        ..dataset
    }
}

// With lenses: compositional update
let city_lens = dataset_lens.compose(protocol_lens)
                             .compose(facility_lens)
                             .compose(address_lens)
                             .compose(city_field_lens);

let updated = city_lens.set(dataset, new_city);
```

Lens laws ensure these operations are well-behaved: getting and then setting with the same value is identity (GetPut), setting and then getting returns the set value (PutGet), and setting twice uses the second value (PutPut).

```haskell
-- Lens laws
-- GetPut: set (view lens s) s = s
-- PutGet: view lens (set a s) = a
-- PutPut: set a' (set a s) = set a' s
```

**See also**: `theoretical-foundations.md#lenses-for-nested-data-access` for categorical interpretation and formal lens laws.

**See also**:
- `theoretical-foundations.md#aggregates-and-optics`
- `event-sourcing.md` for event-sourced aggregates where state is derived from event log

### Pattern 6: Repositories as generic modules

Group persistence operations as parameterized modules that abstract over storage mechanisms while maintaining type safety and composability.

**Abstract definition**:

A repository is a generic interface parameterized by aggregate type and identifier type.
The repository signature defines abstract operations (query, store, delete) without committing to implementation details like database technology or serialization format.
Different algebras implement this signature for different storage backends (in-memory, PostgreSQL, object storage), and interpreters execute operations in specific contexts (production database, test mocks).

**Generic repository signature**:

```rust
trait Repository<A, Id> {
    type Error;

    fn query(&self, id: &Id) -> Result<Option<A>, Self::Error>;
    fn store(&self, aggregate: &A) -> Result<A, Self::Error>;
    fn delete(&self, id: &Id) -> Result<(), Self::Error>;
    fn query_by(&self, predicate: impl Fn(&A) -> bool) -> Result<Vec<A>, Self::Error>;
}

// Concrete implementation for PostgreSQL
struct PostgresRepository<A> {
    pool: PgPool,
    _phantom: PhantomData<A>,
}

impl<A> Repository<A, Uuid> for PostgresRepository<A>
where
    A: Serialize + DeserializeOwned + HasId<Uuid>,
{
    type Error = DatabaseError;

    fn query(&self, id: &Uuid) -> Result<Option<A>, DatabaseError> {
        // Implementation using sqlx
    }

    fn store(&self, aggregate: &A) -> Result<A, DatabaseError> {
        // Implementation using sqlx
    }

    fn delete(&self, id: &Uuid) -> Result<(), DatabaseError> {
        // Implementation using sqlx
    }

    fn query_by(&self, predicate: impl Fn(&A) -> bool) -> Result<Vec<A>, DatabaseError> {
        // Load all and filter (or translate predicate to SQL)
    }
}

// In-memory implementation for testing
struct InMemoryRepository<A, Id> {
    storage: Arc<RwLock<HashMap<Id, A>>>,
}

impl<A, Id> Repository<A, Id> for InMemoryRepository<A, Id>
where
    A: Clone,
    Id: Eq + Hash + Clone,
{
    type Error = InMemoryError;

    fn query(&self, id: &Id) -> Result<Option<A>, InMemoryError> {
        Ok(self.storage.read().unwrap().get(id).cloned())
    }

    fn store(&self, aggregate: &A) -> Result<A, InMemoryError> {
        let id = aggregate.id().clone();
        self.storage.write().unwrap().insert(id, aggregate.clone());
        Ok(aggregate.clone())
    }

    // ... other operations
}
```

**Dependency injection via Reader pattern**:

Rather than passing repositories as constructor parameters (which couples components to concrete implementations), use the Reader pattern to thread dependencies through computations.
This defers injection to the call site, enabling testing with alternative implementations and making dependency requirements explicit in type signatures.

```rust
// Reader monad threads environment through computation
struct Reader<R, A> {
    run: Box<dyn Fn(&R) -> A>,
}

impl<R, A> Reader<R, A> {
    fn new(f: impl Fn(&R) -> A + 'static) -> Self {
        Reader { run: Box::new(f) }
    }

    fn run_reader(&self, env: &R) -> A {
        (self.run)(env)
    }

    fn map<B>(self, f: impl Fn(A) -> B + 'static) -> Reader<R, B> {
        Reader::new(move |env| f(self.run_reader(env)))
    }

    fn bind<B>(self, f: impl Fn(A) -> Reader<R, B> + 'static) -> Reader<R, B> {
        Reader::new(move |env| f(self.run_reader(env)).run_reader(env))
    }
}

// Usage: workflow that needs repository
fn load_and_process_dataset(
    dataset_id: DatasetId
) -> Reader<impl Repository<Dataset, DatasetId>, Result<ProcessedData, Error>> {
    Reader::new(move |repo| {
        match repo.query(&dataset_id)? {
            Some(dataset) => process_dataset(dataset),
            None => Err(Error::NotFound(dataset_id)),
        }
    })
}

// At call site: inject dependencies
fn main() {
    let repo = PostgresRepository::new(db_pool);
    let workflow = load_and_process_dataset(dataset_id);
    let result = workflow.run_reader(&repo);
}

// In tests: inject mock
#[test]
fn test_load_and_process() {
    let repo = InMemoryRepository::new();
    repo.store(&test_dataset());
    let workflow = load_and_process_dataset(test_dataset_id);
    let result = workflow.run_reader(&repo);
    assert!(result.is_ok());
}
```

**See also**: `railway-oriented-programming.md` for Reader pattern details and effect composition, `theoretical-foundations.md` for Reader monad categorical interpretation.

### Pattern 7: Domain errors vs infrastructure errors

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

## Module algebra for domain services

Domain services are best understood as algebras consisting of three parts: signatures that define abstract operations, algebras that implement those operations, and interpreters that execute them in specific contexts.
This organization pattern, central to Debasish Ghosh's approach in "Functional and Reactive Domain Modeling", separates interface from implementation and execution, enabling testability, composability, and multiple interpretations of the same domain logic.

### Signatures

A signature is a trait or interface defining abstract operations parameterized on types.
The signature publishes the contract without committing to implementation.
Type parameters remain abstract, allowing different implementations to choose concrete representations suited to their context.

```rust
// Account service signature
trait AccountService {
    type Account;
    type Amount;
    type Error;

    fn open(&self, no: &str, name: &str, opening_date: Date)
        -> Result<Self::Account, Self::Error>;

    fn close(&self, account: &Self::Account, close_date: Date)
        -> Result<Self::Account, Self::Error>;

    fn debit(&self, account: &Self::Account, amount: Self::Amount)
        -> Result<Self::Account, Self::Error>;

    fn credit(&self, account: &Self::Account, amount: Self::Amount)
        -> Result<Self::Account, Self::Error>;

    fn balance(&self, account: &Self::Account) -> Self::Amount;
}
```

The signature abstracts over Account, Amount, and Error types.
Different implementations can provide different concrete types: Amount might be Decimal for production, or i64 for tests; Account might be a rich domain object or a minimal test stub.

```haskell
-- Haskell equivalent using type families
class AccountService m where
    type Account m
    type Amount m
    type Error m

    open :: String -> String -> Date -> m (Either (Error m) (Account m))
    close :: Account m -> Date -> m (Either (Error m) (Account m))
    debit :: Account m -> Amount m -> m (Either (Error m) (Account m))
    credit :: Account m -> Amount m -> m (Either (Error m) (Account m))
    balance :: Account m -> m (Amount m)
```

### Algebras (implementations)

An algebra is a concrete implementation of the signature.
Multiple algebras can implement the same signature for different contexts: production database, in-memory testing, event sourcing, external API integration.

```rust
// Production algebra: PostgreSQL implementation
struct PostgresAccountService {
    pool: PgPool,
}

impl AccountService for PostgresAccountService {
    type Account = Account;  // Rich domain type
    type Amount = Decimal;
    type Error = DatabaseError;

    fn open(&self, no: &str, name: &str, opening_date: Date)
        -> Result<Account, DatabaseError>
    {
        // Validate using smart constructor
        let account = Account::open(no, name, opening_date)?;

        // Persist to database
        sqlx::query!(
            "INSERT INTO accounts (number, name, opened_on, status) VALUES ($1, $2, $3, 'open')",
            account.number(),
            account.name(),
            account.opened_on()
        )
        .execute(&self.pool)
        .await?;

        Ok(account)
    }

    fn debit(&self, account: &Account, amount: Decimal) -> Result<Account, DatabaseError> {
        let updated = account.debit(amount)?;  // Domain logic

        // Persist change
        sqlx::query!(
            "UPDATE accounts SET balance = $1 WHERE number = $2",
            updated.balance(),
            updated.number()
        )
        .execute(&self.pool)
        .await?;

        Ok(updated)
    }

    // ... other operations
}

// Test algebra: in-memory implementation
struct InMemoryAccountService {
    accounts: Arc<RwLock<HashMap<String, Account>>>,
}

impl AccountService for InMemoryAccountService {
    type Account = Account;  // Same domain type
    type Amount = Decimal;
    type Error = TestError;

    fn open(&self, no: &str, name: &str, opening_date: Date)
        -> Result<Account, TestError>
    {
        let account = Account::open(no, name, opening_date)?;
        self.accounts.write().unwrap().insert(no.to_string(), account.clone());
        Ok(account)
    }

    fn debit(&self, account: &Account, amount: Decimal) -> Result<Account, TestError> {
        let updated = account.debit(amount)?;
        self.accounts.write().unwrap().insert(account.number().to_string(), updated.clone());
        Ok(updated)
    }

    // ... other operations
}
```

Different algebras for the same signature enable swapping implementations without changing client code.
Tests use `InMemoryAccountService`, production uses `PostgresAccountService`, but both satisfy the `AccountService` contract.

### Interpreters

An interpreter transforms one algebra into another or executes the algebra in a specific context.
This separation enables testing with mock interpreters while using database interpreters in production.

```rust
// Interpreter: execute account operations in IO context
async fn run_account_workflow<S: AccountService>(
    service: &S,
    account_no: &str,
    name: &str,
    transactions: Vec<Transaction>,
) -> Result<S::Account, S::Error> {
    // Open account
    let mut account = service.open(account_no, name, Date::today())?;

    // Apply transactions
    for transaction in transactions {
        account = match transaction {
            Transaction::Debit(amount) => service.debit(&account, amount)?,
            Transaction::Credit(amount) => service.credit(&account, amount)?,
        };
    }

    Ok(account)
}

// Use with different algebras
#[tokio::main]
async fn main() {
    let service = PostgresAccountService::new(pool);
    let account = run_account_workflow(&service, "ACC001", "Alice", transactions).await;
}

#[test]
fn test_account_workflow() {
    let service = InMemoryAccountService::new();
    let account = block_on(run_account_workflow(&service, "ACC001", "Alice", test_transactions));
    assert_eq!(service.balance(&account.unwrap()), Decimal::from(1000));
}
```

The interpreter `run_account_workflow` is polymorphic over any `AccountService` implementation.
It doesn't care whether operations hit a database or update in-memory state—it operates purely on the algebra interface.

### Composition

Modules compose via trait inheritance (Rust), mixins (Scala), or type class composition.
Larger services are built by combining smaller service algebras.

```rust
// Compose account service with reporting service
trait AccountReportingService: AccountService {
    fn generate_statement(&self, account: &Self::Account, period: DateRange)
        -> Result<Statement, Self::Error>;

    fn tax_report(&self, accounts: Vec<Self::Account>, year: Year)
        -> Result<TaxReport, Self::Error>;
}

// Implementation composes both algebras
impl AccountReportingService for PostgresAccountService {
    fn generate_statement(&self, account: &Account, period: DateRange)
        -> Result<Statement, DatabaseError>
    {
        // Uses self.balance() from AccountService
        let current_balance = self.balance(account);

        // Fetch transactions from database
        let transactions = self.fetch_transactions(account, period)?;

        Ok(Statement::new(account.clone(), transactions, current_balance))
    }

    // ... other operations
}
```

Composition preserves the algebra structure: composed services remain abstract over type parameters, enabling the same test/production separation at higher levels of abstraction.

```haskell
-- Haskell: compose services via constraint intersection
class (AccountService m, ReportingService m) => AccountReportingService m where
    generateStatement :: Account m -> DateRange -> m (Either (Error m) Statement)
    taxReport :: [Account m] -> Year -> m (Either (Error m) TaxReport)
```

This compositional structure scales to complex domain models.
Payment services compose with account services; portfolio management composes with both; risk analysis composes with all three.
Each layer remains testable in isolation by substituting appropriate algebras.

**See also**: `theoretical-foundations.md` for the categorical interpretation of module algebras as F-algebras, and `architectural-patterns.md` for organizing module algebras in application architecture.

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
