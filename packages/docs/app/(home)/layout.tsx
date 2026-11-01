"use client";

import { HomeLayout } from "fumadocs-ui/layouts/home";
import { usePathname } from "next/navigation";
import { baseOptions } from "@/lib/layout.shared";

export default function Layout({ children }: LayoutProps<"/">) {
  const isHomepage = usePathname() === "/";
  return (
    <HomeLayout {...baseOptions()}>
      {children}
      <footer className="mt-auto border-t border-fd-border py-6 text-center text-sm text-fd-muted-foreground">
        Callcium by{" "}
        <a
          href="https://provencraft.com"
          className="text-fd-foreground/80 transition-colors hover:text-fd-foreground"
          target="_blank"
          rel="noopener noreferrer"
        >
          Provencraft
        </a>{" "}
        · MIT License
        {isHomepage && " · Lean is a trademark of Lean FRO"}
      </footer>
    </HomeLayout>
  );
}
