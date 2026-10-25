import { DualEnforcementView } from "./dual-enforcement-view";
import { buildApproveLens } from "./policy-lens-data";
import { APPROVE } from "./snippets";
import { renderCode } from "@/lib/highlight";

export async function DualEnforcement() {
  const [solidity, typescript] = await Promise.all([
    renderCode(APPROVE.solidity, "solidity"),
    renderCode(APPROVE.typescript, "typescript"),
  ]);

  return <DualEnforcementView solidity={solidity} typescript={typescript} lens={buildApproveLens()} />;
}
