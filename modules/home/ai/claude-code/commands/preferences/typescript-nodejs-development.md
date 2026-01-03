# TypeScript / Node.js Development

## Architectural patterns alignment

See @~/.claude/commands/preferences/architectural-patterns.md for overarching principles.

For React UI development with TanStack ecosystem, see @~/.claude/commands/preferences/react-tanstack-ui-development.md.

TypeScript with Effect-TS provides excellent support for functional programming and effect management in the JavaScript ecosystem.

### Recommended libraries for functional programming
- **Effect system**: Effect-TS for composable, type-safe effects and monad transformers
- **Error handling**: Use Effect-TS's `Either`, `Option`, and `Effect` types instead of try/catch
- **Immutability**: Effect-TS's built-in immutable data structures or `immer` for updates
- **Validation**: `@effect/schema` for runtime validation and type derivation
- **Functional utilities**: Effect-TS provides comprehensive functional programming primitives

### Functional programming patterns
- Encode all effects explicitly in type signatures using Effect types
- Use `Effect<Success, Error, Requirements>` for effectful computations
- Compose effects with `flatMap`/`map`/`zip` instead of async/await when using Effect-TS
- Thread dependencies through `Context` (Reader pattern) instead of global variables
- Use `Either<E, A>` and `Option<A>` for error handling instead of null/undefined/exceptions
- Layer your application as effect transformers (similar to monad transformer stacks)

For detailed patterns on Result types, error composition, and ADT modeling in TypeScript:
- **~/.claude/commands/preferences/railway-oriented-programming.md** - Result type implementation, bind/apply, effect composition
- **~/.claude/commands/preferences/algebraic-data-types.md** - Discriminated unions, branded types (newtypes), domain modeling

### TypeScript-specific practices
- Enable strict mode in tsconfig.json (`strict: true`)
- Leverage discriminated unions for state machines and domain modeling
- Use `const` assertions and `as const` for literal type inference
- Avoid `any` type; use `unknown` when type is truly unknown

## Functional domain modeling in TypeScript

This section demonstrates how to implement functional domain modeling patterns in TypeScript with Effect-TS.
For pattern descriptions, see domain-modeling.md.
For theoretical foundations, see theoretical-foundations.md.

### Pattern 1: Smart constructors with branded types

Use branded types to create newtypes with guaranteed invariants.

**Example: Validated measurement types**

```typescript
import { Brand } from "effect";
import { Either } from "effect/Either";
import * as E from "effect/Either";

// Branded type for quality score
type QualityScore = number & Brand.Brand<"QualityScore">;

const QualityScore = Brand.refined<QualityScore>(
  (value): value is QualityScore & Brand.Brand.Unbranded<QualityScore> =>
    value >= 0 && value <= 1,
  (value) => Brand.error(`QualityScore must be in [0,1], got ${value}`)
);

// Branded type for uncertainty
type Uncertainty = number & Brand.Brand<"Uncertainty">;

const Uncertainty = Brand.refined<Uncertainty>(
  (value): value is Uncertainty & Brand.Brand.Unbranded<Uncertainty> =>
    value > 0,
  (value) => Brand.error(`Uncertainty must be positive, got ${value}`)
);

// Measurement with validated components
interface Measurement {
  readonly value: number;
  readonly uncertainty: Uncertainty;
  readonly qualityScore: QualityScore;
}

// Smart constructor for Measurement
const createMeasurement = (
  value: number,
  uncertainty: number,
  qualityScore: number
): Either.Either<Measurement, string> => {
  const uncResult = Uncertainty(uncertainty);
  if (E.isLeft(uncResult)) {
    return E.left(uncResult.left.message);
  }

  const qualResult = QualityScore(qualityScore);
  if (E.isLeft(qualResult)) {
    return E.left(qualResult.left.message);
  }

  // Additional cross-field validation
  if (Math.abs(uncertainty) > Math.abs(value) * 10) {
    return E.left(
      `Uncertainty ${uncertainty} too large relative to value ${value}`
    );
  }

  return E.right({
    value,
    uncertainty: uncResult.right,
    qualityScore: qualResult.right,
  });
};

// Usage
const measurementResult = createMeasurement(10.0, 0.5, 0.95);
// Type: Either<Measurement, string>
```

