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
        <div className="flex flex-col gap-4">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">Express any constraint</h2>
          <p className="max-w-xl text-fd-muted-foreground text-pretty">
            Scalar arguments, nested struct fields, array elements, transaction context, even raw ABI blobs. Compose
            them with AND/OR logic. Pick a capability.
          </p>
        </div>

        <div className="mt-8 flex flex-wrap gap-2">
          {features.map((feature) => {
            const selected = feature.id === activeId;
            return (
              <button
                key={feature.id}
                type="button"
                aria-pressed={selected}
                onClick={() => setActiveId(feature.id)}
                className={cn(
                  "rounded-lg border px-3.5 py-1.5 font-mono text-sm transition-colors",
                  selected
                    ? "border-fd-primary bg-fd-primary text-fd-primary-foreground"
                    : "border-fd-border text-fd-muted-foreground hover:border-fd-primary/40 hover:text-fd-foreground",
                )}
              >
                {feature.label}
              </button>
            );
          })}
        </div>

        {/* All features stay in the DOM (crawlable); the pill toggles visibility. */}
        {features.map((feature) => (
          <div
            key={feature.id}
            className={cn(
              "mt-5 grid gap-5 lg:grid-cols-[minmax(0,18rem)_minmax(0,1fr)] lg:items-start",
              feature.id !== activeId && "hidden",
            )}
          >
            <p className="text-pretty text-fd-muted-foreground lg:pt-9">{feature.blurb}</p>
            <CodeSwitch
              solidity={<CodeBlock className="min-h-[12rem]">{feature.solidity}</CodeBlock>}
              typescript={<CodeBlock className="min-h-[12rem]">{feature.typescript}</CodeBlock>}
            />
          </div>
        ))}
      </div>
    </section>
  );
}
