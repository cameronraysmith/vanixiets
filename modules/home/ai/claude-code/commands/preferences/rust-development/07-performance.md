# Performance

## Hot path identification and profiling discipline

Identify hot paths through profiling before optimizing.

Use profiling tools:
- `cargo flamegraph` - generates flame graphs showing where time is spent
- `perf` (Linux) - detailed CPU profiling
- `Instruments` (macOS) - Apple's profiling tools
- `cargo bench` with criterion - statistical benchmarking

```bash
# Generate flame graph
cargo flamegraph --bin my_app

# Run with perf
perf record -g ./target/release/my_app
perf report
```

Only optimize code proven to be performance-critical through profiling.

## Throughput optimization for batch processing

For batch operations processing many items:

```rust
// Good: Process batch in single operation
pub fn process_batch(items: &[Item]) -> Vec<Result> {
    items.par_iter()  // Parallel iteration with rayon
        .map(|item| process_item(item))
        .collect()
}

// Avoid: Individual operations with repeated overhead
pub fn process_one(item: &Item) -> Result {
    // Each call pays setup/teardown cost
}
```

Use `rayon` for data parallelism when operations are independent.

## Async cooperative scheduling and yield points

Async functions must yield regularly to prevent blocking the executor.

```rust
use tokio::task::yield_now;

pub async fn process_large_dataset(data: &[Item]) -> Result<Summary, Error> {
    let mut results = Vec::new();

    for (i, item) in data.iter().enumerate() {
        results.push(process_item(item).await?);

        // Yield every 100 iterations to allow other tasks to run
        if i % 100 == 0 {
            yield_now().await;
        }
    }

    Ok(compute_summary(&results))
}
```

Without yield points, long-running async functions starve other tasks.

## Memory efficiency and allocation strategies

**Reuse allocations**:

```rust
// Good: Reuse buffer across iterations
let mut buffer = Vec::with_capacity(1024);
for item in items {
    buffer.clear();
    process_into_buffer(item, &mut buffer);
    use_buffer(&buffer);
}

// Avoid: Allocate on each iteration
for item in items {
    let buffer = Vec::new();  // New allocation every loop
    process_into_buffer(item, &mut buffer);
}
```

**Pre-allocate when size known**:

```rust
// Good: Pre-allocate with known capacity
let mut results = Vec::with_capacity(items.len());
for item in items {
    results.push(process(item));
}

// Avoid: Repeated reallocations as vector grows
let mut results = Vec::new();
for item in items {
    results.push(process(item));  // May reallocate multiple times
}
```

## Allocator considerations

Consider alternative allocators for specific workloads:

```rust
// Use jemalloc for multi-threaded applications with frequent allocations
#[global_allocator]
static GLOBAL: jemallocator::Jemalloc = jemallocator::Jemalloc;

// Or mimalloc for high-performance scenarios
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;
```

Profile before switching allocators - gains vary by workload.

## Benchmarking and measurement

Use `criterion` for statistical benchmarking:

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_process_data(c: &mut Criterion) {
    let data = create_test_data();

    c.bench_function("process_data", |b| {
        b.iter(|| {
            process_data(black_box(&data))
        })
    });
}

criterion_group!(benches, bench_process_data);
criterion_main!(benches);
```

Run benchmarks:

```bash
cargo bench
```

Criterion provides statistical analysis, outlier detection, and comparison across runs.

## Performance documentation

Document performance characteristics in function docs when relevant:

```rust
/// Processes observations in parallel using all available CPU cores.
///
/// # Performance
///
/// - Time complexity: O(n) where n is the number of observations
/// - Space complexity: O(n) for result storage
/// - Parallelism: Uses rayon thread pool, scales with core count
/// - Allocation: Pre-allocates result vector, no per-item allocation
///
/// For small datasets (< 100 items), use [`process_sequential`] to avoid
/// threading overhead.
pub fn process_parallel(observations: &[Observation]) -> Vec<Result> {
    // Implementation
}
```
