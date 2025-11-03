/**
 * Shared test fixtures for component testing
 */

export const mockCardProps = {
  default: {
    title: "Test Card",
  },
  withLink: {
    title: "Link Card",
    href: "https://example.com",
  },
  featured: {
    title: "Featured Card",
    variant: "featured" as const,
  },
};

export const mockSlotContent = {
  simple: "This is simple content",
  html: "<p>This is <strong>HTML</strong> content</p>",
  empty: "",
};
