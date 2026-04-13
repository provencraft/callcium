import { Suspense } from "react";
import type { Metadata } from "next";
import { Enforcer } from "@/components/policy-enforcer/enforcer";

export const metadata: Metadata = {
  title: "Policy Enforcer",
  description: "Test calldata against a Callcium policy. See pass/fail results with detailed violation explanations.",
};

export default function PolicyEnforcerPage() {
  return (
    <main className="mx-auto w-full max-w-[var(--fd-layout-width)] px-4 py-12">
      <h1 className="text-3xl font-bold mb-2">Policy Enforcer</h1>
      <p className="text-fd-muted-foreground mb-8">
        Test calldata against a policy to check whether it satisfies the constraints.
      </p>
      <Suspense>
        <Enforcer />
      </Suspense>
    </main>
  );
}
