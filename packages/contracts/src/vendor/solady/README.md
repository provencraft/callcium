# Vendored Solady

Source: https://github.com/Vectorized/solady
Version: `v0.1.26`
License: MIT (see `LICENSE`)

## Contents

| File | Upstream path |
|---|---|
| `utils/DynamicBufferLib.sol` | `src/utils/DynamicBufferLib.sol` |
| `utils/EfficientHashLib.sol` | `src/utils/EfficientHashLib.sol` |
| `utils/LibBytes.sol` | `src/utils/LibBytes.sol` |
| `utils/LibSort.sol` | `src/utils/LibSort.sol` |
| `utils/SSTORE2.sol` | `src/utils/SSTORE2.sol` |

## Rules

- Files are copied verbatim from the upstream tag. SPDX headers and `@author Solady` attribution are preserved.
- Do not modify these files. Patches belong upstream.
- Vendored types must not appear in any external or public function signature of Callcium contracts.

## Refresh

1. Bump the version tag above.
2. Replace each file under `utils/` with its counterpart from the new upstream tag.
3. Replace `LICENSE` if upstream changed it.
4. Diff against the upstream tag, not the previous vendored version.
5. Run `bun run test` in the contracts package.