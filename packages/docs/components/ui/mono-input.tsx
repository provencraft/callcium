import type { ComponentPropsWithoutRef } from "react";
import { forwardRef } from "react";
import { cn } from "@/lib/utils";

/** Monospace single-line input with standard tool styling. */
const MonoInput = forwardRef<HTMLInputElement, ComponentPropsWithoutRef<"input">>(
  ({ className, type = "text", ...props }, ref) => (
    <input
      ref={ref}
      type={type}
      className={cn(
        "h-9 w-full rounded-lg border border-fd-border bg-fd-card px-3 py-1.5 font-mono text-sm",
        "placeholder:text-fd-muted-foreground/50",
        "focus:outline-none focus:ring-2 focus:ring-inset focus:ring-fd-ring",
        className,
      )}
      autoComplete="off"
      spellCheck={false}
      {...props}
    />
  ),
);
MonoInput.displayName = "MonoInput";

export { MonoInput };
