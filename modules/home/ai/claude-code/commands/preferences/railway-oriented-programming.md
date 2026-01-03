# Railway-oriented programming

## Overview

Railway-oriented programming (ROP) is a functional pattern for composing operations that can fail.
The mental model is a two-track railway: success track and failure track.
Once on the failure track, operations are skipped and errors propagate to the end.

This approach makes error handling explicit, composable, and type-safe.

## The Result type

The foundation of ROP is a discriminated union representing success or failure.

### Pattern: Result<T, E> in Python

```python
from typing import Generic, TypeVar, Union
from dataclasses import dataclass

T = TypeVar('T')
E = TypeVar('E')
U = TypeVar('U')

@dataclass
class Success(Generic[T]):
    value: T

@dataclass
class Failure(Generic[E]):
    error: E

Result = Union[Success[T], Failure[E]]

# Functions that can fail return Result
def parseInput(raw: dict) -> Result[Input, ParseError]:
    """Parse untrusted input - can fail"""
    try:
        return Success(Input(**raw))
    except Exception as e:
        return Failure(ParseError(str(e)))

def validate(input: Input) -> Result[ValidInput, ValidationError]:
    """Validate business rules - can fail"""
    errors = []
    if not input.email or '@' not in input.email:
        errors.append("email must contain @")
    if not input.name:
        errors.append("name is required")

    if errors:
        return Failure(ValidationError(errors))
    return Success(ValidInput(email=input.email, name=input.name))

# Pattern match on Result
match parseInput(data):
    case Success(input):
        print(f"Parsed: {input}")
    case Failure(error):
        print(f"Parse error: {error}")
```

### Pattern: Result in TypeScript

```typescript
// Result as discriminated union
type Result<T, E> =
  | { ok: true; value: T }
  | { ok: false; error: E };

// Constructor functions
function success<T, E>(value: T): Result<T, E> {
  return { ok: true, value };
}

function failure<T, E>(error: E): Result<T, E> {
  return { ok: false, error };
}

// Functions that can fail return Result
function parseInput(raw: unknown): Result<Input, ParseError> {
  try {
    const input = Input.parse(raw);  // Zod/similar
    return success(input);
  } catch (e) {
    return failure(new ParseError(e.message));
  }
}

function validate(input: Input): Result<ValidInput, ValidationError> {
  const errors: string[] = [];

  if (!input.email || !input.email.includes('@')) {
    errors.push('email must contain @');
  }
  if (!input.name) {
    errors.push('name is required');
  }

  if (errors.length > 0) {
    return failure(new ValidationError(errors));
  }

  return success({ email: input.email, name: input.name });
}

// Pattern match with type narrowing
const result = parseInput(data);
if (result.ok) {
  console.log(`Parsed: ${result.value}`);
} else {
  console.log(`Error: ${result.error}`);
}
```

### Pattern: Result in Go

```go
// Result as struct with generics
type Result[T any] struct {
    Value T
    Error error
}

func Success[T any](value T) Result[T] {
    return Result[T]{Value: value, Error: nil}
}

func Failure[T any](err error) Result[T] {
    var zero T
    return Result[T]{Value: zero, Error: err}
}

func (r Result[T]) IsOk() bool {
    return r.Error == nil
}

func (r Result[T]) IsErr() bool {
    return r.Error != nil
}

// Functions that can fail return Result
func ParseInput(raw map[string]any) Result[Input] {
    input, err := parseInputInternal(raw)
    if err != nil {
        return Failure[Input](err)
    }
    return Success(input)
}

func Validate(input Input) Result[ValidInput] {
    if input.Email == "" || !strings.Contains(input.Email, "@") {
        return Failure[ValidInput](errors.New("email must contain @"))
    }
    if input.Name == "" {
        return Failure[ValidInput](errors.New("name is required"))
    }
    return Success(ValidInput{Email: input.Email, Name: input.Name})
}

// Check result
result := ParseInput(data)
if result.IsOk() {
    fmt.Printf("Parsed: %v\n", result.Value)
} else {
    fmt.Printf("Error: %v\n", result.Error)
}
```

## The abstraction hierarchy

Result types participate in a hierarchy of abstractions, each more powerful than the last.
Understanding this hierarchy helps you choose the appropriate abstraction for each situation.

### Functor: transforming success values

The functor interface (`map`) transforms the success value without affecting the error track.
Use when you have a pure function to apply to a successful result.

```rust
result.map(|account| account.balance)
```

This is the simplest and most widely applicable abstraction.
Every Result is a functor, and functors compose freely.

### Applicative: combining independent results

The applicative interface (`apply`, `map2`, `mapN`) combines multiple independent results.
All validations run regardless of individual failures, collecting all errors.

Use when operations don't depend on each other's results.

