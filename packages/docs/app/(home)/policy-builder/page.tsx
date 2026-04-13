import { Suspense } from "react";
import type { Metadata } from "next";
import { Builder } from "@/components/policy-builder/builder";

export const metadata: Metadata = {
  title: "Policy Builder",
  description:
    "Visually construct Callcium policies. Select function parameters, add constraints, and get the encoded policy blob.",
};

export default function PolicyBuilderPage() {
  return (
    <main className="mx-auto w-full max-w-[var(--fd-layout-width)] px-4 py-12">
      <h1 className="text-3xl font-bold mb-2">Policy Builder</h1>
      <p className="text-fd-muted-foreground mb-8">
        Construct a policy by selecting parameters and adding constraints.
      </p>
      <Suspense>
        <Builder />
      </Suspense>
    </main>
  );
}
