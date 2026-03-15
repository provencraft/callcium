import type { Metadata } from "next";
import { Inspector } from "@/components/policy-inspector/inspector";

export const metadata: Metadata = {
  title: "Policy Inspector",
  description:
    "Decode and inspect Callcium policy blobs. Paste a hex-encoded policy to see its structure, constraints, and rules.",
};

export default function PolicyInspectorPage() {
  return (
    <main className="mx-auto w-full max-w-[var(--fd-layout-width)] px-4 py-12">
      <h1 className="text-3xl font-bold mb-2">Policy Inspector</h1>
      <p className="text-fd-muted-foreground mb-8">
        Paste a hex-encoded policy blob to decode and inspect its structure.
      </p>
      <Inspector />
    </main>
  );
}
