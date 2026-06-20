"use client";

import { buttonVariants } from "fumadocs-ui/components/ui/button";
import Link from "next/link";
import { useLanguage } from "./language-provider";
import { cn } from "@/lib/utils";

/** Primary CTA whose target follows the active language. */
export function GetStartedButton() {
  const { lang } = useLanguage();
  const href = lang === "solidity" ? "/docs/solidity" : "/docs/sdk";

  return (
    <Link href={href} className={cn(buttonVariants({ variant: "primary" }), "px-8 py-2.5 text-base")}>
      Get Started
    </Link>
  );
}