**Alternative: Using @effect/schema**

```typescript
import * as S from "@effect/schema/Schema";
import * as ParseResult from "@effect/schema/ParseResult";

// Schema-based validation
const MeasurementSchema = S.Struct({
  value: S.Number,
  uncertainty: S.Number.pipe(
    S.filter((n) => n > 0, {
      message: () => "uncertainty must be positive",
    })
  ),
  qualityScore: S.Number.pipe(
    S.filter((n) => n >= 0 && n <= 1, {
      message: () => "quality score must be in [0,1]",
    })
  ),
});

type Measurement = S.Schema.Type<typeof MeasurementSchema>;

// Decode/validate
const parseMeasurement = S.decodeUnknownEither(MeasurementSchema);

const result = parseMeasurement({
  value: 10.0,
  uncertainty: 0.5,
  qualityScore: 0.95,
});
```

**See also**: domain-modeling.md#pattern-2-smart-constructors-for-invariants

### Pattern 2: State machines with discriminated unions

Use discriminated unions to model entity lifecycles.

**Example: Data processing pipeline states**

```typescript
// State 1: Raw observations
interface RawObservations {
  readonly type: "raw";
  readonly values: ReadonlyArray<number>;
  readonly metadata: Record<string, string>;
}

// State 2: Calibrated data
interface CalibratedData {
  readonly type: "calibrated";
  readonly measurements: ReadonlyArray<Measurement>;
  readonly calibrationParams: Record<string, number>;
}

// State 3: Inferred results
interface InferredResults {
  readonly type: "inferred";
  readonly parameters: Record<string, number>;
  readonly logLikelihood: number;
  readonly convergenceInfo: Record<string, boolean>;
}

// State 4: Validated model
interface ValidatedModel {
  readonly type: "validated";
  readonly parameters: Record<string, number>;
  readonly diagnostics: Record<string, number>;
  readonly validationTimestamp: string;
}

// Discriminated union of all states
type DataState =
  | RawObservations
  | CalibratedData
  | InferredResults
  | ValidatedModel;

// Pattern matching helper
const matchDataState = <R>(handlers: {
  raw: (state: RawObservations) => R;
  calibrated: (state: CalibratedData) => R;
  inferred: (state: InferredResults) => R;
  validated: (state: ValidatedModel) => R;
}) => (state: DataState): R => {
  switch (state.type) {
    case "raw":
      return handlers.raw(state);
    case "calibrated":
      return handlers.calibrated(state);
    case "inferred":
      return handlers.inferred(state);
    case "validated":
      return handlers.validated(state);
  }
};

// Usage
const getDescription = matchDataState({
  raw: (s) => `Raw: ${s.values.length} observations`,
  calibrated: (s) => `Calibrated: ${s.measurements.length} measurements`,
  inferred: (s) => `Inferred: ${Object.keys(s.parameters).length} parameters`,
  validated: (s) => `Validated: ${Object.keys(s.diagnostics).length} diagnostics`,
});
```

**State transitions as functions with Effect**

