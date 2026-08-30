import { SiSolidity, SiTypescript } from "@icons-pack/react-simple-icons";
import { icons as lucideIcons } from "lucide-react";
import { createElement, type ReactElement } from "react";

const brandIcons: Record<string, () => ReactElement> = {
  solidity: () => createElement(SiSolidity),
  typescript: () => createElement(SiTypescript),
};

/** Resolve a meta.json `icon` string to a ReactElement, preferring brand icons over lucide. */
function resolveIcon(icon: string): ReactElement | undefined {
  const brand = brandIcons[icon];
  if (brand) return brand();

  const Icon = lucideIcons[icon as keyof typeof lucideIcons];
  if (Icon) return createElement(Icon);

  console.warn(`[icons-plugin] Unknown icon: ${icon}.`);
}

/** Fumadocs source plugin that rewrites `icon` strings in the page tree into React elements. */
export function iconsPlugin() {
  const replace = <T extends { icon?: unknown }>(node: T): T => {
    if (typeof node.icon === "string") {
      (node as { icon: unknown }).icon = resolveIcon(node.icon);
    }
    return node;
  };

  return {
    name: "callcium:icons",
    transformPageTree: {
      file: replace,
      folder: replace,
      separator: replace,
    },
  };
}
