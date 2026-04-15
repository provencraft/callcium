import type { ConstraintInput } from "@/tools/policy-builder";

export type BuilderExample = {
  name: string;
  signature: string;
  selectorless?: boolean;
  constraints: { groupIndex: number; config: ConstraintInput }[];
};

export const EXAMPLES: BuilderExample[] = [
  {
    name: "Restrict spender",
    signature: "approve(address,uint256)",
    constraints: [
      {
        groupIndex: 0,
        config: {
          scope: "calldata",
          path: [0],
          rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
        },
      },
    ],
  },
  {
    name: "Cap transfer amount",
    signature: "approve(address,uint256)",
    constraints: [
      {
        groupIndex: 0,
        config: {
          scope: "calldata",
          path: [0],
          rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
        },
      },
      {
        groupIndex: 0,
        config: {
          scope: "calldata",
          path: [1],
          rules: [{ operator: "lte", values: [1000000000000n] }],
        },
      },
    ],
  },
  {
    name: "Sender allowlist + cap",
    signature: "transfer(address,uint256)",
    constraints: [
      {
        groupIndex: 0,
        config: {
          scope: "context",
          contextProperty: "msgSender",
          rules: [{ operator: "eq", values: ["0xd8da6bf26964af9d7eed9e03e53415d37aa96045"] }],
        },
      },
      {
        groupIndex: 0,
        config: {
          scope: "calldata",
          path: [1],
          rules: [{ operator: "lte", values: [5000000000000000000n] }],
        },
      },
    ],
  },
  {
    name: "Multi-path approval",
    signature: "approve(address,uint256)",
    constraints: [
      {
        groupIndex: 0,
        config: {
          scope: "calldata",
          path: [0],
          rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
        },
      },
      {
        groupIndex: 0,
        config: {
          scope: "calldata",
          path: [1],
          rules: [{ operator: "lte", values: [1000000000000000000n] }],
        },
      },
      {
        groupIndex: 1,
        config: {
          scope: "calldata",
          path: [0],
          rules: [{ operator: "eq", values: ["0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45"] }],
        },
      },
      {
        groupIndex: 1,
        config: {
          scope: "calldata",
          path: [1],
          rules: [{ operator: "lte", values: [100000000000000000n] }],
        },
      },
    ],
  },
  {
    name: "Capped approval",
    signature: "approve(address,uint256)",
    constraints: [
      {
        groupIndex: 0,
        config: {
          scope: "calldata",
          path: [0],
          rules: [{ operator: "eq", values: ["0x1111111254eeb25477b68fb85ed929f73a960582"] }],
        },
      },
      {
        groupIndex: 0,
        config: {
          scope: "calldata",
          path: [1],
          rules: [
            { operator: "gte", values: [1000000n] },
            { operator: "lte", values: [1000000000000n] },
          ],
        },
      },
    ],
  },
];
