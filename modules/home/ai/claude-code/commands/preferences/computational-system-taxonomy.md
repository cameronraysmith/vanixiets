# Computational system taxonomy

## Purpose

This document establishes terminological and architectural clarity about computational system types.
Understanding the distinction between closed and open systems is fundamental to choosing appropriate design patterns and avoiding category errors when composing heterogeneous components.

Topics covered:
- Closed vs open systems from automata theory and process calculi
- Industry terminology mapping (batch, stream, services)
- Functional reactive programming formulations
- Essential vs accidental UI complexity
- Composition patterns for heterogeneous systems

For architectural implementation patterns, see architectural-patterns.md.
For FRP foundations, see functional-reactive-programming.md.
For hypermedia patterns, see hypermedia-development/00-index.md.

## System classification by computational model

### Closed vs open systems

The fundamental distinction comes from automata theory and process calculi.

A *closed system* has all inputs determined before execution begins.
No interaction with the environment occurs during computation.
The denotational semantics is a pure function from inputs to outputs: `Inputs -> Outputs`.
Examples include compilers, batch data transformations, and scientific simulations with fixed parameters.

An *open system* interacts with its environment during execution.
Inputs arrive over time; behavior depends on both timing and content of external events.
Pure denotational semantics are insufficient; the system requires process algebra (CSP, CCS, pi-calculus) or coalgebraic formulations to specify behavior.
Examples include web servers, interactive applications, and reactive dashboards.

### Industry terminology mapping

The closed/open distinction manifests across multiple industry domains with different vocabulary.

For closed or offline systems, common terms include batch processing, pipelines, workflows, and jobs.
These systems process bounded input to produce bounded output.
Execution has a clear start and end.

For open or online systems, common terms include services, reactive applications, and interactive systems.
These systems process unbounded input streams and may run indefinitely.
Behavior emerges from ongoing interaction with the environment.

### Algorithms perspective

Algorithm theory formalizes this distinction precisely.

An *offline algorithm* receives complete input before producing output.
The algorithm can examine the entire input when making decisions.
Optimal solutions are often achievable because all information is available.

An *online algorithm* receives input incrementally and must make decisions before seeing future input.
Competitive analysis measures performance against an omniscient adversary.
Optimal decisions may be impossible because future events are unknown.

## Batch vs stream processing

Data engineering applies the closed/open distinction to data pipelines.

*Batch processing* operates on bounded datasets.
The job processes all available data and terminates.
Examples include Flyte workflows, Spark jobs, and MapReduce.
Correctness is defined by the final output matching the specification.

*Stream processing* operates on unbounded event streams.
The system runs continuously, processing events as they arrive.
Examples include Kafka Streams, Flink, and Apache Beam in streaming mode.
Correctness involves properties like exactly-once semantics and event-time handling.

The same computation may be expressible in both paradigms.
The choice depends on latency requirements, data characteristics, and operational constraints.
Batch is simpler when bounded datasets and higher latency are acceptable.
Streaming is necessary when continuous processing or low latency is required.

## Functional reactive programming and interactivity

Conal Elliott's FRP formulation provides precise semantics for reactive systems while preserving denotational reasoning.

A *Behavior a* is a time-varying value with denotation `Time -> a`.
Behaviors represent continuous signals like mouse position, current temperature, or animation parameters.
They always have a value at every point in time.

An *Event a* represents discrete occurrences with denotation `[(Time, a)]`.
Events represent user clicks, network messages, or timer firings.
They have values only at specific moments.

A reactive program is a function from input events and behaviors to output events and behaviors.
The program itself has denotational semantics; only the environment introducing events is non-deterministic.
This provides compositional reasoning about reactive systems that process algebra approaches lack.

The key insight is that FRP makes the *program* closed even though the *system* (program plus environment) is open.
The program is a pure function; non-determinism is isolated to the environment boundary.

## Essential vs accidental UI complexity

Fred Brooks' distinction between essential and accidental complexity applies directly to interactive systems.

### Essential complexity

Certain challenges are inherent to interactive systems and cannot be eliminated.

