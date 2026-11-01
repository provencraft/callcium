import { createGetUrl } from "fumadocs-core/source";

export const SITE_NAME = "Callcium";
export const SITE_URL = "https://callcium.dev";
export const SITE_DESCRIPTION =
  "Callcium is a calldata policy engine for the EVM. It builds and enforces type-safe constraints on ABI-encoded calldata in Solidity or TypeScript.";

/** Open Graph fields for every page. A page's `openGraph` replaces its layout's whole object, so each page spreads these. */
export const OPEN_GRAPH = {
  siteName: SITE_NAME,
  type: "website",
  images: { url: "/og/image.png", width: 1200, height: 630, alt: SITE_NAME },
} as const;

const getMarkdownUrl = createGetUrl("/llms.mdx/docs");

/** The Markdown URL of a docs page. */
export function getPageMarkdownUrl(page: { slugs: string[] }) {
  const segments = [...page.slugs, "content.md"];

  return { segments, url: getMarkdownUrl(segments) };
}
