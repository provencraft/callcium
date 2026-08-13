import { describe, expect, test } from "vitest";

import { parsePathSteps } from "../src/policy-coder";
import { expectErrorCode } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// parsePathSteps
///////////////////////////////////////////////////////////////////////////

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

  test("byte length that is not a whole number of steps throws INVALID_PATH", () => {
    expectErrorCode(() => parsePathSteps("0x000000"), "INVALID_PATH");
  });
});
