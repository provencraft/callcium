import { describe, expect, test } from "vitest";

import { SignatureParser } from "../src/signature";
import { expectErrorCode } from "./helpers";

describe("SignatureParser", () => {
  test("parses transfer(address,uint256)", () => {
    const result = SignatureParser.parse("transfer(address,uint256)");
    expect(result.selector).toBe("0xa9059cbb");
    expect(result.types).toBe("address,uint256");
  });

  test("accepts underscores and digits in the function name", () => {
    const result = SignatureParser.parse("_set_owner2(address)");
    expect(result.types).toBe("address");
  });

  test("leaves a non-ASCII character between the parentheses to the type parser", () => {
    // The selector hashes the signature's UTF-8 bytes.
    const result = SignatureParser.parse("foo(é)");
    expect(result.selector).toBe("0x4cc3fd17");
    expect(result.types).toBe("é");
  });

  test("rejects a signature too short to hold a name and both parentheses", () => {
    expectErrorCode(() => SignatureParser.parse("()"), "MALFORMED_SIGNATURE");
  });

  test("rejects each whitespace character", () => {
    for (const whitespace of [" ", "\t", "\n", "\r"]) {
      expectErrorCode(
        () => SignatureParser.parse(`transfer(address,${whitespace}uint256)`),
        "SIGNATURE_CONTAINS_WHITESPACE",
      );
    }
  });

  test("rejects a signature with no opening parenthesis", () => {
    expectErrorCode(() => SignatureParser.parse("transfer)"), "MALFORMED_SIGNATURE");
  });

  test("rejects missing closing parenthesis", () => {
    expectErrorCode(() => SignatureParser.parse("foo(uint256"), "MALFORMED_SIGNATURE");
  });

  test("rejects function name starting with a digit", () => {
    expectErrorCode(() => SignatureParser.parse("1foo(uint256)"), "INVALID_FUNCTION_NAME");
  });

  test("rejects a non-ASCII character in the function name", () => {
    expectErrorCode(() => SignatureParser.parse("tránsfer(uint256)"), "INVALID_FUNCTION_NAME");
  });
});
