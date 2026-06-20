"use client";

import { Blocks, BookOpen, Braces } from "lucide-react";
import Link from "next/link";
import { useLanguage } from "./language-provider";
import { cn } from "@/lib/utils";

const links = [
  {
    Icon: Blocks,
    title: "Solidity",
    description: "Build and enforce policies onchain.",
    href: "/docs/solidity",
    lang: "solidity" as const,
  },
  {
    Icon: Braces,
    title: "TypeScript",
    description: "Build and enforce policies offchain.",
    href: "/docs/sdk",
    lang: "typescript" as const,
  },
  {
    Icon: BookOpen,
    title: "Specifications",
    description: "Normative policy and descriptor formats.",
    href: "/docs/specifications",
    lang: null,
  },
];

export function SpecsReference() {
  const { lang } = useLanguage();

  return (
    <section>
      <div className="mx-auto max-w-5xl px-6 py-16">
        <div className="grid gap-8 sm:grid-cols-3">
          {links.map(({ Icon, title, description, href, lang: linkLang }) => {
            const active = linkLang === lang;
            return (
              <Link key={title} href={href} className="group flex flex-col gap-2">
                <div className="flex items-center gap-2">
                  <Icon
                    className={cn("h-4 w-4", active ? "text-fd-primary" : "text-fd-muted-foreground")}
                    aria-hidden="true"
                  />
                  <span className="font-mono text-sm font-semibold">{title}</span>
                </div>
                <p className="text-sm text-fd-muted-foreground transition-colors group-hover:text-fd-foreground">
                  {description}
                </p>
              </Link>
            );
          })}
        </div>
      </div>
    </section>
  );
}
