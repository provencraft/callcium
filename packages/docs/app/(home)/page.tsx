import { DualEnforcement } from "@/components/home/dual-enforcement";
import { FeatureExplorer } from "@/components/home/feature-explorer";
import { GetStarted } from "@/components/home/get-started";
import { Hero } from "@/components/home/hero";
import { LanguageProvider } from "@/components/home/language-provider";
import { Tools } from "@/components/home/tools";
import { Verification } from "@/components/home/verification";

export default function HomePage() {
  return (
    <LanguageProvider>
      <Hero />
      <DualEnforcement />
      <FeatureExplorer />
      <Verification />
      <Tools />
      <GetStarted />
    </LanguageProvider>
  );
}
