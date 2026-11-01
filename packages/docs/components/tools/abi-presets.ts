import { parseAbi } from "viem";

/** Standard token interfaces from forge-std's `IERC20` and `IERC721` with its inherited `IERC165`. */
export const abiPresets = [
  {
    name: "ERC20",
    abi: parseAbi([
      "function totalSupply() view returns (uint256)",
      "function balanceOf(address account) view returns (uint256)",
      "function transfer(address to, uint256 amount) returns (bool)",
      "function allowance(address owner, address spender) view returns (uint256)",
      "function approve(address spender, uint256 amount) returns (bool)",
      "function transferFrom(address from, address to, uint256 amount) returns (bool)",
      "function name() view returns (string)",
      "function symbol() view returns (string)",
      "function decimals() view returns (uint8)",
    ]),
  },
  {
    name: "ERC721",
    abi: parseAbi([
      "function supportsInterface(bytes4 interfaceId) view returns (bool)",
      "function balanceOf(address owner) view returns (uint256)",
      "function ownerOf(uint256 tokenId) view returns (address)",
      "function safeTransferFrom(address from, address to, uint256 tokenId, bytes data) payable",
      "function safeTransferFrom(address from, address to, uint256 tokenId) payable",
      "function transferFrom(address from, address to, uint256 tokenId) payable",
      "function approve(address approved, uint256 tokenId) payable",
      "function setApprovalForAll(address operator, bool approved)",
      "function getApproved(uint256 tokenId) view returns (address)",
      "function isApprovedForAll(address owner, address operator) view returns (bool)",
    ]),
  },
];
