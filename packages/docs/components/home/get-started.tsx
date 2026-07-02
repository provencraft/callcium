import { SiGithub } from "@icons-pack/react-simple-icons";
import { buttonVariants } from "fumadocs-ui/components/ui/button";
import Link from "next/link";
import { GetStartedButton } from "./get-started-button";
import { GridBackground } from "./grid-background";
import { gitConfig } from "@/lib/layout.shared";
import { cn } from "@/lib/utils";

export function GetStarted() {
  return (
    <section className="relative overflow-hidden bg-fd-primary/[0.04]">
      <GridBackground maxOpacity={0.1} />
      <div className="relative mx-auto flex max-w-5xl flex-col items-center gap-6 px-6 py-28 text-center">
        <div className="flex flex-col items-center gap-3">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">Start building</h2>
          <p className="max-w-md text-fd-muted-foreground text-pretty">
            Install the Solidity library or the TypeScript SDK and write your first policy.
          </p>
        </div>

        <div className="flex w-full flex-col items-stretch justify-center gap-3 sm:w-auto sm:flex-row sm:items-center">
          <GetStartedButton />
          <Link
            href={`https://github.com/${gitConfig.user}/${gitConfig.repo}`}
            target="_blank"
            rel="noopener noreferrer"
            className={cn(buttonVariants({ variant: "secondary" }), "gap-2 px-6 py-2.5 text-base")}
          >
            <SiGithub className="h-4 w-4" aria-hidden="true" />
            GitHub
          </Link>
        </div>
      </div>
    </section>
  );
}
