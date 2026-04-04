import { defineConfig } from "oxlint";

export default defineConfig({
  ignorePatterns: [
    "node_modules",
    ".next",
    ".source",
    "content/docs/reference",
    "content/docs/specifications",
    "components/ui",
  ],
  options: {
    typeAware: true,
  },
  plugins: [
    // Defaults (must re-list since setting plugins overwrites them).
    "eslint",
    "typescript",
    "unicorn",
    "oxc",
    // Non-defaults needed for a Next.js/React docs site.
    "react",
    "nextjs",
    "jsx-a11y",
  ],
  categories: {
    correctness: "error",
    suspicious: "error",
    pedantic: "off",
  },
  rules: {
    "react/no-array-index-key": "error",
    "react/react-in-jsx-scope": "off",
    "typescript/no-unsafe-type-assertion": "off",
  },
});
