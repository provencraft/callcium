import { OpenPanelComponent } from "@openpanel/nextjs";
import { Hanken_Grotesk, JetBrains_Mono } from "next/font/google";
import type { Metadata } from "next";
import "./global.css";
import { Provider } from "./provider";
import { OPEN_GRAPH, SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "@/lib/shared";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    template: `%s | ${SITE_NAME}`,
    default: `${SITE_NAME}: Calldata Policy Engine for the EVM`,
  },
  description: SITE_DESCRIPTION,
  openGraph: OPEN_GRAPH,
  twitter: { card: "summary_large_image", site: "@CallciumDev" },
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
        {process.env.NODE_ENV === "production" && (
          <OpenPanelComponent
            clientId="c03af4f0-2a91-4911-8808-24ca04a40716"
            scriptUrl="/a/script.js"
            apiUrl="/a"
            trackScreenViews
          />
        )}
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