```rust
// All three validations run; errors accumulate
validate_name(name)
    .and(validate_email(email))
    .and(validate_age(age))
    .map3(|n, e, a| User::new(n, e, a))
```

Applicative is more powerful than functor because it can combine multiple Results, but less powerful than monad because it cannot express sequential dependencies.

### Monad: sequencing dependent operations

The monad interface (`flatMap`, `and_then`, `>>=`) sequences operations where later steps depend on earlier results.
Execution short-circuits on first failure.

Use when each step needs the result of the previous step.

```rust
validate_account_no(no)
    .and_then(|no| lookup_account(no))
    .and_then(|account| validate_balance(account, amount))
    .and_then(|account| debit(account, amount))
```

Monad is the most powerful abstraction in this hierarchy, but also the most specialized.
Not all applicatives are monads.

### The least powerful abstraction principle

Prefer the simplest abstraction that solves your problem.
Functors compose more freely than applicatives.
Applicatives compose more freely than monads.
Using a more powerful abstraction than necessary restricts composability.

When in doubt, follow this decision tree:
1. Can you just transform the success value? Use functor (`map`)
2. Are the operations independent of each other? Use applicative (`apply`, `mapN`)
3. Does each step depend on the previous result? Use monad (`bind`, `and_then`)

### Selection guidance

| Situation | Abstraction | Interface | Why |
|-----------|-------------|-----------|-----|
| Transform success value | Functor | `map` | Simplest, most reusable, composes freely |
| Combine independent validations | Applicative | `apply`, `mapN` | Parallel execution, error accumulation |
| Chain dependent operations | Monad | `bind`, `and_then` | Sequential dependency, fail-fast |

See `~/.claude/commands/preferences/theoretical-foundations.md#functor-applicative-monad-hierarchy` for the mathematical laws each abstraction must satisfy.

## bind: Monadic composition

Chain operations that can fail - short-circuit on first error.

### Pattern: Sequential pipeline in Python

```python
from typing import Callable

def bind(result: Result[T, E], f: Callable[[T], Result[U, E]]) -> Result[U, E]:
    """
    Monadic bind: compose world-crossing functions.

    If result is Success, apply f to the value.
    If result is Failure, skip f and propagate error.
    """
    match result:
        case Success(value):
            return f(value)
        case Failure(error):
            return Failure(error)

# Infix operator for chaining
def bindAsync(
    result: Result[T, E],
    f: Callable[[T], Awaitable[Result[U, E]]]
) -> Awaitable[Result[U, E]]:
    """Bind for async operations"""
    async def inner():
        match result:
            case Success(value):
                return await f(value)
            case Failure(error):
                return Failure(error)
    return inner()

# Usage: Chain operations with short-circuit on error
def processOrder(raw: dict) -> Result[Order, Error]:
    """
    Process order through pipeline:
    1. Parse input (can fail)
    2. Validate (can fail)
    3. Save to DB (can fail)

    Stop at first error - don't waste work.
    """
    return (
        bind(parseInput(raw), lambda input:
        bind(validate(input), lambda valid:
        bind(saveToDb(valid), lambda order:
        Success(order))))
    )

# More readable with helper
class ResultMonad:
    def __init__(self, result: Result[T, E]):
        self._result = result

    def bind(self, f: Callable[[T], Result[U, E]]) -> 'ResultMonad[U, E]':
        return ResultMonad(bind(self._result, f))

    def unwrap(self) -> Result[T, E]:
        return self._result

# Fluent API
result = (
    ResultMonad(parseInput(raw))
    .bind(validate)
    .bind(saveToDb)
    .unwrap()
)
```

### Pattern: Async pipeline in Python

```python
async def processOrderAsync(raw: dict) -> Result[Order, Error]:
    """
    Async pipeline with Result:
    - Parse (sync)
    - Validate (sync)
    - Fetch from DB (async, can fail)
    - Update DB (async, can fail)
    """
    # Sync steps
    inputResult = parseInput(raw)
    validResult = bind(inputResult, validate)

    # Async steps
    match validResult:
        case Success(valid):
            userResult = await fetchUser(valid.userId)
            return await bindAsync(userResult, lambda user:
                   await updateUser(user, valid))
        case Failure(error):
            return Failure(error)

# Or with async helper
async def bindAsync(
    result: Result[T, E],
    f: Callable[[T], Awaitable[Result[U, E]]]
) -> Result[U, E]:
    match result:
        case Success(value):
            return await f(value)
        case Failure(error):
            return Failure(error)
```

### When to use bind (monadic style)

Use bind when:
- **Steps depend on previous results**: Next operation needs output of previous
- **Want to short-circuit**: Stop on first error, don't waste work
- **Database operations**: Skip writes if validation fails
- **External API calls**: Don't call next API if previous failed
- **Expensive operations**: Avoid unnecessary computation

