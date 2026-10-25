import { Hanken_Grotesk, JetBrains_Mono } from "next/font/google";
import type { Metadata } from "next";
import "./global.css";
import { Provider } from "./provider";
import { SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "@/lib/shared";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    template: `%s | ${SITE_NAME}`,
    default: SITE_NAME,
  },
  description: SITE_DESCRIPTION,
  openGraph: { images: "/og/image.png" },
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
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