```typescript
import { Effect } from "effect";
import * as E from "effect/Effect";

// Error types for each transition
class CalibrationError {
  readonly _tag = "CalibrationError";
  constructor(readonly message: string) {}
}

class InferenceError {
  readonly _tag = "InferenceError";
  constructor(readonly message: string) {}
}

class ValidationError {
  readonly _tag = "ValidationError";
  constructor(readonly message: string) {}
}

// Transition 1: Raw → Calibrated
const calibrate = (
  calibrationModel: (raw: number, metadata: Record<string, string>) =>
    [number, number, number],
  qualityThreshold: number,
  raw: RawObservations
): Effect.Effect<CalibratedData, CalibrationError> =>
  E.try({
    try: () => {
      const measurements = raw.values.map((rawValue) => {
        const [value, uncertainty, quality] = calibrationModel(
          rawValue,
          raw.metadata
        );

        if (quality < qualityThreshold) {
          throw new CalibrationError(
            `Quality ${quality} below threshold ${qualityThreshold}`
          );
        }

        const measurementResult = createMeasurement(value, uncertainty, quality);
        if (E.isLeft(measurementResult)) {
          throw new CalibrationError(measurementResult.left);
        }

        return measurementResult.right;
      });

      return {
        type: "calibrated" as const,
        measurements,
        calibrationParams: { model: calibrationModel.name },
      };
    },
    catch: (error) =>
      error instanceof CalibrationError
        ? error
        : new CalibrationError(String(error)),
  });

// Transition 2: Calibrated → Inferred
const infer = (
  inferenceAlgorithm: (measurements: ReadonlyArray<Measurement>) => {
    parameters: Record<string, number>;
    logLikelihood: number;
    convergence: Record<string, boolean>;
  },
  calibrated: CalibratedData
): Effect.Effect<InferredResults, InferenceError> =>
  E.try({
    try: () => {
      const result = inferenceAlgorithm(calibrated.measurements);
      return {
        type: "inferred" as const,
        parameters: result.parameters,
        logLikelihood: result.logLikelihood,
        convergenceInfo: result.convergence,
      };
    },
    catch: (error) => new InferenceError(String(error)),
  });

// Transition 3: Inferred → Validated
const validateModel = (
  validationMetrics: Record<string, (params: Record<string, number>) => number>,
  inferred: InferredResults
): Effect.Effect<ValidatedModel, ValidationError> =>
  E.try({
    try: () => {
      const diagnostics: Record<string, number> = {};

      for (const [name, metricFn] of Object.entries(validationMetrics)) {
        diagnostics[name] = metricFn(inferred.parameters);
      }

      const allPass = Object.values(diagnostics).every((v) => v > 0.9);
      if (!allPass) {
        throw new ValidationError(
          `Diagnostics failed: ${JSON.stringify(diagnostics)}`
        );
      }

      return {
        type: "validated" as const,
        parameters: inferred.parameters,
        diagnostics,
        validationTimestamp: new Date().toISOString(),
      };
    },
    catch: (error) =>
      error instanceof ValidationError
        ? error
        : new ValidationError(String(error)),
  });
```

**See also**: domain-modeling.md#pattern-3-state-machines-for-entity-lifecycles

### Pattern 3: Workflows with dependencies using Effect Context

Model workflows with explicit dependencies using Effect's Context system.

**Example: Complete processing workflow**