Example scenarios:
- User registration: validate → check email not taken → create user → send email
- Order processing: validate → reserve inventory → charge card → create shipment
- Data pipeline: parse → validate → transform → load

## apply: Applicative composition

Combine independent validations and collect all errors.

### Pattern: Parallel validation in Python

```python
def apply(
    fResult: Result[Callable[[T], U], list[E]],
    xResult: Result[T, list[E]]
) -> Result[U, list[E]]:
    """
    Applicative apply: combine independent computations.

    If both Success: apply function to value.
    If either Failure: collect errors from both.
    """
    match (fResult, xResult):
        case (Success(f), Success(x)):
            return Success(f(x))
        case (Failure(e1), Success(_)):
            return Failure(e1)
        case (Success(_), Failure(e2)):
            return Failure(e2)
        case (Failure(e1), Failure(e2)):
            return Failure(e1 + e2)  # Combine error lists!

def map(f: Callable[[T], U], result: Result[T, E]) -> Result[U, E]:
    """Lift normal function to Result world"""
    match result:
        case Success(value):
            return Success(f(value))
        case Failure(error):
            return Failure(error)

# Usage: Validate all fields, collect all errors
def validateUser(raw: dict) -> Result[User, list[ValidationError]]:
    """
    Validate all fields independently.
    Returns all validation errors, not just first.
    Better UX than stopping at first error.
    """
    emailResult = validateEmail(raw.get('email'))
    nameResult = validateName(raw.get('name'))
    ageResult = validateAge(raw.get('age'))

    # Applicative style: combine all results
    # Using curried function to apply results one by one
    def makeUser(email: EmailAddress):
        def withName(name: str):
            def withAge(age: int):
                return User(email=email, name=name, age=age)
            return withAge
        return withName

    return apply(
        apply(
            map(makeUser, emailResult),
            nameResult),
        ageResult)

# Test with invalid data
result = validateUser({
    'email': 'invalid',      # Missing @
    'name': '',              # Empty
    'age': '-5'              # Negative
})

# Result is Failure with ALL three errors:
# ["email must contain @", "name is required", "age must be positive"]
```

### Pattern: Applicative in TypeScript

```typescript
function apply<T, U, E>(
  fResult: Result<(t: T) => U, E[]>,
  xResult: Result<T, E[]>
): Result<U, E[]> {
  if (fResult.ok && xResult.ok) {
    return success(fResult.value(xResult.value));
  }
  if (!fResult.ok && !xResult.ok) {
    return failure([...fResult.error, ...xResult.error]);
  }
  if (!fResult.ok) {
    return failure(fResult.error);
  }
  return failure(xResult.error);
}

function map<T, U, E>(
  f: (t: T) => U,
  result: Result<T, E>
): Result<U, E> {
  if (result.ok) {
    return success(f(result.value));
  }
  return failure(result.error);
}

// Validate all fields
function validateUser(raw: unknown): Result<User, ValidationError[]> {
  const emailResult = validateEmail(raw.email);
  const nameResult = validateName(raw.name);
  const ageResult = validateAge(raw.age);

  // Applicative composition
  const makeUser = (email: EmailAddress) =>
    (name: string) =>
    (age: number) =>
    ({ email, name, age });

  return apply(
    apply(
      map(makeUser, emailResult),
      nameResult),
    ageResult);
}
```

### Error accumulation with semigroups

For applicative validation to accumulate errors, the error type must form a semigroup (support associative combination).
NonEmptyList or NonEmptyVec are common choices because they guarantee at least one error when in the Failure case.

```rust
use nonempty::NonEmpty;

type ValidationResult<T> = Result<T, NonEmpty<ValidationError>>;

#[derive(Debug, Clone)]
enum ValidationError {
    InvalidName(String),
    InvalidEmail(String),
    InvalidAge(String),
}

fn validate_name(name: &str) -> ValidationResult<String> {
    if name.is_empty() {
        Err(NonEmpty::new(ValidationError::InvalidName(
            "name is required".into()
        )))
    } else {
        Ok(name.to_string())
    }
}

fn validate_email(email: &str) -> ValidationResult<String> {
    if !email.contains('@') {
        Err(NonEmpty::new(ValidationError::InvalidEmail(
            "email must contain @".into()
        )))
    } else {
        Ok(email.to_string())
    }
}

fn validate_age(age: i32) -> ValidationResult<i32> {
    if age < 0 {
        Err(NonEmpty::new(ValidationError::InvalidAge(
            "age must be positive".into()
        )))
    } else {
        Ok(age)
    }
}

fn validate_user(
    name: &str,
    email: &str,
    age: i32
) -> ValidationResult<User> {
    // All three validations run even if some fail
    // Errors are combined using semigroup append
    validate_name(name)
        .and(validate_email(email))
        .and(validate_age(age))
        .map(|(n, e, a)| User::new(n, e, a))
}

// Example: multiple validation failures
let result = validate_user("", "invalid", -5);
// Returns: Err(NonEmpty([InvalidName, InvalidEmail, InvalidAge]))
```

