## Tooling

### Code quality and linting

Address all `clippy` warnings before committing - run `cargo clippy --all-targets --all-features`.

Use `cargo fmt` to format code according to Rust style guidelines.

Enable additional clippy lint groups: `#![warn(clippy::all, clippy::pedantic)]`.

Consider stricter lints for critical code: `clippy::unwrap_used`, `clippy::expect_used`.

Run `cargo check` frequently during development for fast feedback.

### Dependencies

Minimize dependencies and audit them regularly with `cargo audit`.

Prefer well-maintained crates with strong type safety.

Use `cargo tree` to understand dependency graphs.

Pin versions appropriately in Cargo.toml.

Keep dependencies updated but test thoroughly after updates.
