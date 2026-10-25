import { ArrowRight, ScanSearch, ShieldCheck, Wrench } from "lucide-react";
import Link from "next/link";

const tools = [
  {
    Icon: Wrench,
    title: "Policy Builder",
    description: "Build a policy visually, rule by rule.",
    href: "/policy-builder",
  },
  {
    Icon: ScanSearch,
    title: "Policy Inspector",
    description: "Decode any policy blob, field by field.",
    href: "/policy-inspector",
  },
  {
    Icon: ShieldCheck,
    title: "Policy Enforcer",
    description: "Test calldata against a policy.",
    href: "/policy-enforcer",
  },
];

export function Tools() {
  return (
    <section>
      <div className="mx-auto max-w-5xl px-6 py-24">
        <div className="flex flex-col gap-3">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">
            The SDK, live in the browser
          </h2>
          <p className="text-fd-muted-foreground text-pretty">
            Build, inspect and enforce policies with the TypeScript SDK. No install.
          </p>
        </div>

        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          {tools.map(({ Icon, title, description, href }) => (
            <Link
              key={title}
              href={href}
              className="group flex flex-col gap-4 rounded-lg border border-fd-border bg-fd-card p-6 transition-colors hover:border-fd-primary/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-fd-ring"
            >
              <Icon className="size-6 text-fd-primary" aria-hidden="true" />
              <div className="flex flex-col gap-2">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-[0.8125rem] font-semibold">{title}</span>
                  <ArrowRight
                    className="size-4 text-fd-muted-foreground transition-colors group-hover:text-fd-primary"
                    aria-hidden="true"
                  />
                </div>
                <p className="text-sm text-pretty text-fd-muted-foreground">{description}</p>
              </div>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}
