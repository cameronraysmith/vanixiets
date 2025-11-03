/**
 * Type definitions for test utilities and helpers
 */

/**
 * Generic test context type for shared test setup
 */
export interface TestContext<T = unknown> {
  data: T;
  cleanup: () => void | Promise<void>;
}

/**
 * Type for component render result
 */
export interface RenderResult {
  html: string;
  text: string;
  container: unknown;
}

/**
 * Type for async test utilities
 */
export type AsyncTestFn = () => Promise<void>;