The semigroup requirement means errors can be combined associatively.
NonEmptyVec satisfies this: `(e1 + e2) + e3 == e1 + (e2 + e3)`.
This enables the applicative to collect errors from independent validations while maintaining type safety (at least one error when failed).

### Pattern: Applicative with NonEmptyList in Python

```python
from typing import Generic, TypeVar
from dataclasses import dataclass

T = TypeVar('T')
E = TypeVar('E')

@dataclass
class NonEmptyList(Generic[E]):
    """List guaranteed to have at least one element."""
    head: E
    tail: list[E]

    def append(self, other: 'NonEmptyList[E]') -> 'NonEmptyList[E]':
        """Semigroup operation: combine two non-empty lists."""
        return NonEmptyList(
            head=self.head,
            tail=self.tail + [other.head] + other.tail
        )

    def to_list(self) -> list[E]:
        return [self.head] + self.tail

ValidationResult = Result[T, NonEmptyList[E]]

def validate_user_fields(
    name: str,
    email: str,
    age: int
) -> ValidationResult[User]:
    """
    Validate all fields independently.
    Accumulates all errors using NonEmptyList semigroup.
    """
    name_result = validate_name(name)
    email_result = validate_email(email)
    age_result = validate_age(age)

    # Applicative combination with error accumulation
    return apply(
        apply(
            map(lambda n: lambda e: lambda a: User(n, e, a), name_result),
            email_result
        ),
        age_result
    )

# All three validations execute
result = validate_user_fields("", "bad-email", -1)
# Returns: Failure(NonEmptyList(
#   head=ValidationError("name required"),
#   tail=[
#       ValidationError("email must contain @"),
#       ValidationError("age must be positive")
#   ]
# ))
```

### When to use apply (applicative style)

Use apply when:
- **Validations are independent**: Each check doesn't need results of others
- **Want to collect all errors**: Better UX to show all problems at once
- **Can run in parallel**: No dependencies means potential parallelism
- **Form validation**: Show all field errors to user

Example scenarios:
- User input validation: email, name, age all validated independently
- Configuration validation: check all required fields before proceeding
- Multi-field business rules: credit score AND income AND debt ratio

The key difference from monadic bind: applicative runs all validations regardless of individual failures, while bind short-circuits on first error.

## Effect signatures

Make side effects explicit in function type signatures.

### Pattern: Async operations that can fail

```python
from typing import Awaitable

# Type alias for common pattern
AsyncResult = Awaitable[Result[T, E]]

# Database operations have explicit effect signature
async def fetchUser(userId: UserId) -> AsyncResult[User, DatabaseError]:
    """
    Effect signature says:
    - This is async (Awaitable)
    - Can fail (Result)
    - Failure type is DatabaseError
    """
    try:
        row = await db.fetchrow(
            "SELECT id, email, name FROM users WHERE id = $1",
            userId.value
        )
        if row is None:
            return Failure(DatabaseError("user not found"))
        return Success(User(
            id=UserId(value=row['id']),
            email=EmailAddress(value=row['email']),
            name=row['name']
        ))
    except Exception as e:
        return Failure(DatabaseError(str(e)))

async def updateUser(user: User) -> AsyncResult[User, DatabaseError]:
    """Effect: async write that can fail"""
    try:
        await db.execute(
            "UPDATE users SET email = $1, name = $2 WHERE id = $3",
            user.email.value,
            user.name,
            user.id.value
        )
        return Success(user)
    except Exception as e:
        return Failure(DatabaseError(str(e)))

# Compose async effects
async def updateUserEmail(
    userId: UserId,
    newEmail: EmailAddress
) -> AsyncResult[User, Error]:
    """
    Railway-oriented pipeline:
    1. Fetch user (async, can fail: not found, db error)
    2. Update email field (pure, cannot fail)
    3. Save user (async, can fail: db error)
    """
    userResult = await fetchUser(userId)

    match userResult:
        case Success(user):
            updatedUser = User(
                id=user.id,
                email=newEmail,
                name=user.name
            )
            return await updateUser(updatedUser)
        case Failure(error):
            return Failure(error)
```

### Pattern: Effect signatures in TypeScript

