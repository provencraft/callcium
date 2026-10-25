import { SiSolidity, SiTypescript } from "@icons-pack/react-simple-icons";
import { buttonVariants } from "fumadocs-ui/components/ui/button";
import Link from "next/link";
import { GridBackground } from "./grid-background";
import { cn } from "@/lib/utils";

const guides = [
  { Icon: SiSolidity, title: "Solidity library", href: "/docs/solidity" },
  { Icon: SiTypescript, title: "TypeScript SDK", href: "/docs/sdk" },
];

export function GetStarted() {
  return (
    <section className="relative overflow-hidden bg-fd-primary/[0.04]">
      <GridBackground maxOpacity={0.1} />
      <div className="relative mx-auto flex max-w-5xl flex-col items-center gap-8 px-6 py-24 text-center">
        <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">Start building</h2>

        <div className="flex w-full flex-col items-stretch justify-center gap-3 sm:w-auto sm:flex-row sm:items-center">
          {guides.map(({ Icon, title, href }) => (
            <Link
              key={href}
              href={href}
              className={cn(buttonVariants({ variant: "primary" }), "gap-2 px-6 py-2.5 text-base")}
            >
              <Icon className="size-4" aria-hidden="true" />
              {title}
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}
