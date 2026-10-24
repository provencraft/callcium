import Callcium.Enforce
import Std.Data.HashMap

/-!
# Differential corpora

The line formats the differential checks share, and the check that runs over them. `generate-corpus` writes a corpus
with the model's verdicts. An implementation replays it and writes the same lines with its own verdicts. A checker
recomputes the model's verdict on every line the implementation wrote.

- Enforcement: `id blob callData context outcome`. `context` lists the context properties from `CTX_MSG_SENDER` to
  `CTX_MAX`, comma separated, each a 32-byte word or `-` where the call does not provide it. `outcome` is `pass`,
  `fail`, the violation code of an abort, or `integrity` for an abort that carries no code.
- Encoding: `id blob encoded`. `blob` is a policy written in any spelling. `encoded` is the blob that the encoder gives
  for the formula the policy states, over the signature the policy embeds. `0x` marks a formula the encoder refuses.
- Storage: `id blob verdict`, `verdict` being `accept` or `reject`.
- Validation: `id blob issues`. `issues` lists the PV-9 issues of a canonical blob as `CODE@g.r`, or as `CODE@g.r.b` for
  a test in a loop's body. The items are comma separated in any order, or `-` marks none.

Hex fields are `0x`-prefixed and lowercase. An implementation can rewrite a line's calldata and context, and can write
several lines per `id`. It never rewrites the blob.
-/

namespace Callcium

/-! ## Fields -/

/-- The lowercase hex digit of a value below 16. -/
def hexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat ('0'.toNat + value) else Char.ofNat ('a'.toNat + value - 10)

/-- The `0x`-prefixed lowercase hex spelling of `bytes`. -/
def hexOf (bytes : Bytes) : String :=
  bytes.foldl (fun text byte => (text.push (hexDigit (byte.toNat / 16))).push (hexDigit (byte.toNat % 16))) "0x"

/-- The violation code of an abort, or none for a blob the enforcer does not evaluate, which carries no code. -/
def Abort.code? : Abort → Option String
  | .missingSelector => some "MISSING_SELECTOR"
  | .selectorMismatch => some "SELECTOR_MISMATCH"
  | .calldataOutOfBounds => some "CALLDATA_OUT_OF_BOUNDS"
  | .nonCanonicalValue => some "NON_CANONICAL_VALUE"
  | .quantifierLimitExceeded => some "QUANTIFIER_LIMIT_EXCEEDED"
  | .unsupportedPolicy => none

/-- The abort a violation code names. -/
def Abort.ofCode? (code : String) : Option Abort :=
  [Abort.missingSelector, .selectorMismatch, .calldataOutOfBounds, .nonCanonicalValue, .quantifierLimitExceeded].find?
    (·.code? == some code)

/-- An outcome as a corpus line spells it. -/
def Outcome.name : Outcome → String
  | .pass => "pass"
  | .fail => "fail"
  | .abort reason => reason.code?.getD "integrity"

namespace Corpus

/-- The context property an operand reads. -/
def operandReads : Operand → List PropertyId
  | .context property => [property]
  | .constant _ => []

/-- The context properties a test reads. -/
def testReads : CompiledTest → List PropertyId
  | .contextTest property operator => property :: operandReads operator.operand
  | .test _ _ operator => operandReads operator.operand

/-- The context properties a rule reads. -/
def ruleReads : CompiledRule → List PropertyId
  | .test compiled => testReads compiled
  | .loop _ _ _ body => body.flatMap testReads

/-- A context as a corpus line spells it: one field per property up to `CTX_MAX`. -/
def contextField (context : Context) : String :=
  ",".intercalate ((List.range (CTX_MAX + 1)).map fun property =>
    match context property with
    | some word => hexOf (beBytes WORD_SIZE word.toNat)
    | none => "-")

/-- The context a corpus field spells, or none unless the field contains one item per property up to `CTX_MAX`. -/
def parseContext (field : String) : Option Context := do
  let words ← (field.splitOn ",").mapM fun entry =>
    if entry == "-" then some none else (parseHex entry).map fun bytes => some (BitVec.ofNat 256 (beNat bytes))
  if words.length != CTX_MAX + 1 then none
  return fun property => (words[property]?).join

/-! ## Encoding -/

/-- `Policy.encode` of the formula the blob states, over the signature the blob embeds. The result is empty where the
encoder refuses the formula. The result is none unless the blob passes storage validation and its descriptor decodes. -/
def reencode (blob : Bytes) : Option Bytes := do
  let policy ← Policy.parse blob
  let params ← Descriptor.decode policy.desc
  return Policy.encode ⟨policy.selector, params⟩ policy.formula

/-! ## Validation -/

/-- A PV-9 issue has a code, the indices of the test it names (group, rule, and the test's position within a loop's
body), and its operator. -/
structure Issue where
  code : String
  location : List Nat
  operator : Operator

/-- An issue as a corpus line spells it. -/
def Issue.key (issue : Issue) : String :=
  s!"{issue.code}@{".".intercalate (issue.location.map toString)}"

