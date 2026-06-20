import { Eye, GitMerge, Package } from "lucide-react";
import Link from "next/link";

const features = [
  {
    Icon: Package,
    title: "Self-Contained",
    description: "Descriptors are embedded in the policy blob, so enforcement needs no external registry or lookup.",
    href: "/docs/specifications",
  },
  {
    Icon: GitMerge,
    title: "Composable",
    description: "Layer multiple constraints on any argument or field. They compose into a single policy blob.",
    href: "/docs/solidity/reference/policy-builder",
  },
  {
    Icon: Eye,
    title: "Auditable",
    description: "Validation catches contradictions, redundant rules, and type mismatches before you ship.",
    href: "/docs/solidity/reference/policy-validator",
  },
];

export function Capabilities() {
  return (
    <section className="bg-fd-primary/[0.04]">
      <div className="mx-auto max-w-5xl px-6 py-20">
        <h2 className="mb-8 font-mono text-sm font-semibold tracking-tight text-fd-muted-foreground">
          Why it holds up
        </h2>
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
