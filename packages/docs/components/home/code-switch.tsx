"use client";

import type { ReactNode } from "react";
import { useLanguage } from "./language-provider";
import { PillToggle } from "@/components/ui/pill-toggle";
import { cn } from "@/lib/utils";

export const LANG_OPTIONS = [
  { value: "solidity", label: "Solidity" },
  { value: "typescript", label: "TypeScript" },
] as const;

/**
 * Renders both language variants into the DOM and shows the active one via CSS, so the inactive variant stays
 * crawlable. The toggle is synced site-wide through the shared language store, never per-block state.
 */
export function CodeSwitch({
  solidity,
  typescript,
  toggleClassName,
}: {
  solidity: ReactNode;
  typescript: ReactNode;
  toggleClassName?: string;
}) {
  const { lang, setLang } = useLanguage();

  return (
    <div className="flex h-full min-w-0 flex-col gap-3">
      <div className={cn("flex items-center justify-end gap-3", toggleClassName)}>
        <PillToggle value={lang} options={LANG_OPTIONS} onChange={setLang} className="[&_button]:text-sm" />
      </div>
      <div className={cn("flex min-w-0 flex-1 flex-col", lang !== "solidity" && "hidden")}>{solidity}</div>
      <div className={cn("flex min-w-0 flex-1 flex-col", lang !== "typescript" && "hidden")}>{typescript}</div>
    </div>
  );
}
