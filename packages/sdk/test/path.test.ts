import { describe, expect, test } from "vitest";

import { Quantifier, encodePath, isQuantifier, lookupQuantifier, parsePathSteps } from "../src/path";
import { expectErrorCode } from "./helpers";

describe("parsePathSteps", () => {
  test("empty path yields no steps", () => {
    expect(parsePathSteps("0x")).toEqual([]);
  });

  test("single step", () => {
    expect(parsePathSteps("0x0001")).toEqual([1]);
  });

  test("several steps", () => {
    expect(parsePathSteps("0x0000ffff0002")).toEqual([0, 65535, 2]);
  });

  test("odd-length body throws INVALID_HEX", () => {
    expectErrorCode(() => parsePathSteps("0x000"), "INVALID_HEX");
  });

  test("non-hex characters throw INVALID_HEX", () => {
    expectErrorCode(() => parsePathSteps("0xzzzz"), "INVALID_HEX");
  });

  test("non-hex characters in a trailing step throw INVALID_HEX", () => {
    expectErrorCode(() => parsePathSteps("0x0000zz"), "INVALID_HEX");
  });

  test("byte length that is not a whole number of steps throws MALFORMED_PATH", () => {
    expectErrorCode(() => parsePathSteps("0x000000"), "MALFORMED_PATH");
  });
});

describe("encodePath", () => {
  test("encodes ordinary steps and both quantifier sentinels", () => {
    expect(encodePath([0, 1])).toBe("0x00000001");
    expect(encodePath([0, Quantifier.ALL])).toBe("0x0000ffff");
    expect(encodePath([0, Quantifier.ANY])).toBe("0x0000fffe");
  });

  test("rejects a step the field cannot hold", () => {
    expectErrorCode(() => encodePath([-1]), "MALFORMED_PATH_STEP");
    expectErrorCode(() => encodePath([0x10000]), "MALFORMED_PATH_STEP");
    expectErrorCode(() => encodePath([1.5]), "MALFORMED_PATH_STEP");
  });
});

describe("lookupQuantifier", () => {
  test("ALL", () => {
    expect(lookupQuantifier(Quantifier.ALL)).toEqual({ label: "all" });
  });

  test("ANY", () => {
    expect(lookupQuantifier(Quantifier.ANY)).toEqual({ label: "any" });
  });

  test("rejects unknown quantifier code", () => {
    expectErrorCode(() => lookupQuantifier(0x0000), "UNKNOWN_QUANTIFIER");
  });
});

describe("isQuantifier", () => {
  test("accepts the reserved quantifier steps", () => {
    expect(isQuantifier(Quantifier.ALL)).toBe(true);
    expect(isQuantifier(Quantifier.ANY)).toBe(true);
  });

  test("rejects the highest concrete index", () => {
    expect(isQuantifier(Quantifier.ANY - 1)).toBe(false);
  });
});
