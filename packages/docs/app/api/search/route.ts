import { createFromSource } from "fumadocs-core/search/server";
import { source } from "@/lib/source";

// Statically cached.
export const revalidate = false;
export const { staticGET: GET } = createFromSource(source);
