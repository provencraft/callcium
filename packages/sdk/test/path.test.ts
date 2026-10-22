import { describe, expect, test } from "vitest";

import { Quantifier, encodePath, parsePathSteps } from "../src/path";
import { expectErrorCode } from "./helpers";

describe("parsePathSteps", () => {
  test("odd-length body throws INVALID_HEX", () => {
    expectErrorCode(() => parsePathSteps("0x000"), "INVALID_HEX");
  });

  test("non-hex characters throw INVALID_HEX", () => {
    expectErrorCode(() => parsePathSteps("0xzzzz"), "INVALID_HEX");
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
    expectErrorCode(() => encodePath([-1]), "PATH_STEP_OVERFLOW");
    expectErrorCode(() => encodePath([0x10000]), "PATH_STEP_OVERFLOW");
    expectErrorCode(() => encodePath([1.5]), "PATH_STEP_OVERFLOW");
  });
});
