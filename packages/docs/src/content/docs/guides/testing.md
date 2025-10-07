---
title: Testing guide
description: Comprehensive testing with Vitest and Playwright
---

Comprehensive testing documentation for the typescript-nix-template project.

## Overview

This project uses a robust testing stack with type-safe patterns and functional programming principles:

- **Vitest 3.x**: Fast unit and component testing with Astro integration
- **Playwright**: Multi-browser E2E testing with type-safe APIs
- **Astro Container API**: Component rendering and testing
- **Nix**: Reproducible test environments with browser binaries

## Quick Start

```bash
# Enter nix development environment (manages all dependencies)
nix develop

# Install npm dependencies
bun install

# Run all tests
just test

# Run tests in watch mode
just test-watch

# Run E2E tests with UI
just test-ui

# Generate coverage report
just test-coverage
```

## Test structure

```
packages/docs/
├── src/
│   ├── components/
│   │   ├── Card.astro
│   │   └── Card.test.ts          # Component tests (co-located)
│   └── utils/
│       ├── formatters.ts
│       └── formatters.test.ts    # Unit tests (co-located)
├── e2e/
│   └── homepage.spec.ts          # E2E tests
├── tests/
│   ├── fixtures/                 # Shared test data
│   │   ├── components.ts
│   │   └── README.md
│   └── types/                    # Test type definitions
│       ├── test-helpers.ts
│       └── README.md
├── vitest.config.ts              # Vitest configuration
├── playwright.config.ts          # Playwright configuration
└── coverage/                     # Coverage reports (generated)
```

## Unit Testing with Vitest

### Writing Unit Tests

Unit tests use Vitest's global API and are co-located with source files:

```typescript
// src/utils/formatters.test.ts
import { describe, expect, it } from "vitest";
import { capitalizeFirst } from "./formatters";

describe("capitalizeFirst", () => {
  it("capitalizes the first letter", () => {
    expect(capitalizeFirst("hello")).toBe("Hello");
  });

  it("handles empty strings", () => {
    expect(capitalizeFirst("")).toBe("");
  });
});
```

### Running Unit Tests

```bash
# Run all unit tests
just test-unit

# Watch mode for development
just test-watch

# With coverage
just test-coverage
```

### Test Patterns

Follow these patterns for unit tests:

- **Pure functions**: Test inputs and outputs without side effects
- **Type safety**: No `any` types, leverage TypeScript inference
- **Descriptive names**: Use `describe` blocks for organization
- **Edge cases**: Test empty, null, and boundary conditions
- **Co-location**: Place tests next to source files

## Component Testing with Astro Container API

### Writing Component Tests

Use the Astro Container API to test Astro components:

```typescript
// src/components/Card.test.ts
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, expect, it } from "vitest";
import Card from "./Card.astro";

describe("Card component", () => {
  it("renders with props and slots", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Card, {
      props: { title: "Test Card" },
      slots: { default: "Content" },
    });

    expect(result).toContain("Test Card");
    expect(result).toContain("Content");
  });
});
```

### Container API Methods

- `AstroContainer.create()`: Create container instance
- `container.renderToString(Component, options)`: Render to HTML string
- `container.renderToResponse(Component, options)`: Render to Response object

### Component Test Patterns

- **Props validation**: Test all prop variations
- **Slot rendering**: Verify slot content appears correctly
- **Conditional rendering**: Test dynamic element rendering
- **Class application**: Verify CSS class logic
- **Type safety**: Use proper prop types from component

## E2E Testing with Playwright

### Writing E2E Tests

E2E tests use Playwright's test runner and live in the `e2e/` directory:

```typescript
// e2e/homepage.spec.ts
import { expect, test } from "@playwright/test";

test.describe("Homepage", () => {
  test("has correct title", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle(/My Docs/);
  });

  test("navigates to guide", async ({ page }) => {
    await page.goto("/");
    const link = page.getByRole("link", { name: /example guide/i });
    await link.click();
    await expect(page).toHaveURL(/\/guides\/example/);
  });
});
```

### Running E2E Tests

```bash
# Run E2E tests
just test-e2e

# Run with UI (interactive mode)
just test-ui

# Run specific test file
bun run test:e2e e2e/homepage.spec.ts

# Run in specific browser
bun run test:e2e --project=firefox
```

### E2E Test Patterns

- **Page objects**: Use locators for maintainability
- **Accessibility**: Use `getByRole` for semantic selectors
- **Assertions**: Use Playwright's async assertions
- **Multi-browser**: Tests run in Chromium, Firefox, WebKit
- **Visual regression**: Use screenshots for visual testing

## Test Configuration

### Vitest Configuration

Key configuration in `vitest.config.ts`:

