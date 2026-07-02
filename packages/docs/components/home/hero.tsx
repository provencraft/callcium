import { SiGithub } from "@icons-pack/react-simple-icons";
import { buttonVariants } from "fumadocs-ui/components/ui/button";
import Image from "next/image";
import Link from "next/link";
import { GridBackground } from "./grid-background";
import { PolicyLens } from "./policy-lens";
import { buildApproveLens } from "./policy-lens-data";
import { gitConfig } from "@/lib/layout.shared";
import { cn } from "@/lib/utils";

export function Hero() {
  const lens = buildApproveLens();

  return (
    <section className="relative overflow-hidden px-6 py-12 lg:py-16">
      <GridBackground />

      <div className="relative mx-auto flex max-w-5xl flex-col items-center gap-7 text-center">
        <Image src="/logo.svg" alt="Callcium" aria-hidden="true" className="w-24 sm:w-28" width={144} height={144} />

        <div className="flex flex-col items-center gap-4">
          <h1 className="text-4xl font-bold tracking-tight text-balance sm:text-5xl">
            Programmable Calldata Policy Engine
          </h1>
          <p className="max-w-2xl text-lg text-pretty text-fd-muted-foreground">
            Define type-safe constraints on ABI-encoded data. Enforce them{" "}
            <span className="text-fd-foreground">onchain in Solidity</span>, or{" "}
            <span className="text-fd-foreground">offchain in TypeScript</span>.
          </p>
        </div>

        <div className="flex w-full flex-col items-stretch justify-center gap-3 sm:w-auto sm:flex-row sm:items-center">
          <Link href="/docs" className={cn(buttonVariants({ variant: "primary" }), "px-8 py-2.5 text-base sm:w-auto")}>
            Get Started
          </Link>
          <Link
            href={`https://github.com/${gitConfig.user}/${gitConfig.repo}`}
            target="_blank"
            rel="noopener noreferrer"
            className={cn(buttonVariants({ variant: "secondary" }), "gap-2 px-6 py-2.5 text-base sm:w-auto")}
          >
            <SiGithub className="h-4 w-4" aria-hidden="true" />
            View on GitHub
          </Link>
        </div>

        <div className="w-full max-w-2xl text-left">
          <PolicyLens data={lens} />
        </div>
      </div>
    </section>
  );
}
