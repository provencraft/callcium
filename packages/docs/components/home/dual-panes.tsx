"use client";

import type { ReactNode } from "react";
import { LANG_OPTIONS } from "./code-switch";
import { useLanguage } from "./language-provider";
import { PillToggle } from "@/components/ui/pill-toggle";
import { cn } from "@/lib/utils";

/** The two code panes: side by side from `xl`, one at a time behind the language toggle below it. */
export function DualPanes({ solidity, typescript }: { solidity: ReactNode; typescript: ReactNode }) {
  const { lang, setLang } = useLanguage();
  const panes = [
    { value: "solidity", label: "Solidity library", block: solidity },
    { value: "typescript", label: "TypeScript SDK", block: typescript },
  ] as const;

  return (
    <div className="flex flex-col gap-3">
      <PillToggle
        value={lang}
        options={LANG_OPTIONS}
        onChange={setLang}
        className="self-end xl:hidden [&_button]:text-sm"
      />
      <div className="grid gap-4 xl:grid-cols-2">
        {panes.map(({ value, label, block }) => (
          <div key={value} className={cn("flex min-w-0 flex-col gap-2", lang !== value && "max-xl:hidden")}>
            <p className="hidden font-mono text-[0.8125rem] font-semibold text-fd-primary xl:block">{label}</p>
            {block}
          </div>
        ))}
      </div>
    </div>
  );
}
