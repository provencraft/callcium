import Corpus
import Lean.Data.Json

/-!
# Conformance vectors

Runs the conformance vectors against the model.

- A descriptor vector agrees when `Descriptor.wellFormed` accepts its blob exactly when its `error` is empty. Validity
  and decoding are no tier's check.
- A storage vector agrees when `Policy.validate` accepts its blob exactly when its `error` is empty. An accepted blob is
  `canonical` exactly when encoding the formula it decodes to, over the signature it embeds, reproduces the blob.
- An encoding vector agrees when storage accepts its `input` and encoding the formula it decodes to, over the signature
  it embeds, gives its `expected` blob. An empty `expected` means the encoder refuses the formula.
- An enforcement vector agrees when `Policy.outcome` on its calldata and context is its `expected` verdict, or the abort
  its `expectedError` names. Such a vector's blob passes storage validation. An `integrityError` vector agrees when
  storage rejects the blob and enforcement aborts without a violation code. Its `context` sets every property the policy
  reads, zero included. Group-local codes reach the model as the fail verdict. Of `violations`, only the shape is
  checked: one group-local code per group on a fail, none otherwise.
- A validation vector that expects PV-9 issues, or none, agrees when the PV-9 oracle reads its blob and gives its issues
  (`validationIssues?`). The vector is skipped when its blob is not canonical, when the oracle does not read it, or when
  it expects another invariant's issue. The run fails when every vector is skipped.

Run the vectors from `spec/lean` with this command.

```
lake exe vectors
```

The five paths default to `spec/vectors/descriptors.json`, `spec/vectors/policies.json`, `spec/vectors/encoding.json`,
`spec/vectors/enforcement.json` and `spec/vectors/validation.json`. The executable exits nonzero on any disagreement,
unreadable vector, or empty file.
-/

open Callcium Callcium.Corpus Lean

/-- The bytes a vector's hex field spells. -/
def bytesField (vector : Json) (name : String) : Except String Bytes := do
  match parseHex (← vector.getObjValAs? String name) with
  | some bytes => pure bytes
  | none => throw s!"{name} is not hex"

/-- Whether a vector expects acceptance: its `error` is empty. -/
def accepts (vector : Json) : Except String Bool :=
  return (← vector.getObjValAs? String "error").isEmpty

/-! ## Storage -/

/-- Whether the blob is the encoding of the formula it decodes to, over the signature it embeds. -/
def canonical (blob : Bytes) : Bool :=
  reencode blob == some blob

/-- None when the descriptor vector agrees, else what disagrees. -/
def checkDescriptor (vector : Json) : Except String (Option String) := do
  let accepted := Descriptor.wellFormed (← bytesField vector "blob")
  return if accepted == (← accepts vector) then none else some s!"wellFormed is {accepted}"

/-- None when the storage vector agrees, else what disagrees. -/
def checkStorage (vector : Json) : Except String (Option String) := do
  let blob ← bytesField vector "blob"
  let accepted := Policy.validate blob
  if accepted != (← accepts vector) then return some s!"validate is {accepted}"
  if !accepted then return none
  let isCanonical := canonical blob
  return if isCanonical == (← vector.getObjValAs? Bool "canonical") then none else some s!"canonical is {isCanonical}"

/-! ## Encoding -/

/-- None when the encoding vector agrees, else what disagrees. -/
def checkEncoding (vector : Json) : Except String (Option String) := do
  let input ← bytesField vector "input"
  unless Policy.validate input do return some "input fails storage validation"
  let some encoded := reencode input | return some "input does not decode"
  return if encoded == (← bytesField vector "expected") then none else some s!"encodes to {hexOf encoded}"

/-! ## Enforcement -/

/-- The context property a vector's context field sets. -/
def propertyOf? : String → Option PropertyId
  | "msgSender" => some CTX_MSG_SENDER
  | "msgValue" => some CTX_MSG_VALUE
  | "blockTimestamp" => some CTX_BLOCK_TIMESTAMP
  | "blockNumber" => some CTX_BLOCK_NUMBER
  | "chainId" => some CTX_CHAIN_ID
  | "txOrigin" => some CTX_TX_ORIGIN
  | "baseFee" => some CTX_BASE_FEE
  | "gasPrice" => some CTX_GAS_PRICE
  | _ => none

/-- The properties a vector's `context` sets, each to the word given. -/
def contextOf (vector : Json) : Except String (List (PropertyId × Word)) := do
  let some fields := (vector.getObjVal? "context").toOption | return []
  (← fields.getObj?).toList.mapM fun (name, value) => do
    let some property := propertyOf? name | throw s!"unknown context field {name}"
    let some bytes := parseHex (← value.getStr?) | throw s!"context field {name} is not hex"
    return (property, BitVec.ofNat 256 (beNat bytes))

/-- The violation codes that fail a group. -/
def groupLocalCodes : List String :=
  ["VALUE_MISMATCH", "ARRAY_INDEX_OUT_OF_BOUNDS", "MISSING_CONTEXT", "QUANTIFIER_NO_MATCH"]

/-- The outcome a vector expects, from exactly one of `expected`, `expectedError` and `integrityError`. -/
def expectedOutcome (vector : Json) : Except String Outcome := do
  let present := ["expected", "expectedError", "integrityError"].filter fun name =>
    (vector.getObjVal? name).toOption.isSome
  match present with
  | ["expected"] => return .ofBool (← vector.getObjValAs? Bool "expected")
  | ["expectedError"] =>
    let code ← vector.getObjValAs? String "expectedError"
    let some reason := Abort.ofCode? code | throw s!"unknown abort code {code}"
    return .abort reason
  | ["integrityError"] =>
    if ← vector.getObjValAs? Bool "integrityError" then return .abort .unsupportedPolicy
    throw "integrityError is false"
  | _ => throw s!"expects {present}, not one outcome"

