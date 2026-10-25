import { getSidebarTabs } from "fumadocs-ui/utils/get-sidebar-tabs";
import Link from "next/link";
import { source } from "@/lib/source";

/** The documentation sections other than the overview, with the icon, title and description the sidebar shows. */
export function EnvironmentCards() {
  const tabs = getSidebarTabs(source.getPageTree(), { transform: (option) => option }).filter(
    (tab) => !tab.urls?.has("/docs"),
  );

  return (
    <div className="not-prose -mx-4 grid gap-3 sm:grid-cols-2">
      {tabs.map((tab) => (
        <Link
          key={tab.url}
          href={tab.url}
          className="flex items-center gap-4 rounded-xl p-4 transition-colors hover:bg-fd-accent/80"
        >
          <div className="size-10 shrink-0 [&_svg]:size-full" aria-hidden="true">
            {tab.icon}
          </div>
          <div className="flex flex-col gap-1">
            <span className="font-medium">{tab.title}</span>
            <span className="text-sm text-fd-muted-foreground">{tab.description}</span>
          </div>
        </Link>
      ))}
    </div>
  );
}
