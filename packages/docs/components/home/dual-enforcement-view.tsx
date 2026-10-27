import { CodeBlock } from "fumadocs-ui/components/codeblock";
import type { ReactNode } from "react";
import { DualPanes } from "./dual-panes";
import { PolicyLens } from "./policy-lens";
import type { LensData } from "./policy-lens-data";

export function DualEnforcementView({
  solidity,
  typescript,
  lens,
}: {
  solidity: ReactNode;
  typescript: ReactNode;
  lens: LensData;
}) {
  return (
    <section className="border-t border-fd-border bg-fd-section">
      <div className="mx-auto max-w-5xl px-6 py-24">
        <div className="flex max-w-2xl flex-col gap-3">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">
            Enforce onchain, offchain, or both
          </h2>
          <p className="text-fd-muted-foreground text-pretty">
            Two complete implementations, each standalone. Same API, same bytes, same verdict.
          </p>
        </div>

        <div className="mt-8">
          <DualPanes
            solidity={<CodeBlock className="my-0">{solidity}</CodeBlock>}
            typescript={<CodeBlock className="my-0">{typescript}</CodeBlock>}
          />
        </div>

        <div aria-hidden="true" className="my-3 flex flex-col items-center text-fd-muted-foreground/50">
          {/* Pane centre to pane centre: half the row plus half the panes' gap-4. */}
          <svg
            viewBox="0 0 100 100"
            preserveAspectRatio="none"
            fill="none"
            className="hidden h-14 w-[calc(50%+0.5rem)] overflow-visible xl:block"
          >
            {["M0 0C0 60 50 40 50 100", "M100 0C100 60 50 40 50 100"].map((d) => (
              <path key={d} d={d} stroke="currentColor" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
            ))}
          </svg>
          <span className="h-8 w-[1.5px] bg-current xl:hidden" />
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" className="block shrink-0">
            <path
              d="M6 0v11M1 6l5 5 5-5"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </div>

        <div className="mx-auto max-w-3xl">
          <PolicyLens data={lens} />
        </div>
      </div>
    </section>
  );
}
