import { Eye, GitMerge, Package } from "lucide-react";
import Link from "next/link";

const features = [
  {
    Icon: Package,
    title: "Self-Contained",
    description: "Descriptors are embedded in the policy blob — no external registry or lookup at enforce-time.",
    href: "/docs/specifications",
  },
  {
    Icon: GitMerge,
    title: "Composable",
    description:
      "Layer multiple constraints per argument. Chain groups with OR semantics for flexible permission models.",
    href: "/docs/solidity/reference/policy-builder",
  },
  {
    Icon: Eye,
    title: "Auditable",
    description: "Any policy blob decoded and inspected entirely on-chain. Audits are reproducible and trustless.",
    href: "/docs/solidity/reference/policy-validator",
  },
];

export function Capabilities() {
  return (
    <section className="border-t border-fd-border">
      <div className="mx-auto max-w-4xl px-6 py-12">
        <div className="grid gap-8 sm:grid-cols-3">
          {features.map(({ Icon, title, description, href }) => (
            <Link key={title} href={href} className="group flex flex-col gap-2">
              <div className="flex items-center gap-2">
                <Icon className="h-4 w-4 text-fd-primary" aria-hidden="true" />
                <span className="font-mono text-sm font-semibold">{title}</span>
              </div>
              <p className="text-sm text-fd-muted-foreground transition-colors group-hover:text-fd-foreground">
                {description}
              </p>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}