*Environmental non-determinism* means user events arrive unpredictably.
The system cannot know when or what the user will do next.
This is fundamental to interactivity.

*Reactivity* means the UI must respond to events and propagate state changes.
User actions must produce visible effects.
State changes must flow to dependent UI components.

FRP addresses essential complexity by providing compositional dataflow specification.
The programmer declares relationships; the runtime propagates changes.
This is the minimum necessary complexity for interactive systems.

### Accidental complexity

Other challenges arise from architectural choices and can be eliminated.

*Distributed state* occurs when both client and server maintain application state.
Synchronization becomes necessary to keep them consistent.
Conflicts and race conditions emerge from concurrent modification.

*Client-side domain logic* duplicates business rules on the client.
Validation, authorization, and computation must be kept in sync with server logic.
Bugs from divergence are subtle and persistent.

*Optimistic updates* require the client to predict server responses.
Rollback logic handles prediction failures.
The client becomes coupled to server implementation details.

### The hypermedia resolution

Hypermedia architecture eliminates accidental complexity by returning to the web's original model.

The server is the source of truth.
It holds application state and executes all domain logic.
There is no client-side state to synchronize because the client has none.

The client is a viewer with local reactivity but no domain state.
Signals handle UI state like form inputs and visibility toggles.
No domain concepts like user sessions, shopping carts, or workflow states exist on the client.

Communication occurs via Server-Sent Events.
The server pushes HTML fragments and signal updates.
The client renders what it receives without interpretation.

The client is a terminal, not a peer in a distributed system.
This eliminates synchronization, conflict resolution, and logic duplication by construction.
The only remaining complexity is essential: environmental non-determinism and local reactivity.

## Composing closed and open systems

Real applications often require both batch computation and reactive presentation.
The key is composing them through well-defined interfaces rather than forcing one model onto the other.

### The process manager pattern

A reactive system coordinates batch computations without becoming one.

The reactive system issues commands such as "submit workflow with these parameters."
The batch system executes to completion, oblivious to the reactive context.
Results are written to stable storage like DuckLake on HuggingFace.
The reactive system queries results via DuckDB httpfs or similar read interfaces.

This is the Process Manager or Saga pattern applied to compute orchestration.
Coordination is asynchronous; no runtime coupling exists between systems.

### Preserving computational models

The closed system does not become reactive.
It processes its inputs and produces outputs as a pure function.
Adding reactivity would violate its design assumptions and introduce unnecessary complexity.

The reactive system does not become batch.
It responds to events and maintains ongoing interaction with users.
Blocking on batch completion would break responsiveness.

They compose through interfaces: command submission, progress polling, result retrieval.
Each system operates according to its natural computational model.

### Practical example

Consider a computational biology dashboard backed by expensive model training.

The dashboard (ironstar/lakescope) is reactive.
Users interact with visualizations, filter data, and request new analyses.
FRP patterns handle UI state and user events.

Model training (pyrovelocity on Flyte) is batch.
Training runs for hours on GPU clusters.
The workflow has fixed inputs and produces fixed outputs.

Integration uses the process manager pattern.
The dashboard submits workflow requests via Flyte API.
Progress is polled or pushed via webhooks.
Results land in DuckLake and are queried via httpfs.
The dashboard never blocks; the workflow never reacts.

## Architectural implications

When designing systems, apply classification-appropriate patterns.

First, identify whether each component is closed or open.
Closed components are pure functions; open components are reactive processes.
Misclassification leads to fighting the natural structure.

Second, use appropriate patterns for each component type.
Pure functions compose via function composition.
Reactive systems compose via FRP combinators or process algebra.
Mixing paradigms within a component creates confusion.

Third, compose heterogeneous components through async interfaces.
Commands, events, and polling bridge closed and open worlds.
Shared databases or message queues provide integration points.
Avoid runtime coupling that would force paradigm mixing.

Fourth, prefer hypermedia for UI to eliminate accidental distributed state complexity.
Server-rendered HTML with SSE updates is simpler than client-side state management.
Reserve client complexity for genuine interactivity requirements like drag-and-drop or offline support.
