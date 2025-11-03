import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, expect, it } from "vitest";
import Card from "./Card.astro";

describe("Card component", () => {
  it("renders with title and slot content", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Card, {
      props: { title: "Test Card" },
      slots: {
        default: "This is card content",
      },
    });

    expect(result).toContain("Test Card");
    expect(result).toContain("This is card content");
    expect(result).toContain("card__title");
    expect(result).toContain("card__content");
  });

  it("renders as link when href is provided", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Card, {
      props: {
        title: "Link Card",
        href: "https://example.com",
      },
      slots: {
        default: "Click me",
      },
    });

    expect(result).toContain("<a");
    expect(result).toContain('href="https://example.com"');
    expect(result).toContain("card--link");
  });

  it("renders as div when href is not provided", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Card, {
      props: { title: "Static Card" },
      slots: {
        default: "Content",
      },
    });

    expect(result).toContain("<div");
    expect(result).not.toContain("card--link");
  });

  it("applies featured variant class", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Card, {
      props: {
        title: "Featured Card",
        variant: "featured",
      },
      slots: {
        default: "Important content",
      },
    });

    expect(result).toContain("card--featured");
  });

  it("applies default variant when not specified", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Card, {
      props: { title: "Default Card" },
      slots: {
        default: "Normal content",
      },
    });

    expect(result).not.toContain("card--featured");
  });
});
