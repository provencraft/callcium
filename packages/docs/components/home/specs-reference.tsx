import { Card, Cards } from "fumadocs-ui/components/card";
import { BookOpen, Code, Rocket } from "lucide-react";

export function SpecsReference() {
  return (
    <section className="border-t border-fd-border">
      <div className="mx-auto max-w-4xl px-6 py-16">
        <Cards>
          <Card
            icon={<Rocket className="h-5 w-5" />}
            title="Getting Started"
            description="Install, write your first policy, and enforce it on-chain."
            href="/docs"
          />
          <Card
            icon={<BookOpen className="h-5 w-5" />}
            title="Specifications"
            description="Normative policy and descriptor format definitions."
            href="/docs/specifications"
          />
          <Card
            icon={<Code className="h-5 w-5" />}
            title="Reference"
            description="Solidity contract API and TypeScript SDK reference."
            href="/docs/solidity/reference/policy-builder"
          />
        </Cards>
      </div>
    </section>
  );
}