```typescript
import { Context, Layer } from "effect";

// Define dependency types as services
interface CalibrationModel {
  readonly calibrate: (
    raw: number,
    metadata: Record<string, string>
  ) => [number, number, number];
}

const CalibrationModel = Context.GenericTag<CalibrationModel>(
  "@services/CalibrationModel"
);

interface QualityThreshold {
  readonly value: number;
}

const QualityThreshold = Context.GenericTag<QualityThreshold>(
  "@services/QualityThreshold"
);

interface InferenceAlgorithm {
  readonly infer: (measurements: ReadonlyArray<Measurement>) => {
    parameters: Record<string, number>;
    logLikelihood: number;
    convergence: Record<string, boolean>;
  };
}

const InferenceAlgorithm = Context.GenericTag<InferenceAlgorithm>(
  "@services/InferenceAlgorithm"
);

interface ValidationMetrics {
  readonly metrics: Record<string, (params: Record<string, number>) => number>;
}

const ValidationMetrics = Context.GenericTag<ValidationMetrics>(
  "@services/ValidationMetrics"
);

// Unified error type for workflow
type ProcessingError = CalibrationError | InferenceError | ValidationError;

// Complete workflow using Context for dependency injection
const processObservations = (
  raw: RawObservations
): Effect.Effect<
  ValidatedModel,
  ProcessingError,
  CalibrationModel | QualityThreshold | InferenceAlgorithm | ValidationMetrics
> =>
  E.gen(function* (_) {
    // Access dependencies from context
    const calibrationModel = yield* _(CalibrationModel);
    const qualityThreshold = yield* _(QualityThreshold);
    const inferenceAlg = yield* _(InferenceAlgorithm);
    const validationMetrics = yield* _(ValidationMetrics);

    // Compose workflow steps
    const calibrated = yield* _(
      calibrate(
        calibrationModel.calibrate,
        qualityThreshold.value,
        raw
      )
    );

    const inferred = yield* _(
      infer(inferenceAlg.infer, calibrated)
    );

    const validated = yield* _(
      validateModel(validationMetrics.metrics, inferred)
    );

    return validated;
  });

// Create implementations (layers)
const DefaultCalibrationModelLive = Layer.succeed(CalibrationModel, {
  calibrate: (raw, metadata) => {
    const value = raw * 1.1;
    const uncertainty = Math.abs(value) * 0.05;
    const quality = 0.95;
    return [value, uncertainty, quality];
  },
});

const DefaultQualityThresholdLive = Layer.succeed(QualityThreshold, {
  value: 0.8,
});

const DefaultInferenceAlgorithmLive = Layer.succeed(InferenceAlgorithm, {
  infer: (measurements) => {
    const values = measurements.map((m) => m.value);
    const mean = values.reduce((a, b) => a + b, 0) / values.length;
    return {
      parameters: { mean },
      logLikelihood: -10.0,
      convergence: { converged: true },
    };
  },
});

const DefaultValidationMetricsLive = Layer.succeed(ValidationMetrics, {
  metrics: {
    metric1: (_params) => 0.95,
  },
});

// Combine all dependencies
const DefaultProcessingLive = Layer.mergeAll(
  DefaultCalibrationModelLive,
  DefaultQualityThresholdLive,
  DefaultInferenceAlgorithmLive,
  DefaultValidationMetricsLive
);

// Run workflow with provided dependencies
const raw: RawObservations = {
  type: "raw",
  values: [1.0, 2.0, 3.0],
  metadata: { source: "sensor_1" },
};

const program = processObservations(raw).pipe(
  E.provide(DefaultProcessingLive)
);

// Execute: Effect.runPromise(program)
```

**See also**:
- domain-modeling.md#pattern-4-workflows-as-type-safe-pipelines
- architectural-patterns.md#workflow-pipeline-architecture

### Pattern 4: Aggregates with consistency

Group related entities that must change together atomically.

**Example: Dataset aggregate with observations**

```typescript
import * as S from "@effect/schema/Schema";

// Entities within aggregate
const ObservationSchema = S.Struct({
  timestamp: S.Date,
  value: S.Number,
  metadata: S.Record(S.String, S.String),
});

type Observation = S.Schema.Type<typeof ObservationSchema>;

const DatasetIdSchema = S.Struct({
  value: S.String.pipe(S.nonEmpty()),
});

type DatasetId = S.Schema.Type<typeof DatasetIdSchema>;

const SummaryStatisticsSchema = S.Struct({
  count: S.Number,
  mean: S.Number,
  stdDev: S.Number,
  minValue: S.Number,
  maxValue: S.Number,
});

type SummaryStatistics = S.Schema.Type<typeof SummaryStatisticsSchema>;

// Aggregate root
interface Dataset {
  readonly id: DatasetId;
  readonly observations: ReadonlyArray<Observation>;
  readonly statistics: SummaryStatistics;
  readonly protocolId: string; // Reference to other aggregate (by ID only)
}

// Smart constructor that enforces invariants
const createDataset = (
  id: DatasetId,
  observations: ReadonlyArray<Observation>,
  protocolId: string
): Either.Either<Dataset, string> => {
  if (observations.length === 0) {
    return E.left("must provide at least one observation");
  }

  // Sort chronologically
  const sorted = [...observations].sort(
    (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
  );

  // Compute statistics
  const values = sorted.map((obs) => obs.value);
  const count = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / count;
  const variance =
    values.reduce((acc, v) => acc + Math.pow(v - mean, 2), 0) / count;
  const stdDev = Math.sqrt(variance);

  const statistics: SummaryStatistics = {
    count,
    mean,
    stdDev,
    minValue: Math.min(...values),
    maxValue: Math.max(...values),
  };

  return E.right({
    id,
    observations: sorted,
    statistics,
    protocolId,
  });
};

// Update operation that maintains invariants
const addObservation = (
  dataset: Dataset,
  observation: Observation
): Either.Either<Dataset, string> => {
  const newObservations = [...dataset.observations, observation];
  return createDataset(dataset.id, newObservations, dataset.protocolId);
};

// Usage
const obs1: Observation = {
  timestamp: new Date("2024-01-01T10:00:00"),
  value: 10.0,
  metadata: { sensor: "A" },
};

const obs2: Observation = {
  timestamp: new Date("2024-01-01T10:05:00"),
  value: 12.0,
  metadata: { sensor: "A" },
};

const datasetResult = createDataset(
  { value: "dataset-001" },
  [obs1, obs2],
  "protocol-001"
);

if (E.isRight(datasetResult)) {
  const dataset = datasetResult.right;
  console.log(`Dataset created with ${dataset.statistics.count} observations`);
  console.log(`Mean: ${dataset.statistics.mean}`);

  // Add new observation
  const obs3: Observation = {
    timestamp: new Date("2024-01-01T10:10:00"),
    value: 11.0,
    metadata: { sensor: "A" },
  };

  const updated = addObservation(dataset, obs3);
}
```