```typescript
// Type alias
type AsyncResult<T, E> = Promise<Result<T, E>>;

// Explicit effect signatures
async function fetchUser(
  userId: UserId
): AsyncResult<User, DatabaseError> {
  try {
    const row = await db.query(
      "SELECT id, email, name FROM users WHERE id = $1",
      [userId]
    );
    if (row.rows.length === 0) {
      return failure(new DatabaseError("not found"));
    }
    return success(parseUser(row.rows[0]));
  } catch (e) {
    return failure(new DatabaseError(e.message));
  }
}

async function updateUser(
  user: User
): AsyncResult<User, DatabaseError> {
  try {
    await db.query(
      "UPDATE users SET email = $1, name = $2 WHERE id = $3",
      [user.email, user.name, user.id]
    );
    return success(user);
  } catch (e) {
    return failure(new DatabaseError(e.message));
  }
}
```

## Combining Result with other effects

When Result must be combined with other effects (async, reader, state), monad transformers stack the effects.

### ResultT for async + error

Most commonly, Result needs to be combined with async operations.
The standard pattern is `Future<Result<T, E>>` or `Promise<Result<T, E>>`.

```rust
// Rust: AsyncResult pattern
type AsyncResult<T, E> = impl Future<Output = Result<T, E>>;

async fn fetch_and_validate(id: &str) -> Result<Account, Error> {
    let data = fetch(id).await?;  // Async effect + error propagation
    validate(data)?;              // Error effect
    Ok(Account::from(data))
}

// Compose async Results with and_then
async fn process_account(id: &str) -> Result<ProcessedAccount, Error> {
    let account = fetch_and_validate(id).await?;
    let verified = verify_account(account).await?;
    let processed = process(verified).await?;
    Ok(processed)
}
```

```typescript
// TypeScript: Promise<Result<T, E>> pattern
type AsyncResult<T, E> = Promise<Result<T, E>>;

async function fetchAndValidate(id: string): AsyncResult<Account, Error> {
    const dataResult = await fetch(id);  // Returns Result<Data, Error>
    if (!dataResult.ok) return dataResult;

    const validResult = validate(dataResult.value);
    if (!validResult.ok) return validResult;

    return success(Account.from(validResult.value));
}

// Compose with async/await
async function processAccount(id: string): AsyncResult<ProcessedAccount, Error> {
    const accountResult = await fetchAndValidate(id);
    if (!accountResult.ok) return accountResult;

    const verifiedResult = await verifyAccount(accountResult.value);
    if (!verifiedResult.ok) return verifiedResult;

    const processedResult = await process(verifiedResult.value);
    return processedResult;
}
```

```python
# Python: Awaitable[Result[T, E]] pattern
from typing import Awaitable

AsyncResult = Awaitable[Result[T, E]]

async def fetch_and_validate(id: str) -> Result[Account, Error]:
    """
    Async operation that can fail.
    Combines async effect (await) with error effect (Result).
    """
    data_result = await fetch(id)  # Returns Result[Data, Error]

    match data_result:
        case Success(data):
            valid_result = validate(data)
            match valid_result:
                case Success(valid):
                    return Success(Account.from_valid(valid))
                case Failure(error):
                    return Failure(error)
        case Failure(error):
            return Failure(error)

# Compose async Results
async def process_account(id: str) -> Result[ProcessedAccount, Error]:
    account_result = await fetch_and_validate(id)

    match account_result:
        case Success(account):
            verified_result = await verify_account(account)
            match verified_result:
                case Success(verified):
                    return await process(verified)
                case Failure(error):
                    return Failure(error)
        case Failure(error):
            return Failure(error)
```

### Effect ordering matters

The transformer stacking order determines behavior.
`Future<Result<T, E>>` gives a Future that resolves to a Result - this is the standard pattern.
`Result<Future<T>, E>` (less common) would give a Result containing a Future, which is rarely useful because you cannot meaningfully combine a successful Future with a failed computation.

For most domain code, prefer `Future<Result<T, E>>` / `async fn() -> Result<T, E>`.
This allows async operations to complete before error handling, matching the natural execution order.

### Combining multiple effects with monad transformers

When stacking more than two effects, libraries provide transformer types:

```haskell
-- Haskell: ReaderT + ExceptT + IO
type AppM a = ReaderT Config (ExceptT AppError IO) a

-- Unwrapped: Config -> IO (Either AppError a)
-- Three effects: Reader (config access), Except (errors), IO (effects)

runApp :: AppM a -> Config -> IO (Either AppError a)
runApp app config = runExceptT (runReaderT app config)
```

```rust
// Rust approximation with custom type
struct AppM<T> {
    run: Box<dyn Fn(Config) -> Pin<Box<dyn Future<Output = Result<T, AppError>>>>>
}

// Combines Reader effect (Config ->), async (Future), and error (Result)
impl<T> AppM<T> {
    fn run(self, config: Config) -> impl Future<Output = Result<T, AppError>> {
        (self.run)(config)
    }
}
```

