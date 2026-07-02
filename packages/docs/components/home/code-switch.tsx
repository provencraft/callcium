"use client";

import type { ReactNode } from "react";
import { useLanguage } from "./language-provider";
import { PillToggle } from "@/components/ui/pill-toggle";
import { cn } from "@/lib/utils";

const LANG_OPTIONS = [
  { value: "solidity", label: "Solidity" },
  { value: "typescript", label: "TypeScript" },
] as const;

/**
 * Renders both language variants into the DOM and shows the active one via CSS,
 * so the inactive variant stays crawlable. The toggle is synced site-wide
 * through the shared language store, never per-block state.
 */
export function CodeSwitch({
  solidity,
  typescript,
  label,
}: {
  solidity: ReactNode;
  typescript: ReactNode;
  label?: string;
}) {
  const { lang, setLang } = useLanguage();

  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="flex items-center justify-between gap-3">
        {label ? (
          <span className="font-mono text-xs text-fd-muted-foreground">{label}</span>
        ) : (
          <span aria-hidden="true" />
        )}
        <PillToggle value={lang} options={LANG_OPTIONS} onChange={setLang} />
      </div>
      <div className={cn("min-w-0", lang !== "solidity" && "hidden")}>{solidity}</div>
      <div className={cn("min-w-0", lang !== "typescript" && "hidden")}>{typescript}</div>
    </div>
  );
}
