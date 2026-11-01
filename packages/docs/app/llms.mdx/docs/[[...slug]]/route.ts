import { notFound } from "next/navigation";
import { getPageMarkdownUrl } from "@/lib/shared";
import { source } from "@/lib/source";

export const revalidate = false;

export async function GET(_req: Request, { params }: RouteContext<"/llms.mdx/docs/[[...slug]]">) {
  const { slug = [] } = await params;
  const page = source.getPage(slug.slice(0, -1));
  if (!page) notFound();

  const markdown = `# ${page.data.title} (${page.url})\n\n${await page.data.getText("processed")}`;

  return new Response(markdown, {
    headers: { "Content-Type": "text/markdown" },
  });
}

export function generateStaticParams() {
  return source.getPages().map((page) => ({
    slug: getPageMarkdownUrl(page).segments,
  }));
}
