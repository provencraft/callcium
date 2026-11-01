import { buttonVariants } from "fumadocs-ui/components/ui/button";
import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { Toolbox } from "lucide-react";
import Link from "next/link";
import { baseOptions } from "@/lib/layout.shared";
import { source } from "@/lib/source";
import { cn } from "@/lib/utils";

export default function Layout({ children }: LayoutProps<"/docs">) {
  return (
    <DocsLayout
      tree={source.getPageTree()}
      {...baseOptions()}
      links={[]}
      searchToggle={{ enabled: true }}
      sidebar={{
        // Fumadocs renders the footer after the theme switch in a flex column, so order-first lifts the link above it.
        footer: (
          <Link
            href="/tools"
            className={cn(
              buttonVariants({ variant: "secondary" }),
              "order-first mb-2 justify-start gap-2 bg-fd-secondary/50 text-fd-muted-foreground",
            )}
          >
            <Toolbox className="size-4.5" aria-hidden="true" />
            Policy Tools
          </Link>
        ),
      }}
    >
      {children}
    </DocsLayout>
  );
}
