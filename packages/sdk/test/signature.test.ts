import { describe, expect, test } from "vitest";

import { CallciumError } from "../src/errors";
import { SignatureParser } from "../src/signature";
import { expectErrorCode } from "./helpers";

describe("SignatureParser", () => {
  test("parses transfer(address,uint256)", () => {
    const result = SignatureParser.parse("transfer(address,uint256)");
    expect(result.selector).toBe("0xa9059cbb");
    expect(result.types).toBe("address,uint256");
  });

  test("parses approve(address,uint256)", () => {
    const result = SignatureParser.parse("approve(address,uint256)");
    expect(result.selector).toBe("0x095ea7b3");
    expect(result.types).toBe("address,uint256");
  });

  test("parses no-argument function pause()", () => {
    const result = SignatureParser.parse("pause()");
    expect(result.types).toBe("");
    expect(result.selector).toHaveLength(10);
    expect(result.selector.startsWith("0x")).toBe(true);
  });

  test("parses tuple argument swap((address,uint256))", () => {
    const result = SignatureParser.parse("swap((address,uint256))");
    expect(result.types).toBe("(address,uint256)");
  });

  test("rejects missing parentheses", () => {
    expect(() => SignatureParser.parse("transfer")).toThrow(CallciumError);
  });

  test("rejects empty string", () => {
    expect(() => SignatureParser.parse("")).toThrow(CallciumError);
  });

  test("rejects no function name", () => {
    expect(() => SignatureParser.parse("(uint256)")).toThrow(CallciumError);
  });

  test("rejects tab in signature", () => {
    expect(() => SignatureParser.parse("transfer\t(uint256)")).toThrow(CallciumError);
  });

  test("rejects newline in signature", () => {
    expect(() => SignatureParser.parse("transfer\n(uint256)")).toThrow(CallciumError);
  });

  test("rejects a non-ASCII character in the function name", () => {
    // Every character outside ASCII fails the same alphanumeric test the name already applies.
    expectErrorCode(() => SignatureParser.parse("tránsfer(uint256)"), "INVALID_FUNCTION_NAME");
  });

  test("rejects an empty function name", () => {
    expectErrorCode(() => SignatureParser.parse("(uint256)"), "INVALID_FUNCTION_NAME");
  });

  test("leaves a non-ASCII character between the parentheses to the type parser", () => {
    // The selector hashes the signature's UTF-8 bytes, which is the preimage the contract hashes.
    const result = SignatureParser.parse("foo(é)");
    expect(result.selector).toBe("0x4cc3fd17");
    expect(result.types).toBe("é");
  });

  test("accepts underscore-prefixed function name", () => {
    const result = SignatureParser.parse("_approve(address,uint256)");
    expect(result.types).toBe("address,uint256");
    expect(result.selector).toHaveLength(10);
  });

  test("rejects special characters in function name", () => {
    expect(() => SignatureParser.parse("foo@bar(uint256)")).toThrow(CallciumError);
  });

  test("rejects missing closing parenthesis", () => {
    expect(() => SignatureParser.parse("foo(uint256")).toThrow(CallciumError);
  });

  test("rejects function name starting with a digit", () => {
    expect(() => SignatureParser.parse("1foo(uint256)")).toThrow(CallciumError);
  });
});
