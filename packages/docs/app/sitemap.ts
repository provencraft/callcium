import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/shared";
import { source } from "@/lib/source";

export const revalidate = false;

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = ["/", "/tools", ...source.getPages().map((page) => page.url)];

  return paths.map((path) => ({ url: new URL(path, SITE_URL).href }));
}