/-- Issues as a corpus line spells them. -/
def issuesField (issues : List Issue) : String :=
  if issues.isEmpty then "-" else ",".intercalate (issues.map Issue.key)

/-- Every value of an 8-bit type in ascending order, two's complement for `int8`, or none for any other type. -/
def valuesOf? : WordType → Option (List Word)
  | .uint width => if width.index = 0 then some ((List.range 256).map (BitVec.ofNat 256)) else none
  | .int width =>
    if width.index = 0 then some ((List.range 256).map fun value => BitVec.ofInt 256 (Int.ofNat value - 128))
    else none
  | .fixedBytes width =>
    if width.index = 0 then some ((List.range 256).map fun value => BitVec.ofNat 256 value <<< 248) else none
  | .bool => some [0, 1]
  | _ => none

/-- The values a context operand takes against an 8-bit unsigned subject: absent, each subject value, and one above
them. A context operand compares by order or equality (PWF-22), so these stand for every context. -/
def contextClasses : List (Option Word) := none :: (List.range 257).map (some ∘ BitVec.ofNat 256)

/-- A test on a subject. It records its operator, its location, the property its operand reads, and whether it holds at
each value of the subject and each context class. A test reading no property has absence as its one class. -/
structure Literal where
  operator : Operator
  location : List Nat
  reads : Option PropertyId
  holds : Array (Array Bool)

/-- The test of `operator` on a subject taking `values`. -/
def Literal.of (values : List Word) (signed : Bool) (operator : Operator) (location : List Nat) : Literal :=
  let reads := match operator.operand with
    | .context property => some property
    | .constant _ => none
  let classes := if reads.isSome then contextClasses else [none]
  ⟨operator, location, reads, values.toArray.map fun value =>
    classes.toArray.map fun context => operator.holds (fun _ => context) (some (.word value signed))⟩

/-- Whether some value and context make each literal hold exactly when its polarity is true. A literal reads at most
one property, so the context is chosen property by property. -/
def satisfiable (valueCount : Nat) (literals : List (Literal × Bool)) : Bool :=
  let properties := (literals.filterMap (·.1.reads)).eraseDups
  (List.range valueCount).any fun value =>
    (literals.filter (·.1.reads.isNone)).all (fun (literal, polarity) => literal.holds[value]![0]! == polarity) &&
    properties.all fun property =>
      let reading := literals.filter (·.1.reads == some property)
      (List.range contextClasses.length).any fun context =>
        reading.all fun (literal, polarity) => literal.holds[value]![context]! == polarity

/-- The sides a test bounds by a constant: from below for `GT`, `GTE` and `BETWEEN`, from above for `LT`, `LTE` and
`BETWEEN`, none when negated. -/
def boundSides : Operator → Bool × Bool
  | ⟨false, .gt, .constant _⟩ | ⟨false, .gte, .constant _⟩ => (true, false)
  | ⟨false, .lt, .constant _⟩ | ⟨false, .lte, .constant _⟩ => (false, true)
  | ⟨false, .between, .constant _⟩ => (true, true)
  | _ => (false, false)

/-- The PV-9 issues of the tests on one subject, in normal-form order. If the tests become unsatisfiable together, the
issue is the test at which they first do so. Otherwise, the issues are three groups. The first group is each test that
holds for every value and context. The second group is each other test that the rest imply. The third group is each
bound among the tests not yet named that is looser than the tightest on its side. -/
def subjectIssues (valueCount : Nat) (literals : List Literal) : List Issue :=
  let issue (code : String) (literal : Literal) : Issue := ⟨code, literal.location, literal.operator⟩
  let contradiction := (List.range literals.length).find? fun index =>
    !satisfiable valueCount ((literals.take (index + 1)).map (·, true))
  match contradiction with
  | some index => (literals[index]?).toList.map (issue "CONTRADICTORY_RULE")
  | none =>
    let named := literals.zipIdx.map fun (literal, index) =>
      if !satisfiable valueCount [(literal, false)] then some (issue "VACUOUS_RULE" literal)
      else if !satisfiable valueCount ((literals.eraseIdx index).map (·, true) ++ [(literal, false)]) then
        some (issue "REDUNDANT_RULE" literal)
      else none
    let unnamed := (literals.zip named).filterMap fun (literal, name) => if name.isNone then some literal else none
    -- Values ascend in the type's order, so a bound is the position of the least or greatest value meeting the test.
    let lowest (literal : Literal) := ((List.range valueCount).find? (literal.holds[·]![0]!)).getD 0
    let highest (literal : Literal) := ((List.range valueCount).reverse.find? (literal.holds[·]![0]!)).getD 0
    let tightestLower := ((unnamed.filter fun literal => (boundSides literal.operator).1).map lowest).foldl max 0
    let tightestUpper :=
      ((unnamed.filter fun literal => (boundSides literal.operator).2).map highest).foldl min valueCount
    let dominated := unnamed.filter fun literal =>
      let (lower, upper) := boundSides literal.operator
      (lower && lowest literal < tightestLower) || (upper && tightestUpper < highest literal)
    named.filterMap id ++ dominated.map (issue "DOMINATED_BOUND")

