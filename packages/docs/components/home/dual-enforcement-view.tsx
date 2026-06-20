import { CodeBlock } from "fumadocs-ui/components/codeblock";
import type { ReactNode } from "react";

function Pane({ label, scenario, children }: { label: string; scenario: string; children: ReactNode }) {
  return (
    <div className="flex min-w-0 flex-col gap-2">
      <div>
        <p className="font-mono text-xs font-semibold text-fd-primary">{label}</p>
        <p className="font-mono text-xs text-fd-muted-foreground">{scenario}</p>
      </div>
      {children}
    </div>
  );
}

export function DualEnforcementView({ solidity, typescript }: { solidity: ReactNode; typescript: ReactNode }) {
  return (
    <section className="border-t border-fd-border bg-fd-primary/[0.04]">
      <div className="mx-auto max-w-5xl px-6 py-24">
        <div className="flex max-w-2xl flex-col gap-3">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">
            One spec, two implementations
          </h2>
          <p className="text-fd-muted-foreground text-pretty">
            The policy format is a specification with two independent implementations, a Solidity library and a
            TypeScript SDK. Reach for whichever your scenario needs: embed the engine in your contracts for dynamic
            onchain rules, or check payloads in TypeScript before they&rsquo;re signed. Use one, the other, or both.
          </p>
        </div>

        <div className="mt-10 grid gap-4 md:grid-cols-2">
          <Pane label="Solidity library" scenario="Dynamic guardrails in your contracts">
            <CodeBlock className="min-h-[12rem]">{solidity}</CodeBlock>
          </Pane>
          <Pane label="TypeScript SDK" scenario="Check payloads before signing">
            <CodeBlock className="min-h-[12rem]">{typescript}</CodeBlock>
          </Pane>
        </div>

        <p className="mt-5 max-w-2xl text-sm text-fd-muted-foreground text-pretty">
          Both implementations also expose <code className="font-mono text-fd-foreground">check</code>, which returns a
          result instead of reverting or throwing.
        </p>
      </div>
    </section>
  );
}
