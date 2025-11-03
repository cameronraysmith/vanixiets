---
title: "ADR-0010: Testing architecture"
---

## Status

Accepted

## Context

Testing TypeScript applications requires choosing:

**Unit/Component testing:**
- **Jest** - most popular, slower, comprehensive mocking
- **Vitest** - fast, Vite-native, Jest-compatible API
- **Node test runner** - built-in, minimal features
- **Mocha/Chai** - classic, more setup needed

**E2E testing:**
- **Playwright** - modern, multi-browser, fast
- **Cypress** - popular, single-browser (Chromium) by default
- **Selenium** - classic, verbose API

**Test location strategy:**
- Co-located tests (next to source)
- Separate test directories
- Mixed approach

## Decision

Use **Vitest** for unit/component tests and **Playwright** for E2E tests with **co-located test files**.

## Implementation

**Unit and component testing: Vitest**
- Fast test execution
- Astro Container API for component testing
- Built-in coverage reporting

**E2E testing: Playwright**
- Multi-browser testing (Chromium, Firefox, WebKit)
- Type-safe APIs
- Managed by Nix for reproducibility

**Test co-location:**
- Unit tests next to source files: `foo.test.ts` next to `foo.ts`
- Component tests next to components: `Card.test.ts` next to `Card.astro`
- E2E tests in separate `e2e/` directory

## Rationale

### Vitest choice
- **Fast test execution** - significantly faster than Jest
- **Vite-native** - works seamlessly with Astro's Vite-based build
- **Excellent TypeScript support** - no additional configuration needed
- **Jest-compatible API** - familiar for developers coming from Jest
- **Built-in coverage** - no additional tooling needed

### Playwright choice
- **Reliable cross-browser testing** - Chromium, Firefox, WebKit
- **Modern async API** - better than Selenium
- **Type-safe** - TypeScript first-class support
- **Nix-managed browsers** - consistent versions across environments
- **Parallel execution** - faster test runs

### Co-location choice
- **Easy to find** - test next to implementation
- **Easy to maintain** - when you change code, test is right there
- **Encourages testing** - less friction to add tests
- **Clear test coverage** - immediately see which files lack tests

## Trade-offs

**Positive:**
- Fast feedback loops (Vitest)
- Reliable cross-browser testing (Playwright)
- Easy to navigate (co-location)
- Type-safe throughout
- Nix ensures consistent Playwright browser versions

**Negative:**
- Vitest is newer (less ecosystem than Jest)
- Co-located tests increase file count in src/
- E2E tests are slower than unit tests (by nature)

**Neutral:**
- Separate `e2e/` directory for E2E tests (not co-located)
- Need to manage Playwright browsers via Nix

## Consequences

See [Testing](/about/contributing/testing/) for comprehensive implementation documentation.

**Development workflow:**
```bash
bun test              # Run unit tests
bun test:e2e          # Run E2E tests
bun test:coverage     # Generate coverage report
```

**CI workflow:**
- Unit tests run on all commits
- E2E tests run on all commits
- Coverage reports uploaded to artifacts
