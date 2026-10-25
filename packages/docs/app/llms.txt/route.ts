import { SITE_DESCRIPTION, SITE_NAME } from "@/lib/shared";
import { docsLlms, source } from "@/lib/source";

export const revalidate = false;

export function GET() {
  // The header names the site, which the root of the page tree does not.
  const sections = source.getPageTree().children.map((node) => docsLlms.indexNode(node));

  return new Response([`# ${SITE_NAME}`, "", `> ${SITE_DESCRIPTION}`, "", ...sections].join("\n"));
}
