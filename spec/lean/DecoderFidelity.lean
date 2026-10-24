import Callcium.Abi.DecodeStrict
import Callcium.Descriptor.Codec
import Std.Data.HashMap

/-!
# Decoder fidelity

Checks `AbiType.decodeSolc` against how Solidity reads function parameters. `memory` parameters (`Eager`) and `calldata`
parameters read element by element (`Access`). The corpus of their readings contains one line per calldata a reader
accepted, in the form `reader descriptor calldata encoding`. `encoding` is Solidity's encoding of the arguments the
reader read. A line agrees when `decodeSolc` reads, from byte 4 on, values that encode to the same bytes. On accepted
input, every word passed Solidity's validator. Equal encodings are therefore equal values.

The Foundry script `packages/contracts/script/LeanDecoderFidelity.s.sol` writes the corpus from a number of cases per
shape, drawn from Foundry's random cheatcodes. The commands below run from `spec/lean`.

```
(cd ../../packages/contracts && FOUNDRY_FUZZ_SEED=<seed> bun run corpus:decoder-fidelity 5000)
lake build decoder-fidelity
(ulimit -v 8000000; .lake/build/bin/decoder-fidelity ../../packages/contracts/out/decoder-fidelity.txt)
```

A model that reads a length no reader read builds a value that size. The memory limit makes that a failed run. The
program exits nonzero on any disagreement or unreadable line.
-/

open Callcium

/-- Lines read, lines whose data is not canonical, and disagreements, for one reader. -/
structure Tally where
  lines : Nat := 0
  nonCanonical : Nat := 0
  disagreements : Nat := 0

/-- Whether `decodeSolc` reads the values the line's encoding contains, and whether the line's data is canonical. The
result is none for an unreadable line. -/
def checkLine (fields : List String) : Option (Bool × Bool) := do
  let [_, descriptorHex, callDataHex, encodingHex] := fields | none
  let types ← Descriptor.decode (← parseHex descriptorHex)
  let callData ← parseHex callDataHex
  let encoding ← parseHex encodingHex
  let abiType := AbiType.tuple types
  some (abiType.encode (abiType.decodeSolc callData 4) == encoding, (abiType.decodeStrict callData 4).isSome)

/-- The tallies per reader of the lines left in `stream`, printing the first five disagreements. -/
partial def readLines (stream : IO.FS.Stream) (tallies : Std.HashMap String Tally) (shown : Nat) :
    IO (Std.HashMap String Tally) := do
  let line ← stream.getLine
  if line.isEmpty then return tallies
  let line := line.trimAsciiEnd.toString
  let fields := line.splitOn " "
  let reader := fields.headD ""
  match checkLine fields with
  | none =>
    IO.eprintln s!"unreadable line: {(line.take 200).toString}"
    let unreadable := tallies.getD "unreadable" {}
    readLines stream (tallies.insert "unreadable" { unreadable with lines := unreadable.lines + 1 }) shown
  | some (agrees, canonical) =>
    let tally := tallies.getD reader {}
    let tally := { tally with
      lines := tally.lines + 1
      nonCanonical := tally.nonCanonical + (if canonical then 0 else 1)
      disagreements := tally.disagreements + (if agrees then 0 else 1) }
    let shown ← if agrees || shown ≥ 5 then pure shown else do
      IO.eprintln s!"disagreement: {line}"
      pure (shown + 1)
    readLines stream (tallies.insert reader tally) shown

/-- Checks the corpus at the one path argument and prints a tally per reader. -/
def main (args : List String) : IO UInt32 := do
  let [path] := args | do
    IO.eprintln "usage: decoder-fidelity <corpus>"
    return 2
  let tallies ← readLines (.ofHandle (← IO.FS.Handle.mk path .read)) {} 0
  let mut failed := tallies.contains "unreadable"
  for (reader, tally) in tallies.toList.mergeSort (·.1 < ·.1) do
    IO.println s!"{reader}: {tally.lines} lines, {tally.nonCanonical} not canonical, {tally.disagreements} disagree"
    failed := failed || tally.disagreements > 0
  return if failed then 1 else 0