/-- The PV-9 issues of the tests of one rule list, each with its location, subject by subject. The result is none for a
context test. It is also none for a subject of any type but `uint8`, `int8`, `bytes1` and `bool`. It is also none for a
context operand on a signed or non-integer subject. -/
def testIssues? (tests : List (CompiledTest × List Nat)) : Option (List Issue) := do
  let entries ← tests.mapM fun
    | (.test path hint operator, location) => some (path, hint, operator, location)
    | (.contextTest .., _) => none
  let issues ← (entries.map (·.1)).eraseDups.mapM fun path => do
    let onPath := entries.filter (·.1 == path)
    let (_, hint, _, _) ← onPath.head?
    let wordType ← WordType.ofCode? hint.typeCode
    let values ← valuesOf? wordType
    guard (wordType matches .uint _ || onPath.all fun (_, _, operator, _) => operator.operand matches .constant _)
    return subjectIssues values.length
      (onPath.map fun (_, _, operator, location) => Literal.of values wordType.signed operator location)
  return issues.flatten

/-- The PV-9 issues of a policy, group by group, with each group's root tests and each loop's body apart. The result is
none where `testIssues?` gives none. -/
def validationIssues? (policy : CompiledPolicy) : Option (List Issue) := do
  let groups ← policy.groups.zipIdx.mapM fun (rules, group) => do
    let root := rules.zipIdx.filterMap fun
      | (.test test, index) => some (test, [group, index])
      | (.loop .., _) => none
    let bodies := rules.zipIdx.filterMap fun
      | (.loop _ _ _ body, index) => some (body.zipIdx.map fun (test, position) => (test, [group, index, position]))
      | (.test _, _) => none
    return (← (root :: bodies).mapM testIssues?).flatten
  return groups.flatten

/-! ## Checking -/

/-- A verdict with its comma-separated items sorted, so a verdict that lists items compares in any order. -/
def canonicalVerdict (verdict : String) : String :=
  ",".intercalate ((verdict.splitOn ",").mergeSort fun first second => !decide (second < first))

/-- The fields of a line. -/
def fieldsOf (line : String) : List String :=
  (line.splitOn " ").filter (!·.isEmpty)

/-- The blobs of a corpus by `id`, from lines of `fieldCount` fields. The result is none for an unreadable line. -/
def blobsOf (lines : List String) (fieldCount : Nat) : Option (Std.HashMap String Bytes) :=
  lines.foldlM (init := {}) fun blobs line => do
    let fields := fieldsOf line
    if fields.length != fieldCount then none
    return blobs.insert (← fields[0]?) (← parseHex (← fields[1]?))

/-- The non-empty lines of the file at `path`. -/
def readLines (path : String) : IO (List String) :=
  return ((← IO.FS.readFile path).splitOn "\n").filter (!·.trimAscii.isEmpty)

/-- Checks the implementation's corpus at `implementation` against the generated one at `generated`. Every line contains
`fieldCount` fields. Each line names a generated `id` and its blob. Each line ends in the verdict that `recompute` gives
on its fields between `id` and the verdict, with its comma-separated items in any order. Every generated `id` has a
line. Prints the first five disagreements and a tally. Exits nonzero on any disagreement, unreadable line, missing `id`,
or an empty corpus. -/
def check (fieldCount : Nat) (recompute : List String → Option String) (args : List String) : IO UInt32 := do
  let [generated, implementation] := args | do
    IO.eprintln "usage: <generated corpus> <implementation corpus>"
    return 2
  let some blobs := blobsOf (← readLines generated) fieldCount | do
    IO.eprintln s!"{generated}: unreadable line"
    return 1
  let mut seen : Std.HashSet String := {}
  let mut lines := 0
  let mut problems := 0
  for line in ← readLines implementation do
    lines := lines + 1
    let fields := fieldsOf line
    let middle := (fields.drop 1).take (fieldCount - 2)
    let problem := match fields[0]?, fields.getLast?, recompute middle with
      | some id, some verdict, some expected =>
        if fields.length != fieldCount then some "unreadable"
        else if blobs.get? id != (fields[1]?).bind parseHex then some "blob differs from the generated one"
        else if canonicalVerdict verdict != canonicalVerdict expected then some s!"model gives {expected}"
        else none
      | _, _, _ => some "unreadable"
    if let some id := fields[0]? then seen := seen.insert id
    if let some problem := problem then
      if problems < 5 then IO.eprintln s!"{problem}: {(line.take 300).toString}"
      problems := problems + 1
  let missing := (blobs.toList.filter fun (id, _) => !seen.contains id).length
  IO.println s!"{implementation}: {lines} lines, {problems} disagree or unreadable, {missing} of {blobs.size} ids missing"
  return if problems == 0 && missing == 0 && 0 < lines then 0 else 1

end Corpus

end Callcium
