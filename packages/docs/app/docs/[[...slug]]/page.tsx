import {
  DocsBody,
  DocsDescription,
  DocsPage,
  DocsTitle,
  MarkdownCopyButton,
  ViewOptionsPopover,
} from "fumadocs-ui/layouts/docs/page";
import { createRelativeLink } from "fumadocs-ui/mdx";
import { notFound } from "next/navigation";
import type { InferPageType } from "fumadocs-core/source";
import type { Metadata } from "next";
import { gitConfig } from "@/lib/layout.shared";
import { getPageMarkdownUrl, OPEN_GRAPH } from "@/lib/shared";
import { getPageImage, source } from "@/lib/source";
import { getMDXComponents } from "@/mdx-components";

// Pages built from `spec/*.md`, NatSpec and TSDoc keep their source outside `content/docs`, so they get no GitHub link.
const generatedPage = /^\(protocol\)\/specifications\/(?!index\.mdx$)|^(solidity|sdk)\/reference\//;

export default async function Page(props: PageProps<"/docs/[[...slug]]">) {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  const MDX = page.data.body;
  const markdownUrl = getPageMarkdownUrl(page).url;

  return (
    <DocsPage toc={page.data.toc} full={page.data.full}>
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription>{page.data.description}</DocsDescription>
      <div className="flex flex-row items-center gap-2 border-b pt-2 pb-6">
        <MarkdownCopyButton markdownUrl={markdownUrl} />
        <ViewOptionsPopover
          markdownUrl={markdownUrl}
          githubUrl={
            generatedPage.test(page.path)
              ? undefined
              : `https://github.com/${gitConfig.user}/${gitConfig.repo}/blob/${gitConfig.branch}/packages/docs/content/docs/${page.path}`
          }
        />
      </div>
      <DocsBody>
        <MDX
          components={getMDXComponents({
            a: createRelativeLink(source, page),
          })}
        />
      </DocsBody>
    </DocsPage>
  );
}

export async function generateStaticParams() {
  return source.generateParams();
}

export async function generateMetadata(props: PageProps<"/docs/[[...slug]]">): Promise<Metadata> {
  const params = await props.params;
  const page = source.getPage(params.slug);
  if (!page) notFound();

  return {
    title: metadataTitle(page),
    description: page.data.description,
    alternates: {
      canonical: page.url,
      types: { "text/markdown": getPageMarkdownUrl(page).url },
    },
    openGraph: {
      ...OPEN_GRAPH,
      type: "article",
      url: page.url,
      images: { ...OPEN_GRAPH.images, url: getPageImage(page).url, alt: page.data.title },
    },
  };
}

// The sections a page URL starts with, which the sidebar names and a search result does not.
const sectionTitles: Partial<Record<string, string>> = {
  solidity: "Solidity",
  sdk: "TypeScript",
  specifications: "Specifications",
};

/** The metadata title of a page, naming the sidebar context that a search result does not show. */
function metadataTitle(page: InferPageType<typeof source>): string {
  const [section, ...rest] = page.slugs;
  const sectionTitle = sectionTitles[section];
  if (!sectionTitle) return page.data.title;
  // Solidity and TypeScript pages share titles, so the section title tells them apart.
  if (section !== "specifications") return `${page.data.title} (${sectionTitle})`;
  return rest.length === 0 ? sectionTitle : `${page.data.title} Specification`;
}
