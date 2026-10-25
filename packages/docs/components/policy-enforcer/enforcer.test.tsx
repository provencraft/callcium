import { renderToString } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { Enforcer } from "./enforcer";

///////////////////////////////////////////////////////////////////////////
// Test helpers
///////////////////////////////////////////////////////////////////////////

/** An `approve(address,uint256)` selector followed by two zero words. */
const calldata = vi.hoisted(() => `0x095ea7b3${"0".repeat(128)}`);

vi.mock("next/navigation", () => ({ useSearchParams: () => new URLSearchParams({ calldata }) }));

///////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////

describe("Enforcer", () => {
  it("prefills the calldata field from the calldata URL parameter", () => {
    const html = renderToString(<Enforcer />);
    const field = html.match(/<textarea[^>]*id="enforcer-calldata-hex"[^>]*>([^<]*)<\/textarea>/);
    expect(field?.[1]).toBe(calldata);
  });
});
