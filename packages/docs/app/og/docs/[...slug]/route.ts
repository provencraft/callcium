import { generateOGImage } from "fumadocs-ui/og";
import { notFound } from "next/navigation";
import { ogBrand } from "@/lib/og";
import { SITE_NAME } from "@/lib/shared";
import { getPageImage, source } from "@/lib/source";

export const revalidate = false;

export async function GET(_req: Request, { params }: RouteContext<"/og/docs/[...slug]">) {
  const { slug } = await params;
  const page = source.getPage(slug.slice(0, -1));
  if (!page) notFound();

  return generateOGImage({ ...ogBrand, title: page.data.title, description: page.data.description, site: SITE_NAME });
}

export function generateStaticParams() {
  return source.getPages().map((page) => ({ slug: getPageImage(page).segments }));
}