- **Environment**: `node` for SSR component testing
- **Globals**: `true` for auto-imported test APIs
- **Coverage**: v8 provider with text, JSON, HTML, LCOV reporters
- **Include**: `src/**/*.{test,spec}.{ts,tsx}`, `tests/**/*.{test,spec}.{ts,tsx}`
- **Exclude**: `node_modules`, `dist`, `.astro`, `e2e`

### Playwright Configuration

Key configuration in `playwright.config.ts`:

- **Test directory**: `./e2e`
- **Browsers**: Chromium, Firefox, WebKit
- **Workers**: 1 in CI, unlimited locally
- **Retries**: 2 in CI, 0 locally
- **Base URL**: `http://localhost:4321`
- **Web server**: Starts Astro preview automatically

### Nix Integration

Playwright browsers are managed by Nix for reproducibility:

```nix
# nix/modules/devshell.nix
packages = [ playwright-driver.browsers ];

shellHook = ''
  export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
  export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
'';
```

## CI/CD Integration

Tests run automatically in GitHub Actions on pull requests and pushes to main.

### CI Test Job

The test job runs after `nixci` and before `build`:

1. Install Nix and dependencies
2. Run unit tests with Vitest
3. Install Playwright browsers
4. Build site for E2E testing
5. Run E2E tests across all browsers
6. Upload test results and coverage artifacts

### Viewing CI Results

```bash
# Check workflow status
just gh-workflow-status

# View logs for latest run
just gh-logs

# Download test artifacts from GitHub
gh run download
```

## Writing New Tests

### Unit Test Checklist

- [ ] Create test file next to source file (e.g., `foo.test.ts` next to `foo.ts`)
- [ ] Use `describe` blocks to organize related tests
- [ ] Test happy path and edge cases
- [ ] Use type-safe assertions
- [ ] Avoid `any` types
- [ ] Run tests in watch mode during development

### Component Test Checklist

- [ ] Create test file next to component (e.g., `Card.test.ts` next to `Card.astro`)
- [ ] Create container with `AstroContainer.create()`
- [ ] Test all prop variations
- [ ] Test slot content rendering
- [ ] Verify conditional rendering logic
- [ ] Check CSS class application

### E2E Test Checklist

- [ ] Create test file in `e2e/` directory
- [ ] Use `test.describe` for grouping
- [ ] Use accessible selectors (`getByRole`, `getByLabel`)
- [ ] Test user workflows, not implementation details
- [ ] Add assertions for page state changes
- [ ] Consider responsive design (mobile viewports)

## Troubleshooting

### Vitest Issues

**Tests not found**
- Check file patterns in `vitest.config.ts`
- Ensure test files match `*.test.ts` or `*.spec.ts`
- Verify files are not in exclude list

**Import errors**
- Check TypeScript configuration
- Ensure dependencies are installed with `bun install`
- Verify Astro integration with `getViteConfig()`

### Playwright Issues

**Browsers not installed**
```bash
just playwright-install
# or
bunx playwright install --with-deps
```

**Port already in use**
- Stop other development servers on port 4321
- Or change `baseURL` in `playwright.config.ts`

**Nix environment issues**
```bash
# Rebuild nix shell
nix develop --rebuild

# Verify environment variables
echo $PLAYWRIGHT_BROWSERS_PATH
```

### Coverage Issues

**Low coverage warnings**
- Add tests for uncovered files
- Check coverage thresholds in `vitest.config.ts`
- Review coverage report in `coverage/index.html`

**Coverage not generated**
```bash
# Ensure coverage dependency is installed
bun install @vitest/coverage-v8

# Run with coverage flag
just test-coverage
```

## Best Practices

### Type Safety

- **No `any` types**: Use proper TypeScript types everywhere
- **Strict mode**: Project uses Astro's strict tsconfig
- **Type imports**: Import types explicitly when needed

### Functional Patterns

- **Pure functions**: Test functions without side effects
- **Immutable data**: Use const and readonly where appropriate
- **Composition**: Build complex tests from simple, reusable pieces

### Test Organization

- **Co-location**: Keep tests near source code
- **Fixtures**: Share test data in `tests/fixtures/`
- **Types**: Define test types in `tests/types/`
- **DRY**: Extract common patterns to shared utilities

### Performance

- **Parallel execution**: Tests run in parallel by default
- **Watch mode**: Use for rapid feedback during development
- **CI optimization**: Tests run with retries and proper workers in CI

## Resources

- [Vitest Documentation](https://vitest.dev/)
- [Playwright Documentation](https://playwright.dev/)
- [Astro Testing Guide](https://docs.astro.build/en/guides/testing/)
- [Astro Container API Reference](https://docs.astro.build/en/reference/container-reference/)
