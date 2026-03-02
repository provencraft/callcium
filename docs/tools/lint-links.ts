import type { InferPageType } from "fumadocs-core/source";
import {
  type FileObject,
  printErrors,
  scanURLs,
  validateFiles,
} from "next-validate-link";
import { source } from "@/lib/source";

async function checkLinks() {
  const scanned = await scanURLs({
    preset: "next",
    populate: {
      "docs/[[...slug]]": source.getPages().map((page) => ({
        value: { slug: page.slugs },
        hashes: getHeadings(page),
      })),
    },
  });

  printErrors(
    await validateFiles(await getFiles(), {
      scanned,
      checkRelativePaths: "as-url",
    }),
    true,
  );
}

function getHeadings({ data }: InferPageType<typeof source>): string[] {
  return (data.toc ?? []).map((item) => item.url.slice(1));
}

async function getFiles(): Promise<FileObject[]> {
  const pages = source
    .getPages()
    .filter((page) => page.absolutePath !== undefined);
  return Promise.all(
    pages.map(async (page) => ({
      path: page.absolutePath as string,
      content: await page.data.getText("raw"),
      url: page.url,
      data: page.data,
    })),
  );
}

void checkLinks();
