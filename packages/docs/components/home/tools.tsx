import { ArrowRight, ScanSearch, ShieldCheck, Wrench } from "lucide-react";
import Link from "next/link";

const tools = [
  {
    Icon: Wrench,
    title: "Policy Builder",
    description: "Build a policy visually, rule by rule.",
  },
  {
    Icon: ScanSearch,
    title: "Policy Inspector",
    description: "Decode any policy blob, field by field.",
  },
  {
    Icon: ShieldCheck,
    title: "Policy Enforcer",
    description: "Test calldata against a policy.",
  },
];

export function Tools() {
  return (
    <section>
      <div className="mx-auto max-w-5xl px-6 py-24">
        <div className="flex flex-col gap-3">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">Policy Tools</h2>
          <p className="text-fd-muted-foreground text-pretty">
            The tools run in the browser and use the TypeScript SDK.
          </p>
          <Link
            href="/tools"
            className="mt-2 inline-flex w-fit items-center gap-1.5 font-medium text-fd-primary hover:underline"
          >
            Open the tools
            <ArrowRight className="size-4" aria-hidden="true" />
          </Link>
        </div>

        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          {tools.map(({ Icon, title, description }) => (
            <div key={title} className="flex flex-col gap-4 rounded-lg border border-fd-border bg-fd-card p-6">
              <Icon className="size-6 text-fd-primary" aria-hidden="true" />
              <div className="flex flex-col gap-2">
                <span className="font-mono text-[0.8125rem] font-semibold">{title}</span>
                <p className="text-sm text-pretty text-fd-muted-foreground">{description}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
