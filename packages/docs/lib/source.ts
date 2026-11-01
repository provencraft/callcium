import { type InferPageType, loader } from "fumadocs-core/source";
import { docs } from "fumadocs-mdx:collections/server";
import { iconsPlugin } from "./icons-plugin";

export const source = loader({
  baseUrl: "/docs",
  source: docs.toFumadocsSource(),
  plugins: [iconsPlugin()],
});

export function getPageImage(page: InferPageType<typeof source>) {
  const segments = [...page.slugs, "image.png"];

  return {
    segments,
    url: `/og/docs/${segments.join("/")}`,
  };
}
