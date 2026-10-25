"use client";

import { CodeBlock } from "fumadocs-ui/components/codeblock";
import { useState } from "react";
import type { ReactNode } from "react";
import { CodeSwitch } from "./code-switch";
import { cn } from "@/lib/utils";

type RenderedFeature = { id: string; label: string; blurb: string; solidity: ReactNode; typescript: ReactNode };

export function FeatureExplorerView({ features }: { features: RenderedFeature[] }) {
  const [activeId, setActiveId] = useState(features[0]?.id);

  return (
    <section>
      <div className="mx-auto max-w-5xl px-6 py-24">
        <div className="flex flex-col gap-3">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">Advanced constraints</h2>
          <p className="text-fd-muted-foreground text-pretty">
            Reach into structs and arrays, compare against transaction context, and allow alternatives with OR.
          </p>
        </div>

        <div className="mt-8 grid gap-6 lg:grid-cols-[minmax(0,20rem)_minmax(0,1fr)]">
          <div className="flex flex-col gap-1">
            {features.map((feature) => {
              const selected = feature.id === activeId;
              return (
                <button
                  key={feature.id}
                  type="button"
                  aria-pressed={selected}
                  onClick={() => setActiveId(feature.id)}
                  className={cn(
                    "flex flex-col gap-1 rounded-lg px-4 py-2 text-left transition-colors",
                    selected ? "bg-fd-accent text-fd-accent-foreground" : "hover:bg-fd-accent/50",
                  )}
                >
                  <span className="font-mono text-[0.8125rem] font-semibold">{feature.label}</span>
                  {/* Every blurb stays in the DOM (crawlable); only the selected one shows. */}
                  <span className={cn("text-sm text-pretty", !selected && "hidden")}>{feature.blurb}</span>
                </button>
              );
            })}
          </div>

          {/* All panels share one cell, so it keeps the tallest panel's height; the list toggles visibility. */}
          <div className="grid min-w-0">
            {features.map((feature) => (
              <div
                key={feature.id}
                className={cn("relative col-start-1 row-start-1 min-w-0", feature.id !== activeId && "invisible")}
              >
                {/* On wide screens the toggle sits above the panel, so the panel starts level with the list. */}
                <CodeSwitch
                  toggleClassName="lg:absolute lg:right-0 lg:bottom-full lg:mb-2"
                  solidity={<CodeBlock className="my-0 flex-1">{feature.solidity}</CodeBlock>}
                  typescript={<CodeBlock className="my-0 flex-1">{feature.typescript}</CodeBlock>}
                />
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
