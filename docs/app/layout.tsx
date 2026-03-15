import { Banner } from "fumadocs-ui/components/banner";
import type { Metadata } from "next";
import { Provider } from "./provider";
import "./global.css";
import { Hanken_Grotesk, JetBrains_Mono } from "next/font/google";

export const metadata: Metadata = {
  metadataBase: new URL("https://callcium.dev"),
  title: {
    template: "%s | Callcium",
    default: "Callcium",
  },
  description:
    "Define type-safe constraints on ABI-encoded data. Update validation rules without redeploying contracts.",
  icons: { icon: "/icon.svg" },
};

const hankenGrotesk = Hanken_Grotesk({ subsets: ["latin"] });
const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
});

export default function Layout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${hankenGrotesk.className} ${jetbrainsMono.variable}`} suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <Banner>Pre-release — The API surface may change. Unaudited.</Banner>
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
