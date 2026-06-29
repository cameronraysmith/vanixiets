# Refine and lower: the forward Lean → Rust step

This file covers the forward step of the pipeline: refining a Lean 4 specification down to Rust source.
In the pipeline Lean 4 ⟶ Rust ⟶ LLBC ⟶ Lean 4, this is the first arrow, written *refine/lower*.
It is the one step with no command-line generator: a human authors the Rust, manually and with LLM assistance, choosing constructs from a deliberately narrow subset so that the later lift (Charon then Aeneas) reproduces a clean functional model in Lean.
The discipline here is entirely about *staying inside that subset*, because the lift only succeeds for the safe Rust fragment Aeneas models.

## Contents

- [No generator: this is human authoring](#no-generator-this-is-human-authoring)
- [The Aeneas/Charon-safe Rust subset](#the-aeneascharon-safe-rust-subset)
- [Ownership intent as the multiplicity encoding](#ownership-intent-as-the-multiplicity-encoding)
- [Do and don't snippets](#do-and-dont-snippets)
- [Is this Rust liftable? a checklist](#is-this-rust-liftable-a-checklist)

## No generator: this is human authoring

There is no `lean2rust` tool, and this skill never implies one exists.
The forward arrow is hand-written Rust, produced by a person reading the Lean spec and translating its data shapes and operations into the safe subset described below.
LLM assistance is appropriate and expected here — proposing the Rust shape of a Lean inductive, suggesting the ownership mode for a parameter, drafting the loop body — but the author owns the result and is responsible for keeping it inside the subset.

The one-CLI-call-per-step framing of the methodology applies to the *later* steps (Charon, Aeneas, and the check), each of which is a single tool invocation.
The forward step is the human-judgment boundary: write the Lean spec, `lake build` it to confirm it elaborates, then hand-author Rust under the constraints here.
Errors caught at this stage — choosing a construct that does not lift — are cheaper than discovering the same problem after a failed Charon or Aeneas run, so the subset rules below are best treated as authoring-time constraints rather than post-hoc filters.

## The Aeneas/Charon-safe Rust subset

Aeneas functionalizes a subset of *safe* Rust (`~/projects/functional-programming-workspace/aeneas`, `README.md:121-139`).
The soundness premise is Rust's borrow checker: because `&mut T` guarantees exclusive access, a mutable borrow can be modeled purely as "take a value in, return the (possibly modified) value out."
Anything that breaks that exclusive-aliasing guarantee falls outside the model.
That single principle explains every inclusion and exclusion that follows.

What lifts cleanly, grounded in the actual Lean standard-library models under `aeneas/backends/lean/Aeneas/Std/`:

Owned values, shared borrows `&T`, and exclusive borrows `&mut T` (including `&mut` in return position) are the core supported cases.
The forward/backward decomposition exists precisely to model `&mut`, so it is not merely tolerated but central — `choose<'a, T>(b, &'a mut T, &'a mut T) -> &'a mut T` and `list_nth_mut` are canonical (`aeneas/tests/src/tutorial/src/lib.rs:1,50`).

Structs, enums (including generic and recursive enums), tuples, and pattern matching (`match`, `if let`, `while let`) all lift to clean Lean inductives and case splits (`tutorial/src/lib.rs:30-33,36,66,124,148`).
Recursion lifts to recursive Lean definitions carrying termination obligations (`lib.rs:35-48`).

Generics with trait bounds are supported: type parameters, `impl Trait for ...`, and `&mut self` methods all lift (`tutorial/src/lib.rs:105-120`), and the richer trait shapes — associated types, supertraits, and default methods — are handled by the trait machinery on the Aeneas Lean backend path (`aeneas/backends/lean/Aeneas/Std/Core/Ops.lean`).
Monomorphizable static dispatch is the safe default for polymorphism.

`Box<T>` is the only smart pointer with a model, and it is modeled as the identity / unique pointer — `Box<T> ≅ T`, with `Box::deref x = x` and `Box::deref_mut x = (x, λ x => x)` (`Std/Alloc.lean:19-23`).
It is the sanctioned indirection for recursive types, e.g. `Cons(T, Box<List<T>>)`.

`Vec<T>` is modeled as a length-refined list, `{ l : List α // l.length ≤ Usize.max }` (`Std/Vec.lean:21-22`), with `new`, `len`, `push`, `insert`, `index_usize`, `index_mut_usize`, and `update` (`Vec.lean:46,53,120,135,148,179,161`).
`push` returns a `Result` because it can fail on capacity.
Fixed-size arrays `[T; N]` (`Std/Array.lean`) and slices `&[T]` / `&mut [T]` (`Std/Slice.lean`, including the `&mut`-paired `get_mut` at `Slice.lean:371`) are modeled.

Integer types `u8..u128`, `i8..i128`, `usize`, `isize` are modeled with arithmetic that returns `Result`: overflow, out-of-bounds indexing, and division by zero short-circuit to a failure value (`Std/Scalar.lean` and the `Std/Scalar/` tree).
`panic!` and `assert!` likewise produce a failure, which becomes a "never panics" proof obligation downstream.
Single-level loops (`while`, `loop`, `for` over a range) lift, each translated to an auxiliary recursive loop function.
Immutable `const` and `static` are items that lift; `static mut` is not in the safe subset.

What does *not* lift — no model, stubbed to failure, or explicitly rejected:

Interior mutability is the headline exclusion.
`Cell`, `RefCell`, `Mutex`, `RwLock`, and `UnsafeCell` have no model anywhere in `Std`; a sweep for them returns nothing.
They bypass the borrow checker's exclusivity, which is the soundness premise of the whole lift, and there is no `&mut`-as-value model for shared-mutable state until separation-logic support lands.
`Rc<T>` and `Arc<T>` are likewise absent from the Lean `Std` and from `aeneas/src/` — shared ownership is outside the model, and `Box` (unique) is the only smart pointer modeled.
(Absence for the Lean target is certain; the dossier flags as uncertain whether some other backend stubs `Rc`/`Arc`.)

`unsafe` code makes the item opaque rather than translating it (`README.md:135`).
Raw pointers `*const T` / `*mut T` are stubbed: `RawPtr` carries the comment "We don't really use raw pointers for now" and its cast fails (`Std/RawPtr.lean:8,28`).
Atomics exist only as opaque type placeholders with no operations (`Std/Core/Atomic.lean:5-11`); threads, channels, and any concurrency have no models; `async`/`await` and `Future` are absent.
Standard collections `HashMap` and `BTreeMap` have no built-in lift — use a `Vec` of pairs or a verified map of your own.

Loops have a precise, code-asserted limit: control transfer to an *outer* loop is unsupported.
The normalization pass hard-asserts against early returns inside loops, breaks to outer loops, continues to outer loops, and returns inside nested loops (`aeneas/src/PrePasses.ml:587,603,648,652,659`).
A single early return or break out of a *single* loop can be hoisted, but transfers targeting an enclosing loop cannot.

Several features are partial or fragile rather than cleanly unsupported.
Trait objects `dyn Trait` are exercised in Charon but the `dyn` test is skipped for the Lean backend (`aeneas/tests/src/dyn.rs:1`, header `//@ [!lean] skip`), so treat `dyn` as fragile for Lean and prefer enum dispatch.
Closures with mutable capture have machinery (`FnMut.call_mut` returns updated state, `Std/Core/Ops.lean:54`) but complex captures fail in practice.
Iterator combinators (`map`, `filter`, `fold`, `collect`) generally do not lift, involving closures plus adapter traits.
`String` is modeled as opaque with no operations (`Std/Alloc.lean:11`); prefer `Vec<u8>`.
The `vec![...]` macro does not lift — it triggers a `shallow-init-box` translation error — so use `Vec::new()` plus `push`.
This `vec![...]` failure rests on empirical evidence (the practitioner corpus `STATUS.md:45`, `GAP_ANALYSIS.md:82`); the dossier could not locate the literal emitter string in the checked-out Charon tree, so the exact handling location is uncertain even though the failure is reliably reported.

## Ownership intent as the multiplicity encoding

A dependently typed source expresses resource usage via multiplicities or linearity — use-exactly-once, use-zero, unrestricted.
Rust has no first-class multiplicity annotation, but its ownership modes are the operational encoding of the same information, and they are exactly the signal Aeneas reads to decide the shape of the lifted function.
This makes ownership intent the practical substitute for the QTT-style linear multiplicities a Lean/QTT-flavored spec might carry.

An owned `T` parameter corresponds to a linear, consumed value: it is moved in, the model takes a plain value, and there is no backward function.
Use it for consume-and-transform operations.
A shared borrow `&T` corresponds to unrestricted read-only use: the model takes a value and returns no update for that argument — forward only.
An exclusive borrow `&mut T` corresponds to a linear borrow-and-return: the model takes a value and *additionally* returns the updated value via a backward function (or as a tuple component).
This is the entire point of the forward/backward decomposition, and multiple `&mut` regions produce multiple backward functions.

So the forward rule is: choose the ownership mode that matches the spec's multiplicity, and Aeneas reproduces the corresponding pure-functional shape.
A spec variable used affinely becomes an owned parameter; a read-only one becomes `&`; an in-place update becomes `&mut`.
The borrow checker then *enforces* that discipline statically, and the soundness of the lift depends on that enforcement — so the encoding is not advisory, it is what the lift relies on.

## Do and don't snippets

Recursive data uses `Box` indirection and lifts to a clean inductive:

```rust
enum CList<T> {
    CCons(T, Box<CList<T>>),
    CNil,
}
```

Express an in-place update as `&mut`, which becomes a backward function:

```rust
fn incr(x: &mut u32) {
    *x += 1;
}
```

Match the spec's multiplicity with the ownership mode — owned to consume, `&` to read, `&mut` to update in place:

```rust
fn reverse<T>(mut l: CList<T>) -> CList<T> { /* consumes l */ }
fn list_nth<T>(l: &CList<T>, i: u32) -> &T { /* reads l */ }
fn list_nth_mut<T>(l: &mut CList<T>, i: u32) -> &mut T { /* updates l in place */ }
```

Do not reach for interior mutability or shared ownership; thread state explicitly instead, which is exactly what the backward-function model reconstructs:

```rust
use std::cell::RefCell;
use std::rc::Rc;

struct Counter {
    count: Rc<RefCell<u32>>,
}
```

Do not build a `Vec` with the `vec![...]` macro — it triggers `shallow-init-box`.
This avoidance rests on empirical evidence from the practitioner corpus rather than a located emitter string, so treat it as a strong heuristic confirmed in practice:

```rust
let xs = vec![1u32, 2, 3];
```

Prefer constructing the `Vec` with `new` plus `push`:

```rust
let mut xs: Vec<u32> = Vec::new();
xs.push(1);
xs.push(2);
xs.push(3);
```

Do not chain iterator combinators; they generally do not lift:

```rust
let evens: Vec<u32> = xs.iter().copied().filter(|n| n % 2 == 0).collect();
```

Prefer an explicit single-level `while` loop with index access:

```rust
let mut evens: Vec<u32> = Vec::new();
let mut i: usize = 0;
while i < xs.len() {
    let n = xs[i];
    if n % 2 == 0 {
        evens.push(n);
    }
    i += 1;
}
```

Do not break to an outer loop; nested control transfer is hard-asserted against:

```rust
'outer: for i in 0..n {
    for j in 0..m {
        if found(i, j) {
            break 'outer;
        }
    }
}
```

Prefer a boolean flag in the loop condition so each loop stays single-level:

```rust
let mut done = false;
let mut i: usize = 0;
while i < n && !done {
    let mut j: usize = 0;
    while j < m && !done {
        if found(i, j) {
            done = true;
        }
        j += 1;
    }
    i += 1;
}
```

For polymorphism, prefer generics with trait bounds (monomorphizable static dispatch) over trait objects, which are fragile for the Lean backend:

```rust
fn use_counter<T: Counter>(cnt: &mut T) { /* lifts */ }
fn use_counter_dyn(cnt: &mut dyn Counter) { /* fragile for Lean: dyn test is [!lean] skip */ }
```

When a closed set of variants suffices, prefer a `match` over an enum to `dyn` dispatch; the enum produces a simpler, reliably lifting model.

Prefer total formulations so the downstream "never panics" obligations are dischargeable rather than merely present: bounds-check indices and pre-validate lengths, since indexing and arithmetic carry panic obligations through the `Result` model.

## Is this Rust liftable? a checklist

Before handing Rust to Charon, confirm each of the following.

No interior mutability: no `Cell`, `RefCell`, `Mutex`, `RwLock`, or `UnsafeCell` anywhere.
No shared-ownership smart pointers: no `Rc` or `Arc`; only `Box` for indirection.
No `unsafe`, no raw pointers, no atomics, no threads or channels, no `async`/`await`.
Recursive data goes through `Box`, and the resulting enums and structs are plain data.
Ownership modes match the spec's multiplicities: owned for consumed, `&` for read-only, `&mut` for in-place update.
No avoidable nested *mutable* borrows; prefer flat index access on a `Vec` or slice.
Loops are single-level with no control transfer (`return`, `break`, `continue`) to an outer loop; bail out via a boolean flag instead.
No iterator combinator chains; use explicit `while` loops with index access.
No `vec![...]` macro; build with `Vec::new()` plus `push`.
No `String` where `Vec<u8>` will do; standard `HashMap`/`BTreeMap` replaced by a `Vec` of pairs or a verified map.
Polymorphism via generics-with-bounds rather than `dyn Trait`; closed variants via enums rather than trait objects.
Arithmetic and indexing are written to be total where possible, so the panic obligations the lift attaches are provable.
Functions are kept small and first-order, which keeps the lifted Lean definitions small and their specs dischargeable.

Clearing this checklist does not guarantee a successful lift, but every item maps to a documented model presence, a stubbed-to-failure model, or a code-asserted limitation in Aeneas and Charon, so an item failing the checklist is a near-certain lift failure.
The empirical corpus failures cluster exactly on these patterns — generics monomorphization, `vec![]`, break-to-outer-loop, iterators, and nested borrows — which is the falsification signal that the subset boundary is drawn in the right place.
