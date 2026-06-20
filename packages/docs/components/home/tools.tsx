import { ScanSearch, ShieldCheck, Wrench } from "lucide-react";
import Link from "next/link";

const tools = [
  {
    Icon: Wrench,
    title: "Policy Builder",
    description: "Visually construct a policy and export the blob.",
    href: "/policy-builder",
  },
  {
    Icon: ScanSearch,
    title: "Policy Inspector",
    description: "Decode and explain any policy blob, field by field.",
    href: "/policy-inspector",
  },
  {
    Icon: ShieldCheck,
    title: "Policy Enforcer",
    description: "Test calldata against a policy and read the violations.",
    href: "/policy-enforcer",
  },
];

export function Tools() {
  return (
    <section>
      <div className="mx-auto max-w-5xl px-6 py-20">
        <div className="flex flex-col gap-3">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">
            Explore and debug, in the browser
          </h2>
          <p className="max-w-xl text-fd-muted-foreground text-pretty">
            Prototype policies visually and debug the ones you write. No install required.
          </p>
        </div>

        <div className="mt-8 grid gap-8 sm:grid-cols-3">
          {tools.map(({ Icon, title, description, href }) => (
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
