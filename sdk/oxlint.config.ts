import { defineConfig } from "oxlint";

export default defineConfig({
  ignorePatterns: ["node_modules", "dist"],
  options: {
    typeAware: true,
  },
  categories: {
    correctness: "error",
    suspicious: "warn",
    pedantic: "off",
  },
  rules: {
    "no-useless-concat": "off",
    "no-inline-comments": "off",
  },
});
