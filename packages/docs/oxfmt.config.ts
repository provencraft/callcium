import { defineConfig } from "oxfmt";

export default defineConfig({
  ignorePatterns: ["node_modules", ".next", ".source", "content/docs", "components/ui"],
  printWidth: 120,
  sortImports: {
    newlinesBetween: false,
    groups: [
      ["value-builtin", "value-external"],
      "type-external",
      ["value-parent", "value-sibling", "value-index"],
      ["type-parent", "type-sibling", "type-index"],
      "unknown",
    ],
  },
});
