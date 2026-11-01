import type { Metadata } from "next";
import { DualEnforcement } from "@/components/home/dual-enforcement";
import { FeatureExplorer } from "@/components/home/feature-explorer";
import { GetStarted } from "@/components/home/get-started";
import { Hero } from "@/components/home/hero";
import { LanguageProvider } from "@/components/home/language-provider";
import { Tools } from "@/components/home/tools";
import { Verification } from "@/components/home/verification";
import { gitConfig } from "@/lib/layout.shared";
import { OPEN_GRAPH, SITE_DESCRIPTION, SITE_NAME, SITE_URL } from "@/lib/shared";

export const metadata: Metadata = {
  alternates: { canonical: "/" },
  openGraph: { ...OPEN_GRAPH, url: "/" },
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareSourceCode",
  "@id": `${SITE_URL}/#software`,
  name: SITE_NAME,
  description: SITE_DESCRIPTION,
  url: SITE_URL,
  codeRepository: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
  programmingLanguage: ["Solidity", "TypeScript"],
  license: "https://spdx.org/licenses/MIT",
  publisher: {
    "@type": "Organization",
    "@id": "https://provencraft.com/#organization",
    name: "Provencraft",
    url: "https://provencraft.com",
  },
};

export default function HomePage() {
  return (
    <LanguageProvider>
      {/* Escaping < keeps a "</script>" inside a string from closing the tag; the JSON stays valid. */}
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c") }}
      />
      <Hero />
      <DualEnforcement />
      <FeatureExplorer />
      <Verification />
      <Tools />
      <GetStarted />
    </LanguageProvider>
  );
}
