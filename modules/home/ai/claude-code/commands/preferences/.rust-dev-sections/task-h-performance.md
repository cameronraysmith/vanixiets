## Performance

### Hot path identification and profiling discipline

Identify early in the development process whether your crate is performance or COGS relevant.
For performance-sensitive code, establish a regular profiling discipline from the start rather than treating optimization as an afterthought.

**Early identification checklist:**

- Identify hot paths during design phase and create benchmarks around them
- Document performance-sensitive areas in code comments and module documentation
- Set measurable performance targets (latency bounds, throughput goals, memory budgets)
- Regularly run profilers collecting CPU and allocation insights

**Profiling tools and workflow:**

- Use `cargo flamegraph` for visualizing CPU time spent in functions
- Use `perf` for detailed CPU performance counter analysis on Linux
- Profile both debug and release builds to understand optimization impact
- Profile with realistic workloads that exercise hot paths under production-like conditions
- Run benchmarks on CI to detect performance regressions

**Common hot path performance issues:**

Profiling frequently reveals these optimization opportunities:

- Short-lived allocations that could use bump allocation or arena patterns
- Memory copy overhead from cloning `String`s and collections unnecessarily
- Repeated re-hashing of equal data structures (consider `FxHashMap` for non-cryptographic hashing)
- Use of Rust's default hasher where collision resistance is not required
- Missed opportunities for zero-cost abstractions (unnecessary trait objects, excessive generics monomorphization)

Anecdotally, addressing only some `String` allocation problems can yield approximately 15% benchmark gains on hot paths, with highly optimized versions potentially achieving up to 50% improvements.

### Throughput optimization for batch processing

Optimize for throughput using items-per-CPU-cycle as the primary metric for batch processing workloads.
While latency matters and cannot be scaled horizontally the way throughput can, avoid paying for latency with empty cycles that come from single-item processing, contended locks, and frequent task switching.

**Throughput optimization principles:**

- Partition reasonable chunks of work upfront rather than discovering work incrementally
- Let individual threads and tasks deal with their slice of work independently
- Sleep or yield when no work is present rather than hot spinning
- Design your own APIs for batched operations where single-item APIs would force inefficiency
- Perform work via batched APIs where available from dependencies
- Yield within long individual items or between chunks of batches (see async cooperative scheduling below)
- Exploit CPU caches through temporal and spatial locality (access related data together, reuse recently accessed data)

**Anti-patterns to avoid:**

- Hot spinning to receive individual items faster (wastes CPU cycles, prevents other tasks from running)
- Processing work on individual items when batching is possible (increases per-item overhead, loses vectorization opportunities)
- Work stealing or similar strategies to balance individual items (introduces synchronization overhead for marginal gains)
- Single-item channel processing in tight loops (context switch overhead dominates useful work)

**Shared state considerations:**

Only use shared state when the cost of sharing (synchronization, cache coherence, false sharing) is less than the cost of re-computation or re-fetching.
Consider using thread-local copies, message passing, or immutable shared data to avoid synchronization overhead.

### Async cooperative scheduling and yield points

Long-running tasks must cooperatively yield to prevent starving other tasks of CPU time.
Futures executed in runtimes that cannot work around blocking or long-running tasks cause runtime overhead and degrade system responsiveness.

**Automatic yielding through I/O:**

Tasks performing I/O regularly utilize await points to preempt themselves automatically:

```rust
async fn process_items(items: &[Item]) {
    // Keep processing items, the runtime will preempt you automatically
    for item in items {
        read_item(item).await; // I/O operation provides natural yield point
    }
}
```

**Explicit yielding for CPU-bound work:**

Tasks performing long-running CPU operations without intermixed I/O should cooperatively yield at regular intervals:

```rust
async fn process_items(zip_file: File) {
    let items = zip_file.read().await;
    for item in items {
        decompress(item); // CPU-bound work
        tokio::task::yield_now().await; // Explicit yield point
    }
}
```

**Yield point frequency guideline:**

In thread-per-core runtime models, balance task switching overhead against systemic effects of starving unrelated tasks.
Assuming runtime task switching takes hundreds of nanoseconds plus CPU cache overhead, continuous execution between yields should be long enough that switching cost becomes negligible (less than 1% overhead).

**Recommended yield interval:** Perform 10-100 microseconds of CPU-bound work between yield points.

**Dynamic yielding with runtime budget:**

For operations with unpredictable number and duration, query the hosting runtime using APIs like `has_budget_remaining()`:

```rust
async fn process_variable_workload(items: Vec<Item>) {
    for item in items {
        process_item(item);

        // Yield only when runtime budget is exhausted
        if !tokio::task::coop::has_budget_remaining() {
            tokio::task::yield_now().await;
        }
    }
}
```