**See also**: domain-modeling.md#pattern-5-aggregates-as-consistency-boundaries

### Pattern 5: Error classification

Distinguish domain errors from infrastructure errors.

**Example: Error type hierarchy**

```typescript
// Domain errors: Part of problem domain logic
class DomainValidationError {
  readonly _tag = "DomainValidationError";
  constructor(
    readonly field: string,
    readonly reason: "OUT_OF_RANGE" | "INVALID_FORMAT" | "MISSING_REQUIRED",
    readonly message: string
  ) {}
}

class DomainCalibrationError {
  readonly _tag = "DomainCalibrationError";
  constructor(
    readonly reason: string,
    readonly qualityScore: number,
    readonly threshold: number
  ) {}
}

class DomainConvergenceError {
  readonly _tag = "DomainConvergenceError";
  constructor(
    readonly iterations: number,
    readonly finalLoss: number,
    readonly message: string
  ) {}
}

// Infrastructure errors: Technical/architectural concerns
class InfrastructureDatabaseError {
  readonly _tag = "InfrastructureDatabaseError";
  constructor(
    readonly operation: string,
    readonly exception: string
  ) {}
}

class InfrastructureNetworkError {
  readonly _tag = "InfrastructureNetworkError";
  constructor(
    readonly url: string,
    readonly statusCode: number | null,
    readonly exception: string
  ) {}
}

// Unified error types
type DomainError =
  | DomainValidationError
  | DomainCalibrationError
  | DomainConvergenceError;

type InfrastructureError =
  | InfrastructureDatabaseError
  | InfrastructureNetworkError;

type WorkflowError = DomainError | InfrastructureError;

// Functions returning specific error types
const validateInput = (
  data: unknown
): Effect.Effect<RawObservations, DomainValidationError> =>
  E.try({
    try: () => {
      if (typeof data !== "object" || data === null) {
        throw new DomainValidationError(
          "root",
          "INVALID_FORMAT",
          "data must be an object"
        );
      }

      const obj = data as Record<string, unknown>;

      if (!("values" in obj)) {
        throw new DomainValidationError(
          "values",
          "MISSING_REQUIRED",
          "values field is required"
        );
      }

      if (!Array.isArray(obj.values)) {
        throw new DomainValidationError(
          "values",
          "INVALID_FORMAT",
          "values must be an array"
        );
      }

      return {
        type: "raw" as const,
        values: obj.values as number[],
        metadata: (obj.metadata as Record<string, string>) || {},
      };
    },
    catch: (error) =>
      error instanceof DomainValidationError
        ? error
        : new DomainValidationError(
            "unknown",
            "INVALID_FORMAT",
            String(error)
          ),
  });

// Infrastructure operation
const saveToDatabase = (
  dataset: Dataset
): Effect.Effect<string, InfrastructureDatabaseError> =>
  E.tryPromise({
    try: async () => {
      // Simulate database save
      await new Promise((resolve) => setTimeout(resolve, 10));
      return `saved-${dataset.id.value}`;
    },
    catch: (error) =>
      new InfrastructureDatabaseError("save_dataset", String(error)),
  });
```

