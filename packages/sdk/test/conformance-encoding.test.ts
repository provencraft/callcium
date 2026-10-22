import { describe, expect, test } from "vitest";

import rawVectors from "../../../spec/vectors/encoding.json";
import { hex, reencode } from "./helpers";

///////////////////////////////////////////////////////////////////////////
// Vector types
///////////////////////////////////////////////////////////////////////////

type Vector = {
  id: string;
  description: string;
  input: string;
  expected: string;
};

const vectors: Vector[] = rawVectors;

///////////////////////////////////////////////////////////////////////////
// Normalized encodings
///////////////////////////////////////////////////////////////////////////

describe("Encoding conformance vectors - PolicyCoder.encode", () => {
  for (const vector of vectors) {
    test(`${vector.id}: ${vector.description}`, () => {
      expect(reencode(hex(vector.input))).toBe(hex(vector.expected));
    });
  }
});
