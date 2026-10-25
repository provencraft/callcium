import { generateOGImage } from "fumadocs-ui/og";
import { ogBrand } from "@/lib/og";
import { SITE_DESCRIPTION, SITE_NAME } from "@/lib/shared";

export const revalidate = false;

export function GET() {
  return generateOGImage({ ...ogBrand, title: SITE_NAME, description: SITE_DESCRIPTION });
}
