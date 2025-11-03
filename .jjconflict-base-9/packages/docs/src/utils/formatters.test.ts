import { describe, expect, it } from "vitest";
import { capitalizeFirst, toKebabCase, truncate } from "./formatters";

describe("formatters", () => {
  describe("capitalizeFirst", () => {
    it("capitalizes the first letter of a lowercase string", () => {
      expect(capitalizeFirst("hello")).toBe("Hello");
    });

    it("handles already capitalized strings", () => {
      expect(capitalizeFirst("Hello")).toBe("Hello");
    });

    it("handles empty strings", () => {
      expect(capitalizeFirst("")).toBe("");
    });

    it("handles single character strings", () => {
      expect(capitalizeFirst("a")).toBe("A");
    });
  });

  describe("toKebabCase", () => {
    it("converts camelCase to kebab-case", () => {
      expect(toKebabCase("camelCase")).toBe("camel-case");
    });

    it("converts PascalCase to kebab-case", () => {
      expect(toKebabCase("PascalCase")).toBe("pascal-case");
    });

    it("converts spaces to hyphens", () => {
      expect(toKebabCase("hello world")).toBe("hello-world");
    });

    it("converts underscores to hyphens", () => {
      expect(toKebabCase("hello_world")).toBe("hello-world");
    });

    it("handles mixed formats", () => {
      expect(toKebabCase("HelloWorld_FooBar")).toBe("hello-world-foo-bar");
    });

    it("handles already kebab-case strings", () => {
      expect(toKebabCase("already-kebab")).toBe("already-kebab");
    });
  });

  describe("truncate", () => {
    it("truncates strings longer than maxLength", () => {
      expect(truncate("This is a long string", 10)).toBe("This is...");
    });

    it("does not truncate strings shorter than maxLength", () => {
      expect(truncate("Short", 10)).toBe("Short");
    });

    it("handles strings exactly at maxLength", () => {
      expect(truncate("Exactly 10", 10)).toBe("Exactly 10");
    });

    it("handles very short maxLength", () => {
      expect(truncate("Hello World", 5)).toBe("He...");
    });

    it("handles empty strings", () => {
      expect(truncate("", 10)).toBe("");
    });
  });
});
