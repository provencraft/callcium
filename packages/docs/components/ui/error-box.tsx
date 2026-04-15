import { cn } from "@/lib/utils";

/** Styled error container used across tool UIs. */
export function ErrorBox({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        "rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-700 dark:text-red-300",
        className,
      )}
    >
      {children}
    </div>
  );
}