**See also**: domain-modeling.md#pattern-7-domain-errors-vs-infrastructure-errors

### Complete example: Temporal data processing

```typescript
/**
 * Complete example: Temporal data processing pipeline
 *
 * Demonstrates:
 * - Smart constructors (branded types)
 * - State machines (pipeline stages)
 * - Workflows (Effect with Context)
 * - Aggregates (dataset with observations)
 * - Error handling (domain vs infrastructure)
 */

import { Effect, Context, Layer } from "effect";
import * as E from "effect/Effect";

// ============================================================================
// Application: Command and event handling
// ============================================================================

interface ProcessDataCommand {
  readonly rawData: RawObservations;
  readonly timestamp: Date;
  readonly userId: string;
  readonly requestId: string;
}

interface DataProcessed {
  readonly type: "DataProcessed";
  readonly model: ValidatedModel;
  readonly processingTime: number;
  readonly timestamp: Date;
}

interface ProcessingFailedEvent {
  readonly type: "ProcessingFailed";
  readonly error: ProcessingError;
  readonly timestamp: Date;
}

type ProcessingEvent = DataProcessed | ProcessingFailedEvent;

// Handle command and emit events
const handleProcessDataCommand = (
  command: ProcessDataCommand
): Effect.Effect<
  ReadonlyArray<ProcessingEvent>,
  never,
  CalibrationModel | QualityThreshold | InferenceAlgorithm | ValidationMetrics
> =>
  E.gen(function* (_) {
    const startTime = Date.now();

    // Execute workflow (may fail)
    const result = yield* _(
      processObservations(command.rawData).pipe(E.either)
    );

    // Convert result to events
    if (E.isRight(result)) {
      return [
        {
          type: "DataProcessed" as const,
          model: result.right,
          processingTime: Date.now() - startTime,
          timestamp: new Date(),
        },
      ];
    } else {
      return [
        {
          type: "ProcessingFailed" as const,
          error: result.left,
          timestamp: new Date(),
        },
      ];
    }
  });

// ============================================================================
// Main program
// ============================================================================

const main = E.gen(function* (_) {
  const command: ProcessDataCommand = {
    rawData: {
      type: "raw",
      values: [1.0, 2.0, 3.0, 4.0, 5.0],
      metadata: { source: "sensor_A", experiment: "exp_001" },
    },
    timestamp: new Date(),
    userId: "user_123",
    requestId: "req_456",
  };

  const events = yield* _(handleProcessDataCommand(command));

  for (const event of events) {
    switch (event.type) {
      case "DataProcessed":
        console.log(`Success! Processed in ${event.processingTime}ms`);
        console.log(`Parameters: ${JSON.stringify(event.model.parameters)}`);
        console.log(`Diagnostics: ${JSON.stringify(event.model.diagnostics)}`);
        break;

      case "ProcessingFailed":
        console.log(`Failed: ${event.error}`);
        break;
    }
  }
});

// Run program with dependencies
const runnable = main.pipe(E.provide(DefaultProcessingLive));

// Execute: Effect.runPromise(runnable)
```

**Key takeaways**:

1. **Types enforce invariants**: Branded types prevent mixing incompatible values
2. **State machines explicit**: RawObservations → CalibratedData → InferredResults → ValidatedModel
3. **Dependencies via Context**: Type-safe dependency injection with Effect Context
4. **Errors typed**: DomainError vs InfrastructureError distinction
5. **Effect composition**: Workflow steps composed with flatMap/gen
6. **Testable**: Easy to swap implementations via Layers

**See also**:
- domain-modeling.md for pattern details
- architectural-patterns.md for application structure
- railway-oriented-programming.md for Either/Effect composition

## Development practices

- Use TypeScript over JavaScript
- Use ES modules (import/export) syntax, not CommonJS (require)
- Run type checking with `tsc --noEmit` before committing
- Use ESLint with TypeScript rules for additional safety
- Consider using Biome or Prettier for consistent formatting
