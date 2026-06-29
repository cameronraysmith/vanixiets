---
name: preferences-haskell-development
description: Haskell development conventions covering type classes, monadic composition, and GHC extensions. Load when working with .hs files or Haskell projects.
---

# Haskell Development

## Architectural patterns alignment

See preferences-architectural-patterns for overarching principles.

Haskell offers exceptionally direct support for lawful abstractions, referential transparency, and effect composition, including monad transformers as one well-supported way to discharge a capability interface.
It serves as a reference model for lawful, type-tracked effect composition that other languages approximate with their respective libraries (Effect-TS, ZIO, etc.).
The capability interface (the effect signature) is the stable primitive; a transformer stack is one interpreter of it, never the interface or the integration ideal itself.
See preferences-theoretical-foundations, and in particular its effects-and-handlers material, for why a capability interface discharged by handlers, not a transformer tower, is the primitive.

### Core patterns and libraries
- **Effect composition**: Use monad transformers from `transformers` and `mtl` for composing effects
- **Error handling**: `Either` and `Maybe` for composable error handling, no exceptions
- **State management**: `StateT` for explicit state threading through computations
- **Reader pattern**: `ReaderT` for dependency injection and configuration
- **IO isolation**: Isolate IO effects to boundaries, keep pure functions pure
- **Type-level programming**: Leverage type classes, GADTs, and type families for compile-time guarantees

### Monad transformer stacks

A transformer stack is one interpreter of a capability interface, and a leaky one: the layers do not commute, and deep `lift` chains cost more as the stack grows.
Keep any stack shallow and hidden behind a newtype or type alias, and treat the mtl capability constraint (`MonadReader`, `MonadState`, `MonadError`) as the stable primitive rather than the carrier.

- Structure applications behind mtl capability constraints, with a transformer stack such as `ReaderT Config (StateT AppState (ExceptT Error IO))` as one interpreter of those capabilities; see preferences-theoretical-foundations for why the capability interface, not the stack, is the primitive
- Ensure all monad instances are lawful (identity, associativity for bind)
- Use `lift` and `liftIO` to traverse effect transformer stacks
- Apply newtype wrappers for domain-specific effect stacks

### Type safety and purity
- Leverage Haskell's type system to make illegal states unrepresentable
- Use `newtype` for domain-specific types to prevent mixing incompatible values
- Encode effects explicitly in type signatures (IO, State, Reader, etc.)
- Prefer total functions; use `Maybe`/`Either` instead of partial functions
- Use smart constructors to enforce invariants at construction time

### Recommended libraries
- **Monad transformers**: `transformers`, `mtl`
- **Effect systems**: `polysemy`, `eff`, `freer-simple` for more flexible effect composition
- **Parsing**: `megaparsec`, `attoparsec` for parser combinators
- **Error handling**: `either`, `validation`, `errors` for enhanced error composition
- **Testing**: `QuickCheck` for property-based testing, `hspec` for BDD-style tests
- **Lenses**: `lens` or `optics` for functional record updates

## Code quality and tooling
- Use `hlint` for linting and style suggestions
- Use `ormolu`, `fourmolu`, or `stylish-haskell` for consistent formatting
- Enable `-Wall` and `-Wcompat` for comprehensive warnings
- Use `ghcid` for fast feedback during development
- Run `stack test` or `cabal test` before committing

## Project structure
- Use Stack or Cabal for package management
- Organize code into modules with clear public APIs
- Separate pure business logic from IO-heavy code
- Use `src/` for library code, `app/` for executables, `test/` for tests
- Document public functions with Haddock comments

## Best practices
- Write point-free style judiciously (when it improves clarity)
- Use pattern matching exhaustively
- Leverage lazy evaluation but be aware of space leaks
- Profile with `-prof` and `+RTS` flags before optimizing
- Use strict fields in data types when appropriate (`!` bang patterns)
- Consider strictness annotations for performance-critical code