### Memory efficiency and allocation strategies

**Prefer borrowing over ownership:**

- Use `&str` over `String` when ownership is not needed
- Consider `Cow<str>` for conditional ownership (borrows when possible, clones when necessary)
- Pass slices `&[T]` instead of `Vec<T>` when function does not need ownership
- Use `AsRef<T>` and `Borrow<T>` traits to accept both owned and borrowed forms

**Pre-allocate when size is known:**

- Use `Vec::with_capacity(n)` when final size is known or estimable
- Use `HashMap::with_capacity(n)` and `HashSet::with_capacity(n)` to avoid rehashing during growth
- Consider `String::with_capacity(n)` for string building in loops

**Avoid unnecessary allocations:**

- Reuse buffers across loop iterations instead of allocating per iteration
- Use `clear()` to reset collections while preserving allocated capacity
- Consider arena allocators or bump allocation for short-lived allocations in hot paths
- Profile allocations using `cargo flamegraph` with allocation profiling or tools like `heaptrack`

**Zero-cost abstractions:**

- Prefer iterator chains over explicit loops (compiler optimizes them equivalently)
- Use generics and monomorphization for performance-critical code (generates specialized code)
- Leverage const generics and const evaluation to move computation to compile time where applicable
- Avoid trait objects (`dyn Trait`) in hot paths when static dispatch (generics) is possible

### Allocator considerations

**Use mimalloc for applications:**

Applications should set [mimalloc](https://crates.io/crates/mimalloc) as their global allocator for significant performance gains without code changes.
This frequently results in notable performance increases along allocating hot paths, with benchmark improvements up to 25% observed.

**Setting mimalloc as global allocator:**

Add mimalloc to `Cargo.toml`:

```toml
[dependencies]
mimalloc = "0.1"
```

Configure global allocator in application entry point (typically `main.rs`):

```rust
use mimalloc::MiMalloc;

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

fn main() {
    // Application code runs with mimalloc
}
```

**When to consider custom allocators:**

- Libraries should not set global allocators (leave choice to applications)
- Consider custom allocators for specialized workload patterns (arena allocation for tree structures, bump allocation for temporary allocations, pool allocation for fixed-size objects)
- Profile allocation patterns before implementing custom allocators to ensure complexity is justified
- Document allocator assumptions in crate documentation if allocation behavior is performance-critical

### Benchmarking and measurement

**Establish benchmark suite:**

- Use `criterion` crate for statistically rigorous benchmarks with regression detection
- Use `divan` crate for faster compile times and simpler benchmark definitions
- Benchmark hot paths identified during profiling and design phases
- Include both microbenchmarks (isolated functions) and macrobenchmarks (end-to-end workflows)

**Criterion benchmark example:**

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn fibonacci(n: u64) -> u64 {
    match n {
        0 => 1,
        1 => 1,
        n => fibonacci(n-1) + fibonacci(n-2),
    }
}

fn criterion_benchmark(c: &mut Criterion) {
    c.bench_function("fib 20", |b| b.iter(|| fibonacci(black_box(20))));
}

criterion_group!(benches, criterion_benchmark);
criterion_main!(benches);
```

**Divan benchmark example:**

```rust
use divan::Bencher;

#[divan::bench]
fn parse_date(bencher: Bencher) {
    bencher.bench_local(|| {
        parse_date_impl("2024-01-15")
    });
}
```

**Benchmark best practices:**

- Use `black_box()` to prevent compiler from optimizing away benchmarked code
- Run benchmarks on dedicated hardware or in controlled environments (disable CPU frequency scaling, close background applications)
- Measure allocations, not just wall-clock time, to understand memory overhead
- Compare against baseline implementations to quantify optimization impact
- Add benchmarks to CI to detect regressions automatically

### Performance documentation

**Document performance characteristics:**

- Add performance notes to public API documentation explaining expected complexity (O(n), O(log n), etc.)
- Document allocation behavior (whether functions allocate, how much, under what conditions)
- Explain trade-offs made between performance and other concerns (correctness, maintainability, API ergonomics)
- Provide guidance on performance-sensitive usage patterns

**Example performance documentation:**

```rust
/// Processes items in batches for optimal throughput.
///
/// # Performance
///
/// - Time complexity: O(n) where n is the number of items
/// - Memory: Allocates a single buffer of size `batch_size` reused across batches
/// - Throughput: Optimized for batches of 100-1000 items
/// - Yields every 50μs to prevent starving other async tasks
///
/// For latency-sensitive workloads, consider using `process_items_streaming`
/// which processes items individually with lower batching overhead.
pub async fn process_items_batched(items: &[Item], batch_size: usize) -> Result<Vec<Output>> {
    // Implementation
}
```
