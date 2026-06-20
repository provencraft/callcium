import { FeatureExplorerView } from "./feature-explorer-view";
import { FEATURES } from "./snippets";
import { renderCode } from "@/lib/highlight";

export async function FeatureExplorer() {
  const rendered = await Promise.all(
    FEATURES.map(async (feature) => ({
      id: feature.id,
      label: feature.label,
      blurb: feature.blurb,
      solidity: await renderCode(feature.solidity, "solidity"),
      typescript: await renderCode(feature.typescript, "typescript"),
    })),
  );

  return <FeatureExplorerView features={rendered} />;
}
