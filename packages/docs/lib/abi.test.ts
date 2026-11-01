import { afterEach, describe, expect, it, vi } from "vitest";
import { lookup4byte, parseAbiFunctions } from "./abi";

describe("parseAbiFunctions", () => {
  it("rejects a function without inputs", () => {
    expect(parseAbiFunctions('[{"type":"function","name":"pause"}]')).toBeInstanceOf(Error);
  });

  it("rejects a function with an untyped input", () => {
    expect(parseAbiFunctions('[{"type":"function","name":"f","inputs":[{"name":"x"}]}]')).toBeInstanceOf(Error);
  });

  it("rejects a function without a name", () => {
    expect(parseAbiFunctions('[{"type":"function","inputs":[]}]')).toBeInstanceOf(Error);
  });

  it("lists state-changing functions before read-only ones and skips other items", () => {
    const functions = parseAbiFunctions(
      JSON.stringify([
        { type: "function", name: "balanceOf", inputs: [], outputs: [], stateMutability: "view" },
        { type: "event", name: "Transfer", inputs: [] },
        { type: "function", name: "pause", inputs: [], outputs: [], stateMutability: "nonpayable" },
      ]),
    );
    if (functions instanceof Error) throw functions;
    expect(functions.map((abiFunction) => abiFunction.name)).toEqual(["pause", "balanceOf"]);
  });
});

describe("lookup4byte", () => {
  const selector = "0x00000000";

  afterEach(() => vi.unstubAllGlobals());

  function stubLookup(name: string) {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => Response.json({ result: { function: { [selector]: [{ name }] } } })),
    );
  }

  it("returns the function name of the first result", async () => {
    stubLookup("transfer(address,uint256)");
    expect(await lookup4byte(selector)).toBe("transfer");
  });

  it("returns null for a name that is not an identifier", async () => {
    stubLookup("x)y(address,uint256)");
    expect(await lookup4byte(selector)).toBeNull();
  });
});