Most languages without native transformer support use a simpler pattern:

```typescript
// TypeScript: Manually stack effects in function signatures
type AppM<T> = (config: Config) => Promise<Result<T, AppError>>;

// Three effects: Reader (Config ->), async (Promise), error (Result)
async function processOrder(config: Config): Promise<Result<Order, AppError>> {
    // Config available via closure (Reader effect)
    // await for async effect
    // Result for error effect
    const validResult = await validateOrder(config);
    if (!validResult.ok) return validResult;

    return success(validResult.value);
}
```

### Guidelines for effect composition

1. **Most common**: `async fn() -> Result<T, E>` / `Future<Result<T, E>>` for async + error
2. **Keep transformers shallow**: Two or three effects maximum before complexity becomes unwieldy
3. **Document effect order**: Make clear what each layer represents
4. **Use language idioms**: async/await with Result is more idiomatic than custom transformers in most languages
5. **Consider effect libraries**: fp-ts (TypeScript), cats-effect (Scala), polysemy (Haskell) when transformer stacks become complex

See `~/.claude/commands/preferences/theoretical-foundations.md#monad-transformers` for the mathematical foundation and `~/.claude/commands/preferences/theoretical-foundations.md#indexed-monad-transformer-stacks-in-practice` for practical considerations when stacking effects.

## The two-track model

Transform all functions to uniform two-track shape for composition.

### Transformation functions

```python
# map: Lift one-track function to two-track
def map(f: Callable[[T], U], result: Result[T, E]) -> Result[U, E]:
    """
    Lift normal function to Result world.
    One-track in, two-track out.
    """
    match result:
        case Success(value):
            return Success(f(value))
        case Failure(error):
            return Failure(error)

# tee: Convert dead-end function to pass-through
def tee(f: Callable[[T], None]) -> Callable[[T], T]:
    """
    Convert side-effect function to pass-through.
    Useful for logging, metrics, etc.
    """
    def wrapper(x: T) -> T:
        f(x)  # Execute side effect
        return x  # Pass through original value
    return wrapper

# tryCatch: Lift function that might throw
def tryCatch(
    f: Callable[[T], U],
    errorHandler: Callable[[Exception], E]
) -> Callable[[T], Result[U, E]]:
    """
    Convert exception-throwing function to Result-returning.
    Catches exceptions and converts to Failure.
    """
    def wrapper(x: T) -> Result[U, E]:
        try:
            return Success(f(x))
        except Exception as e:
            return Failure(errorHandler(e))
    return wrapper
```

### Uniform pipeline composition

```python
# Example: User update workflow with mixed function types

# One-track function (pure)
def canonicalizeEmail(email: str) -> str:
    return email.strip().lower()

# Dead-end function (side effect, no return)
def logUser(user: User) -> None:
    logger.info(f"Processing user {user.id}")

# Exception-throwing function
def encryptPassword(password: str) -> str:
    if len(password) < 8:
        raise ValueError("password too short")
    return bcrypt.hash(password)

# Build uniform two-track pipeline
def updateUserPipeline(raw: dict) -> Result[User, Error]:
    """
    All functions transformed to two-track for uniform composition:
    - parseInput: already two-track (returns Result)
    - validate: already two-track (returns Result)
    - canonicalizeEmail: lifted via map
    - logUser: converted via tee + map
    - encryptPassword: lifted via tryCatch
    - saveToDb: already two-track
    """
    return (
        bind(parseInput(raw), lambda input:
        bind(validate(input), lambda valid:
        bind(
            # Transform one-track canonicalize to two-track
            map(lambda v: canonicalizeEmail(v.email), Success(valid)),
            lambda canonicalized:
            # Transform dead-end log to pass-through two-track
            bind(map(tee(logUser), Success(canonicalized)), lambda logged:
            # Transform exception-thrower to two-track
            bind(
                tryCatch(encryptPassword, lambda e: Error(str(e)))(valid.password),
                lambda encrypted:
                saveToDb(logged, encrypted)
            )))))
    )

# All functions now uniform - easy to compose and rearrange
```

### Railway diagrams

```
Single-track function (one input, one output):
    ─────[ f ]─────

Switch function (one input, two outputs - Success or Failure):
    ───┬─[ f ]─── Success
       └────────── Failure

Two-track function (two inputs, two outputs):
    ───┬─[ f ]─┬─── Success
       │       └─── Failure (from success track)
    ───┴─────────── Failure (passthrough)

Pipeline of switches with bind:
    ───┬─[ f1 ]─┬─[ f2 ]─┬─[ f3 ]─┬─── Success
       └────────┴────────┴────────┴─── Failure

All functions uniform after transformation:
    ───┬─[ switch ]─┬─[ map g ]─┬─[ tee h ]─┬─── Success
       └────────────┴───────────┴───────────┴─── Failure
```

