import { ArrowRight } from "lucide-react";
import Image from "next/image";
import Link from "next/link";

export function Verification() {
  return (
    <section className="bg-fd-primary/[0.04]">
      <div className="mx-auto flex max-w-5xl flex-col gap-10 px-6 py-24 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex max-w-2xl flex-col gap-3">
          <h2 className="text-2xl font-semibold tracking-tight text-balance sm:text-3xl">Formal spec, Lean proofs</h2>
          <p className="text-fd-muted-foreground text-pretty">
            <span className="block">A Lean model defines the policy format and proves its guarantees.</span>
            <span className="block">Both implementations pass the same test vectors.</span>
          </p>
          <Link
            href="/docs/specifications"
            className="mt-2 inline-flex w-fit items-center gap-1.5 font-medium text-fd-primary hover:underline"
          >
            Read the specification
            <ArrowRight className="size-4" aria-hidden="true" />
          </Link>
        </div>

        {/* Lean FRO provides only a dark-ink logo, which disappears on dark grounds. */}
        <div className="shrink-0 dark:hidden">
          {/* The negative margins cancel the file's built-in padding, so the mark itself meets the text edges. */}
          <Image
            src="/lean/lean-logo-official-TM-transparent-2400x900.svg"
            alt="Lean logo"
            width={240}
            height={90}
            className="-mx-[24.5px] -my-[15px] max-w-none"
          />
        </div>
      </div>
    </section>
  );
}
