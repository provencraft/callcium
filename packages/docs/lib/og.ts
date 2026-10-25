import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createElement } from "react";

const logomark = `data:image/svg+xml;base64,${readFileSync(join(process.cwd(), "public/icon.svg")).toString("base64")}`;

/** Brand accent, text colour and logomark for generated OG images, on their dark ground. */
export const ogBrand = {
  primaryColor: "rgba(219, 58, 52, 0.3)",
  primaryTextColor: "rgb(226, 84, 80)",
  icon: createElement("img", { src: logomark, width: 56, height: 56 }),
};
