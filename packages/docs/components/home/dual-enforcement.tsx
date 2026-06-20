import { DualEnforcementView } from "./dual-enforcement-view";
import { APPROVE, ENFORCE } from "./snippets";
import { renderCode } from "@/lib/highlight";

export async function DualEnforcement() {
  const [solidity, typescript] = await Promise.all([
    renderCode(`${APPROVE.solidity}\n\n${ENFORCE.solidity}`, "solidity"),
    renderCode(`${APPROVE.typescript}\n\n${ENFORCE.typescript}`, "typescript"),
  ]);

  return <DualEnforcementView solidity={solidity} typescript={typescript} />;
}
