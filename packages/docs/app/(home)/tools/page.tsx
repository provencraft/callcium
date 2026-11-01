import type { Metadata } from "next";
import { Workspace } from "@/components/tools/workspace";
import { OPEN_GRAPH } from "@/lib/shared";

export const metadata: Metadata = {
  title: "Policy Tools",
  description: "Build, inspect and enforce Callcium policies with the TypeScript SDK, in the browser.",
  alternates: { canonical: "/tools" },
  openGraph: { ...OPEN_GRAPH, url: "/tools" },
};

export default function ToolsPage() {
  return (
    <main className="mx-auto w-full max-w-[var(--fd-layout-width)] px-4 py-12">
      <h1 className="text-3xl font-bold mb-2">Policy Tools</h1>
      <p className="text-fd-muted-foreground mb-12">
        A policy is a set of constraints on calldata. Use these tools to build a policy from a function signature or
        ABI, to decode a policy blob into its rules, and to check calldata against a policy. Everything runs in the
        browser. No transaction is sent or executed, and policies and calldata are not uploaded.
      </p>
      <Workspace />
    </main>
  );
}