/-- None when the vector's `violations` fits its outcome. Otherwise the result names what does not fit. A fail lists one
group-local code per group, since every group failed. No other outcome lists any. -/
def checkViolations (vector : Json) (expected : Outcome) (groupCount : Nat) : Except String (Option String) := do
  let codes ← match (vector.getObjVal? "violations").toOption with
    | some field => some <$> fromJson? (α := Array String) field
    | none => pure none
  match codes, expected with
  | some codes, .fail =>
    if codes.size != groupCount then return some s!"{codes.size} violations for {groupCount} groups"
    return (codes.find? (!groupLocalCodes.contains ·)).map (s!"{·} is not a group-local code")
  | none, .fail => return some "violations missing"
  | some _, _ => return some "violations on an outcome other than fail"
  | none, _ => return none

/-- None when the enforcement vector agrees, else what disagrees. -/
def checkEnforcement (vector : Json) : Except String (Option String) := do
  let blob ← bytesField vector "blob"
  let expected ← expectedOutcome vector
  let entries ← contextOf vector
  let parsed := Policy.parse blob
  match parsed, expected with
  | none, .abort .unsupportedPolicy => pure ()
  | none, _ => return some "blob fails storage validation"
  | some _, .abort .unsupportedPolicy => return some "blob passes storage validation"
  | some policy, _ =>
    for property in policy.groups.flatten.flatMap ruleReads do
      unless entries.any (·.1 == property) do return some s!"context lacks property {property}"
  if let some problem ← checkViolations vector expected ((parsed.map (·.groups.length)).getD 0) then
    return some problem
  let outcome := Policy.outcome blob (← bytesField vector "callData") fun property => entries.lookup property
  return if outcome == expected then none else some s!"outcome {reprStr outcome}, expected {reprStr expected}"

/-! ## Validation -/

/-- The codes of PV-9 issues. -/
def pv9Codes : List String :=
  ["CONTRADICTORY_RULE", "REDUNDANT_RULE", "VACUOUS_RULE", "DOMINATED_BOUND", "DOMINATED_LENGTH_BOUND"]

/-- The issues the oracle finds on a validation vector's blob, and those the vector expects, as corpus lines spell them.
The result is none when the vector expects another invariant's issue, or when its blob is not canonical or the oracle
does not read it.
-/
def validationVerdicts? (vector : Json) : Except String (Option (String × String)) := do
  let issues ← (← vector.getObjValAs? (Array Json) "issues").toList.mapM fun issue =>
    return ((← issue.getObjValAs? String "code"), (← issue.getObjValAs? String "location"))
  let blob ← bytesField vector "blob"
  -- The oracle's locations are positions in the blob, which are the normal form's only in a canonical blob.
  unless issues.all (pv9Codes.contains ·.1) && canonical blob do return none
  let some found := (Policy.parse blob).bind validationIssues? | return none
  let expected := if issues.isEmpty then "-"
    else ",".intercalate (issues.map fun (code, location) => s!"{code}@{location}")
  return some (issuesField found, expected)

/-- None when the validation vector agrees or the oracle does not check it, else what disagrees. -/
def checkValidation (vector : Json) : Except String (Option String) := do
  let some (found, expected) ← validationVerdicts? vector | return none
  return if canonicalVerdict found == canonicalVerdict expected then none else some s!"oracle gives {found}"

/-! ## Files -/

/-- Runs `check` on every vector in the file at `path`. It prints each disagreement and returns the number of vectors
and the number of failures. -/
def runFile (path : String) (check : Json → Except String (Option String)) : IO (Nat × Nat) := do
  let vectors ← IO.ofExcept ((Json.parse (← IO.FS.readFile path)).bind Json.getArr?)
  let mut failures := 0
  for vector in vectors do
    let id := (vector.getObjValAs? String "id").toOption.getD "?"
    match check vector with
    | .ok none => pure ()
    | .ok (some disagreement) =>
      IO.eprintln s!"{path} {id}: {disagreement}"
      failures := failures + 1
    | .error problem =>
      IO.eprintln s!"{path} {id}: unreadable: {problem}"
      failures := failures + 1
  if vectors.isEmpty then
    IO.eprintln s!"{path}: no vectors"
    failures := 1
  IO.println s!"{path}: {vectors.size} vectors, {failures} failing"
  return (vectors.size, failures)

/-- Checks the descriptor, storage, encoding, enforcement and validation vector files at the given paths. Without
arguments, it checks the default paths. -/
def main (args : List String) : IO UInt32 := do
  let defaults := ["../vectors/descriptors.json", "../vectors/policies.json", "../vectors/encoding.json",
    "../vectors/enforcement.json", "../vectors/validation.json"]
  let [descriptors, policies, encoding, enforcement, validation] := if args.isEmpty then defaults else args | do
    IO.eprintln "usage: vectors [<descriptors> <policies> <encoding> <enforcement> <validation>]"
    return 2
  let results ← [(descriptors, checkDescriptor), (policies, checkStorage), (encoding, checkEncoding),
    (enforcement, checkEnforcement), (validation, checkValidation)].mapM fun (path, check) => runFile path check
  let vectors ← IO.ofExcept ((Json.parse (← IO.FS.readFile validation)).bind Json.getArr?)
  let checked := vectors.toList.countP fun vector => (validationVerdicts? vector).toOption.join.isSome
  IO.println s!"{validation}: {checked} checked against the PV-9 oracle"
  return if results.all (·.2 == 0) && 0 < checked then 0 else 1
