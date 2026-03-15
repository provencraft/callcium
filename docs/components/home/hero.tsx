import { highlight } from "fumadocs-core/highlight";
import { CodeBlock, Pre } from "fumadocs-ui/components/codeblock";
import { Tab, Tabs } from "fumadocs-ui/components/tabs";
import { buttonVariants } from "fumadocs-ui/components/ui/button";
import Image from "next/image";
import Link from "next/link";
import { shikiThemes } from "@/lib/shiki";
import { cn } from "@/lib/utils";
import { HeroBackground } from "./hero-background";

const tabs = [
  {
    label: "Flat Arguments",
    code: `// function approve(address spender, uint256 amount)
bytes memory policy = PolicyBuilder
    .create("approve(address,uint256)")
    .add(arg(0).isIn(trustedSpenders))     // spender
    .add(arg(1).lte(uint256(1_000_000e6))) // amount
    .build();`,
  },
  {
    label: "Nested Structs",
    code: `// struct SwapParams { address tokenIn; address tokenOut; uint256 amount; }
// function swap(SwapParams params)
bytes memory policy = PolicyBuilder
    .create("swap((address,address,uint256))")
    .add(arg(0, 0).notIn(sanctioned)) // params.tokenIn
    .add(arg(0, 1).notIn(sanctioned)) // params.tokenOut
    .add(arg(0, 2).gt(uint256(0)))    // params.amount
    .build();`,
  },
  {
    label: "Array Guards",
    code: `// struct Transaction { address to; uint256 value; }
// function multiSend(Transaction[] calls)
bytes memory policy = PolicyBuilder
    .create("multiSend((address,uint256)[])")
    .add(arg(0).lengthBetween(1, 50))            // calls.length
    .add(arg(0, Path.ALL, 0).notIn(sanctioned))  // calls[*].to
    .add(arg(0, Path.ALL, 1).lte(uint256(1e18))) // calls[*].value
    .build();`,
  },
  {
    label: "Context Constraints",
    code: `// function transfer(address to, uint256 amount)
bytes memory policy = PolicyBuilder
    .create("transfer(address,uint256)")
    .add(msgSender().isIn(operators))    // caller
    .add(arg(0).notIn(sanctioned))       // to
    .add(arg(1).lte(uint256(100e18)))    // amount
    .build();`,
  },
  {
    label: "OR Groups",
    code: `// function supply(address asset, uint256 amount)
bytes memory policy = PolicyBuilder
    .create("supply(address,uint256)")
    .add(msgSender().eq(OPERATOR))   // caller
    .or()
    .add(arg(0).isIn(allowedAssets)) // asset
    .build();`,
  },
];

export async function Hero() {
  const highlighted = await Promise.all(
    tabs.map(async (tab) => ({
      label: tab.label,
      rendered: await highlight(tab.code, {
        lang: "solidity" as const,
        themes: shikiThemes,
        components: {
          pre: (props) => <Pre {...props} />,
        },
      }),
    })),
  );

  return (
    <section className="relative overflow-hidden px-6 py-8 lg:py-12">
      <HeroBackground />

      <div className="relative mx-auto flex max-w-4xl flex-col items-center gap-10">
        {/* Title block */}
        <div className="flex flex-col items-center gap-4 text-center">
          <Image
            src="/logo.svg"
            alt="Callcium - Programmable Calldata Validation Engine"
            aria-hidden="true"
            className="mb-2 w-36"
            width={144}
            height={144}
          />
          <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">Programmable Calldata Validation Engine</h1>
          <p className="max-w-xl text-pretty text-lg text-fd-muted-foreground">
            <span className="block">Define type-safe constraints on ABI‑encoded data.</span>
            <span className="block">Update validation rules without redeploying contracts.</span>
          </p>
          <Link href="/docs" className={cn(buttonVariants({ variant: "primary" }), "px-8 py-2.5 text-base")}>
            Get Started
          </Link>
        </div>

        {/* Code tabs — full width, server-highlighted */}
        <div className="w-full">
          <h2 className="mb-4 text-center text-sm font-medium tracking-wide text-fd-muted-foreground">
            Build policies with a fluent Solidity API
          </h2>
          <Tabs items={highlighted.map((t) => t.label)}>
            {highlighted.map((tab) => (
              <Tab key={tab.label} value={tab.label}>
                <CodeBlock className="min-h-[11rem]">{tab.rendered}</CodeBlock>
              </Tab>
            ))}
          </Tabs>
        </div>
      </div>
    </section>
  );
}
