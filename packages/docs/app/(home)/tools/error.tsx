"use client";

import { buttonVariants } from "fumadocs-ui/components/ui/button";
import { ErrorBox } from "@/components/ui/error-box";
import { formatError } from "@/lib/format-error";
import { clearState } from "@/lib/tools-storage";

/** The tools page after an error. Reset removes the saved tools state and renders the page again. */
export default function ToolsError({ error, retry }: { error: unknown; retry: () => void }) {
  return (
    <main className="mx-auto w-full max-w-[var(--fd-layout-width)] px-4 py-12">
      <h1 className="text-3xl font-bold mb-2">Policy Tools</h1>
      <ErrorBox className="mb-4">{formatError(error)}</ErrorBox>
      <button
        type="button"
        className={buttonVariants({ variant: "outline", size: "sm" })}
        onClick={() => {
          clearState();
          retry();
        }}
      >
        Reset tools
      </button>
    </main>
  );
}