## Error classification and handling strategies

Not all errors should be modeled the same way.
Understanding error categories helps choose appropriate handling strategies.

### Three categories of errors

Following Wlaschin's classification from "Domain Modeling Made Functional":

**1. Domain errors** - Expected outcomes of domain operations
- Subject matter experts can describe them
- Part of normal workflow, not exceptional
- Have established procedures for handling
- Should be modeled explicitly as Result types

Examples:
- Validation failures (invalid email format)
- Business rule violations (insufficient funds)
- Not found errors (user doesn't exist)
- Convergence failures (model didn't converge)

**2. Infrastructure errors** - Technical/architectural failures
- Technical concerns outside domain logic
- May be transient (retry can help)
- Outside subject matter expert vocabulary
- Can model as Result or use exceptions

Examples:
- Network timeouts
- Database connection failures
- Disk full, out of memory
- Authentication/authorization failures

**3. Panics** - Unrecoverable system errors
- System in unknown state
- Usually programmer errors
- Cannot meaningfully continue
- Should use exceptions/panics

Examples:
- Division by zero (bug in code)
- Array index out of bounds (logic error)
- Null/None when value guaranteed (broken invariant)
- Stack overflow, out of memory

### Decision tree

Ask: "Would a subject matter expert recognize this error as part of the domain?"

```
Is this a domain concept?
├─ Yes → Domain error
│         Model explicitly with Result
│         Example: OrderQuantityMustBePositive
│
└─ No → Ask: "Can we meaningfully continue?"
         ├─ Yes → Infrastructure error
         │         Consider modeling as Result
         │         Example: DatabaseTemporarilyUnavailable
         │
         └─ No → Panic
                  Use exceptions/panics
                  Example: IndexOutOfBounds (programmer error)
```

### Handling strategies by category

**Domain errors with Result**:

```python
from expression import Result, Ok, Error

# Model domain errors explicitly
@dataclass
class ValidationError:
    field: str
    reason: str

@dataclass
class InsufficientFunds:
    account_id: str
    balance: Decimal
    requested: Decimal

DomainError = ValidationError | InsufficientFunds

def process_payment(
    account: Account,
    amount: Decimal
) -> Result[Payment, DomainError]:
    """Domain operation that can fail with known errors."""
    if amount > account.balance:
        return Error(InsufficientFunds(
            account_id=account.id,
            balance=account.balance,
            requested=amount
        ))

    return Ok(Payment(account=account, amount=amount))
```

**Infrastructure errors - explicit or exception**:

```python
# Option 1: Model explicitly with Result
@dataclass
class DatabaseError:
    operation: str
    exception: str

async def save_to_database(
    data: Data
) -> Result[SavedData, DatabaseError]:
    try:
        result = await db.save(data)
        return Ok(result)
    except Exception as e:
        return Error(DatabaseError("save", str(e)))

# Option 2: Let exception propagate
async def save_to_database(data: Data) -> SavedData:
    """May raise DatabaseException."""
    return await db.save(data)  # Exception if fails
```

**Panics - always exceptions**:

```python
def get_first_element(items: list[T]) -> T:
    """
    Get first element.

    Precondition: items must be non-empty.
    Raises AssertionError if violated (programmer error).
    """
    assert len(items) > 0, "items must be non-empty"
    return items[0]

# Better: Use types to make precondition unrepresentable
from typing import NewType

NonEmptyList = NewType('NonEmptyList', list)

def get_first_element(items: NonEmptyList[T]) -> T:
    """Get first element. Type guarantees non-empty."""
    return items[0]  # Safe - type prevents empty list
```

### Composing different error types

When workflows combine operations with different error types:

```python
from typing import Union

# Unified error type for workflow
WorkflowError = (
    ValidationError |
    InsufficientFunds |
    DatabaseError
)

def process_order_workflow(
    order: UnvalidatedOrder
) -> Result[OrderConfirmation, WorkflowError]:
    """Workflow combining domain and infrastructure errors."""
    return (
        validate_order(order)              # Result[ValidOrder, ValidationError]
        .map_error(lambda e: e)            # Widen to WorkflowError
        .bind(process_payment)             # Result[Payment, InsufficientFunds]
        .map_error(lambda e: e)            # Widen to WorkflowError
        .bind(save_to_database)            # Result[Saved, DatabaseError]
        .map_error(lambda e: e)            # Widen to WorkflowError
    )
```

### Guidelines

1. **Default to Result for domain errors**: If domain experts discuss it, model it explicitly
2. **Infrastructure errors are judgment calls**: Model explicitly if need fine-grained control, use exceptions if want to fail fast
3. **Never catch panics in domain logic**: Panics indicate bugs, not business scenarios
4. **Use types to prevent panics**: Make invalid states unrepresentable instead of asserting
5. **Document error possibilities**: Function signatures should show what can go wrong

### Cross-language error handling

**Python**:
- Domain: Result from Expression library
- Infrastructure: Result or raise exceptions
- Panics: assert, raise RuntimeError

**TypeScript**:
- Domain: Either from fp-ts or Effect.Effect
- Infrastructure: Either or throw Error
- Panics: throw Error, assert

**Rust**:
- Domain: Result<T, E> with custom error types
- Infrastructure: Result or anyhow::Result
- Panics: panic!, assert

**See also**:
- domain-modeling.md#pattern-6-domain-errors-vs-infrastructure-errors for detailed examples
- Language-specific docs (python-development.md, typescript-nodejs-development.md, rust-development/02-error-handling.md) for error type hierarchies

## Integration with data pipelines

### SQLMesh models as pure functions

Treat SQLMesh models as pure, composable functions in the Result world.

```sql
-- Each model is a function: Input → Output
MODEL (
  name analytics.validated_events,
  kind INCREMENTAL_BY_TIME_RANGE(time_column created_at),
  dialect postgres
);

-- Function signature: raw_events → validated_events OR audit_failures
SELECT
  event_id,
  event_type,
  payload,
  created_at
FROM raw_events
WHERE
  -- Validation: only pass through valid events
  event_type IN ('UserCreated', 'UserUpdated', 'UserDeleted')
  AND jsonb_typeof(payload) = 'object'
  AND created_at IS NOT NULL;

-- Invalid events go to audit table (failure track)
MODEL (
  name analytics.event_validation_failures,
  kind FULL
);

SELECT
  event_id,
  event_type,
  'invalid_event_type' as failure_reason
FROM raw_events
WHERE event_type NOT IN ('UserCreated', 'UserUpdated', 'UserDeleted')

UNION ALL

SELECT
  event_id,
  event_type,
  'invalid_payload' as failure_reason
FROM raw_events
WHERE jsonb_typeof(payload) != 'object';
```

### Composing models with Result semantics

```sql
-- Success track: validated events → aggregated metrics
MODEL (
  name analytics.user_stats,
  kind INCREMENTAL_BY_TIME_RANGE(time_column event_date)
);

SELECT
  user_id,
  DATE(created_at) as event_date,
  COUNT(*) as event_count
FROM {{ ref('validated_events') }}  -- Only valid events
WHERE event_type = 'UserCreated'
GROUP BY user_id, DATE(created_at);

-- Failure track: collect all validation failures
MODEL (
  name analytics.data_quality_metrics,
  kind FULL
);

SELECT
  'event_validation' as check_name,
  COUNT(*) as failure_count,
  CURRENT_TIMESTAMP as checked_at
FROM {{ ref('event_validation_failures') }};
```

## Testing railway-oriented code

### Property-based testing for bind/apply

```python
from hypothesis import given, strategies as st

# Test bind law: bind is associative
@given(
    st.integers(),
    st.integers()
)
def test_bind_associativity(x: int, y: int):
    """(m >>= f) >>= g  ===  m >>= (\x -> f x >>= g)"""
    m = Success(x)
    f = lambda a: Success(a + y)
    g = lambda b: Success(b * 2)

    left = bind(bind(m, f), g)
    right = bind(m, lambda a: bind(f(a), g))

    assert left == right

# Test apply collects all errors
@given(st.text(), st.text(), st.text())
def test_apply_collects_errors(email: str, name: str, age: str):
    """Applicative should collect errors from all validations"""
    result = validateUser({'email': email, 'name': name, 'age': age})

    match result:
        case Failure(errors):
            # Count how many fields are actually invalid
            expected_errors = 0
            if '@' not in email:
                expected_errors += 1
            if not name:
                expected_errors += 1
            try:
                if int(age) < 0:
                    expected_errors += 1
            except:
                expected_errors += 1

            assert len(errors) == expected_errors
        case Success(_):
            # All fields must be valid
            assert '@' in email
            assert name
            assert int(age) >= 0
```

## Integration with other preferences

See `~/.claude/commands/preferences/algebraic-data-types.md` for:
- How to model domain types that work with Result
- Sum types for error variants
- Newtypes for validated values

See `~/.claude/commands/preferences/schema-versioning.md` for:
- Configuring sqlc to generate Result-returning queries
- Database operations in railway-oriented style

See `~/.claude/commands/preferences/data-modeling.md` for:
- How ROP fits into data pipeline architecture
- Effect isolation at boundaries
- Monad transformer stack vision
