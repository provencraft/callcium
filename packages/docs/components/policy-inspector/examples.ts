import type { Hex } from "@callcium/sdk";
import type { Abi } from "viem";

export type PolicyExample = {
  /// Dropdown label and banner text.
  name: string;
  /// Hex-encoded policy blob.
  blob: Hex;
  /// Optional ABI for named parameter resolution.
  abi?: Abi;
};

const approveAbi: Abi = [
  {
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
  },
];

const safeTransferFromAbi: Abi = [
  {
    type: "function",
    name: "safeTransferFrom",
    inputs: [
      { name: "from", type: "address" },
      { name: "to", type: "address" },
      { name: "tokenId", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
];

const transferAbi: Abi = [
  {
    type: "function",
    name: "transfer",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
  },
];

const executeAbi: Abi = [
  {
    type: "function",
    name: "execute",
    inputs: [{ name: "proposalId", type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
];

const submitAbi: Abi = [
  {
    type: "function",
    name: "submit",
    inputs: [
      {
        name: "request",
        type: "tuple",
        components: [
          { name: "recipient", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "data", type: "bytes" },
        ],
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
];

export const EXAMPLES: PolicyExample[] = [
  {
    name: "Restrict spender",
    blob: "0x01095ea7b300040102401f010001000000490049010100000700400000000000000000000000001111111254eeb25477b68fb85ed929f73a96058200000000000000000000000068b3465833fb72a70ecdf485e0e4c7bd8665fc45",
    abi: approveAbi,
  },
  {
    name: "Cap amount",
    blob: "0x01095ea7b300040102401f010001000000490049010100010600400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000e8d4a51000",
    abi: approveAbi,
  },
  {
    name: "Allowed token IDs",
    blob: "0x0142842e0e0005010340401f010001000000690069010100020700600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000064",
    abi: safeTransferFromAbi,
  },
  {
    name: "Restrict sender",
    blob: "0x01a9059cbb00040102401f01000100000029002900010000010020000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045",
    abi: transferAbi,
  },
  {
    name: "Timelock",
    blob: "0x01fe0d94c1000301011f01000100000029002900010002020020000000000000000000000000000000000000000000000000000000006955b900",
    abi: executeAbi,
  },
  {
    name: "Struct field",
    blob: "0x01c037dace000b0101900000090003401f700100010000002b002b010200000000010020000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045",
    abi: submitAbi,
  },
  {
    name: "Multi-group OR",
    blob: "0x01095ea7b300040102401f0200020000005200290101000001002000000000000000000000000068b3465833fb72a70ecdf485e0e4c7bd8665fc45002901010001050020000000000000000000000000000000000000000000000000000000746a5288000002000000520029010100000100200000000000000000000000001111111254eeb25477b68fb85ed929f73a960582002901010001050020000000000000000000000000000000000000000000000000000000174876e800",
    abi: approveAbi,
  },
  {
    name: "Selectorless",
    blob: "0x110000000000040102401f01000100000029002901010000010020000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045",
  },
];
