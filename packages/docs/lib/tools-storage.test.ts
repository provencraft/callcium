import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { addConstraint, createSession, type ConstraintInput } from "./policy-builder";
import { clearState, fromRules, loadState, saveState } from "./tools-storage";

describe("tools storage", () => {
  const store = new Map<string, string>();

  beforeEach(() => {
    store.clear();
    vi.stubGlobal("sessionStorage", {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => void store.set(key, value),
      removeItem: (key: string) => void store.delete(key),
      key: (index: number) => [...store.keys()][index] ?? null,
      get length() {
        return store.size;
      },
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("rebuilds a session with bigint operands from stored rules", () => {
    const session = addConstraint(createSession("approve(address spender, uint256 amount)"), 0, {
      scope: "calldata",
      path: [1],
      rules: [{ operator: "lte", values: [10n ** 30n] }],
    });

    saveState(
      "rules",
      session.groups.map((group) => group.constraints),
    );
    const rebuilt = fromRules(session.signature, false, loadState<ConstraintInput[][]>("rules", []));

    expect(session.hex).not.toBeNull();
    expect(rebuilt.hex).toBe(session.hex);
  });

  it("clears only the values it saved", () => {
    store.set("other", "kept");
    saveState("workspace", "saved");

    clearState();

    expect(loadState("workspace", "fallback")).toBe("fallback");
    expect(store.get("other")).toBe("kept");
  });
});
