import { createGetUrl } from "fumadocs-core/source";

export const SITE_NAME = "Callcium";
export const SITE_URL = "https://callcium.dev";
export const SITE_DESCRIPTION =
  "Change the rules, not the contract. Type-safe constraints on calldata, enforced onchain and offchain.";

const getMarkdownUrl = createGetUrl("/llms.mdx/docs");

/** The Markdown URL of a docs page. */
export function getPageMarkdownUrl(page: { slugs: string[] }) {
  const segments = [...page.slugs, "content.md"];

  return { segments, url: getMarkdownUrl(segments) };
}
