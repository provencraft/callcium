import type { ComponentPropsWithoutRef } from "react";
import { forwardRef } from "react";
import { cn } from "@/lib/utils";

/** Monospace textarea with standard tool styling. */
const MonoTextarea = forwardRef<HTMLTextAreaElement, ComponentPropsWithoutRef<"textarea">>(
  ({ className, ...props }, ref) => (
    <textarea
      ref={ref}
      className={cn(
        "w-full rounded-lg border border-fd-border bg-fd-card px-3 py-2 font-mono text-sm",
        "placeholder:text-fd-muted-foreground/50",
        "focus:outline-none focus:ring-2 focus:ring-inset focus:ring-fd-ring",
        "resize-y",
        className,
      )}
      autoComplete="off"
      spellCheck={false}
      {...props}
    />
  ),
);
MonoTextarea.displayName = "MonoTextarea";

export { MonoTextarea };
