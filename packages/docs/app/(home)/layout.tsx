import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";

export default function Layout({ children }: LayoutProps<"/">) {
  return (
    <HomeLayout {...baseOptions()}>
      {children}
      <footer className="mt-auto border-t border-fd-border py-6 text-center text-xs text-fd-muted-foreground">
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
      </footer>
    </HomeLayout>
  );
}
