import { defineConfig } from "oxfmt";

export default defineConfig({
  ignorePatterns: ["node_modules", "dist"],
  printWidth: 120,
  sortImports: {
    groups: [
      ["value-builtin", "value-external"],
      "type-external",
      ["value-parent", "value-sibling", "value-index"],
      ["type-parent", "type-sibling", "type-index"],
      "unknown",
    ],
  },
});
