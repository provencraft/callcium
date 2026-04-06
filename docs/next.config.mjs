import { createMDX } from "fumadocs-mdx/next";
import { resolve } from "node:path";

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const config = {
  output: "export",
  reactStrictMode: true,
  transpilePackages: ["shiki"],
  turbopack: {
    root: resolve(import.meta.dirname, ".."),
  },
};

export default withMDX(config);
