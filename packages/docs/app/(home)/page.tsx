import { Capabilities } from "@/components/home/capabilities";
import { DualEnforcement } from "@/components/home/dual-enforcement";
import { FeatureExplorer } from "@/components/home/feature-explorer";
import { GetStarted } from "@/components/home/get-started";
import { Hero } from "@/components/home/hero";
import { LanguageProvider } from "@/components/home/language-provider";
import { SpecsReference } from "@/components/home/specs-reference";
import { Tools } from "@/components/home/tools";

export default function HomePage() {
  return (
    <LanguageProvider>
      <Hero />
      <DualEnforcement />
      <FeatureExplorer />
      <Capabilities />
      <Tools />
      <GetStarted />
      <SpecsReference />
    </LanguageProvider>
  );
}
