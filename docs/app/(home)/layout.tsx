import { HomeLayout } from "fumadocs-ui/layouts/home";
import { baseOptions } from "@/lib/layout.shared";

export default function Layout({ children }: LayoutProps<"/">) {
  return (
    <HomeLayout {...baseOptions()}>
      {children}
      <footer className="mt-auto py-4 text-center text-xs text-fd-muted-foreground/50">
        Callcium by{" "}
        <a
          href="https://provencraft.com"
          className="hover:text-fd-muted-foreground"
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
