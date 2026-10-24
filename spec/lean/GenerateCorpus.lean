import Corpus
import Lean.Data.Json

/-!
# Corpus generator

Writes the corpora of the enforcement, encoding, storage and validation differential checks. Each corpus carries the
model's verdicts, as `Corpus` defines them.

- Enforcement: random signatures, arguments and formulas within the core. Each formula is built from its signature's
  types, so it is well-formed and encodes (`Policy.WellFormed`). A case that is not well-formed or does not encode stops
  the run. The blob is `Policy.encode`. The calldata is the canonical encoding of the arguments (`AbiType.encode`). The
  context contains every property within the EVM's bounds. Operands lean on the values the arguments contain, so tests
  both pass and fail.
- Encoding: every enforcement formula respelled in the ways normalization undoes. The respellings are:
  - a negated comparison with a positive form.
  - a one-member set.
  - a context pair with the higher ID as subject.
  - an `ALL` loop split in two.
  - a context test moved into an `ANY` body.
  - a range split into its bounds.
  - a repeated rule or group.
  - the order reversed.
  The respelled formula is written compiled but not normalized, followed by `Policy.encode` of that formula. A
  respelling that is not well formed keeps the formula.
- Storage: every enforcement blob and every blob of `spec/vectors/policies.json`, each followed by mutants.
- Validation: random tests on an 8-bit subject, which is `uint8`, `int8`, `bytes1` or `bool`. The subject is one or two
  parameters or the elements of an array a loop walks. The comparisons are those that PV-5 admits on the type. Constants
  sit near a few values per case, masks have one to three bits, and on `uint8`, context operands come from one or two
  properties. The blob is `Policy.encode`, followed by its PV-9 issues (`validationIssues?`). A case with a
  contradiction is kept `CONTRADICTIONS_KEPT` percent of the time. There are `VALIDATION_CASES_PER_CASE` validation
  cases per enforcement case.

The tier-B coverage of Phase B's harvest is counted over the enforcement corpus. Verdicts are counted over the
enforcement corpus too. Each rewrite of normalization is counted over the encoding corpus. Each PV-9 issue is counted
over the validation corpus. The run exits nonzero when any count is zero. The commands below run from `spec/lean`.

```
lake exe generate-corpus <seed> <cases> <directory> [<policies.json>]
```

Writes `<directory>/enforcement.txt`, `<directory>/encoding.txt`, `<directory>/storage.txt` and
`<directory>/validation.txt`. The same seed and count give the same corpora.
-/

open Callcium Callcium.Corpus Lean

/-! ## Randomness -/

/-- A computation drawing from a pseudo-random generator. -/
abbrev Draw := StateM StdGen

/-- A number from `low` to `high`, both included. -/
def natBetween (low high : Nat) : Draw Nat :=
  modifyGet fun generator => randNat generator low high

/-- True with probability `chance` percent. -/
def percent (chance : Nat) : Draw Bool :=
  return (← natBetween 0 99) < chance

/-- One of `items`, which must be nonempty. -/
def oneOf {Item : Type} [Inhabited Item] (items : List Item) : Draw Item :=
  return items[← natBetween 0 (items.length - 1)]!

/-- `count` draws of `item`. -/
def listOf {Item : Type} (count : Nat) (item : Draw Item) : Draw (List Item) :=
  (List.range count).mapM fun _ => item

/-- A byte, zero a quarter of the time. -/
def byte : Draw UInt8 := do
  if ← percent 25 then return 0 else return UInt8.ofNat (← natBetween 0 255)

/-! ## Types and values -/

instance : Inhabited WordType := ⟨.bool⟩
instance : Inhabited AbiType := ⟨.bytes⟩
instance : Inhabited Value := ⟨.bytes []⟩
instance : Inhabited Comparison := ⟨.eq⟩
instance : Inhabited Quantifier := ⟨.all⟩

/-- The width of `bytes` bytes, for 1 to 32. -/
def widthOf (bytes : Nat) : ByteWidth := ⟨Fin.ofNat 32 (bytes - 1)⟩

/-- A word type. -/
def wordType : Draw WordType := do
  let width := widthOf (← oneOf [1, 2, 4, 8, 16, 20, 31, 32, ← natBetween 1 32])
  oneOf [.uint (widthOf 32), .uint (widthOf 32), .uint width, .int width, .int (widthOf 32), .address, .bool, .function,
    .fixedBytes width, .fixedBytes (widthOf 4)]

/-- A type nesting at most `depth` composite nodes. -/
def abiType : Nat → Draw AbiType
  | 0 => do
    let roll ← natBetween 0 99
    if roll < 70 then return .word (← wordType) else if roll < 85 then return .bytes else return .string
  | depth + 1 => do
    let roll ← natBetween 0 99
    if roll < 35 then abiType 0
    else if roll < 60 then return .dynamicArray (← abiType depth)
    else if roll < 80 then return .staticArray (← abiType depth) (← natBetween 1 3)
    else return .tuple (← listOf (← natBetween 1 3) (abiType depth))

/-- An unsigned number below `2 ^ bits`, often at an edge. -/
def unsigned (bits : Nat) : Draw Nat := do
  let top := 2 ^ bits
  oneOf [0, 1, 2, 3, top - 1, top / 2, top / 2 - 1, ← natBetween 0 (top - 1), ← natBetween 0 (top - 1)]

/-- A word of the type: a canonical encoding of one of its values. -/
def wordOf : WordType → Draw Word
  | .uint width => BitVec.ofNat 256 <$> unsigned width.bits
  | .int width => do
    let half : Int := 2 ^ (width.bits - 1)
    let random := (← natBetween 0 (2 * half.toNat - 1) : Int) - half
    return BitVec.ofInt 256 (← oneOf [0, 1, 2, -1, -2, half - 1, -half, random])
  | .address => BitVec.ofNat 256 <$> unsigned 160
  | .bool => BitVec.ofNat 256 <$> natBetween 0 1
  | .function => (BitVec.ofNat 256 · <<< 64) <$> unsigned 192
  | .fixedBytes width => (BitVec.ofNat 256 · <<< (256 - width.bits)) <$> unsigned width.bits

/-- A byte string, often at a word boundary. -/
def byteString : Draw (List UInt8) := do
  listOf (← oneOf [0, 1, 4, 31, 32, 33, ← natBetween 0 70]) byte

/-- A value of the type. 6 percent of dynamic arrays of words are one element past `MAX_QUANTIFIED_ARRAY_LENGTH`. -/
partial def valueOf : AbiType → Draw Value
  | .word wordType => return .word (← wordOf wordType) wordType.signed
  | .bytes | .string => .bytes <$> byteString
  | .staticArray element length => .list <$> listOf length (valueOf element)
  | .dynamicArray element => do
    let long := element matches .word _ && (← percent 6)
    let length ← if long then pure (MAX_QUANTIFIED_ARRAY_LENGTH + 1) else oneOf [0, 1, 2, 2, 3, 4]
    .list <$> listOf length (valueOf element)
  | .tuple fields => .list <$> fields.mapM valueOf

/-- The steps that enter an element of a dynamic array: some past the lengths `valueOf` draws. -/
def dynamicIndices : List Nat := [0, 1, 2, 5]

/-- Every path within the type to a target a test compares: a word type, or a type with a calldata length. -/
partial def targets : AbiType → List (Path × AbiType)
  | .staticArray element length =>
    (List.range length).flatMap fun step => (targets element).map fun (path, target) => (step :: path, target)
  | abiType@(.dynamicArray element) =>
    ([], abiType) :: dynamicIndices.flatMap fun step => (targets element).map fun (path, target) => (step :: path, target)
  | .tuple fields =>
    fields.zipIdx.flatMap fun (field, step) => (targets field).map fun (path, target) => (step :: path, target)
  | abiType => [([], abiType)]

/-- Every path within the type to an array a loop walks. -/
partial def arrays : AbiType → List (Path × AbiType)
  | abiType@(.staticArray element length) =>
    ([], abiType) :: (List.range length).flatMap fun step =>
      (arrays element).map fun (path, array) => (step :: path, array)
  | abiType@(.dynamicArray element) =>
    ([], abiType) :: dynamicIndices.flatMap fun step =>
      (arrays element).map fun (path, array) => (step :: path, array)
  | .tuple fields =>
    fields.zipIdx.flatMap fun (field, step) => (arrays field).map fun (path, array) => (step :: path, array)
  | _ => []

/-! ## Formulas -/

/-- The width in bits of the largest value Foundry's cheatcodes set for the chain ID and the fee properties. -/
def EVM_FIELD_BITS : Nat := 64

/-- The context properties bounded by `EVM_FIELD_BITS`. -/
def EVM_FIELD_PROPERTIES : List PropertyId := [CTX_CHAIN_ID, CTX_BASE_FEE, CTX_GAS_PRICE]

/-- A context: every property present, the bounded ones within `EVM_FIELD_BITS`. -/
def contextOf : Draw (List (Option Word)) :=
  (List.range (CTX_MAX + 1)).mapM fun property => do
    if EVM_FIELD_PROPERTIES.contains property then return some (BitVec.ofNat 256 (← unsigned EVM_FIELD_BITS))
    return some (← wordOf (contextPropertyType property))

/-- A constant of the type, often the subject itself or next to it. -/
def near (wordType : WordType) (subject : Option Word) : Draw Word := do
  let roll ← natBetween 0 99
  match subject with
  | some word =>
    let neighbour := if roll % 2 == 0 then word + 1 else word - 1
    if roll < 45 then return word
    else if roll < 70 && wordType.isCanonical neighbour then return neighbour
    else wordOf wordType
  | none => wordOf wordType

/-- Ascending unsigned and without repeats. -/
def ascending (words : List Word) : List Word :=
  (words.mergeSort fun first second => first.toNat ≤ second.toNat).eraseDups

/-- An operand of `comparison` against a word of the type, near `subject`. -/
def wordOperand (wordType : WordType) (subject : Option Word) : Comparison → Draw Operand
  | .between => do
    let bounds := [← near wordType subject, ← near wordType subject]
    let ordered := bounds.mergeSort fun lower upper => !lessThan wordType.signed upper lower
    return .constant (if ← percent 80 then ordered else bounds)
  | .in_ => do
    let mut members := ascending ((← listOf (← natBetween 1 4) (wordOf wordType)) ++
      (if ← percent 70 then subject.toList else []))
    while members.length < 2 do members := ascending (members ++ [← wordOf wordType])
    return .constant members
  | .eq | .gt | .lt | .gte | .lte => do
    if ← percent 15 then return .context (← natBetween 0 CTX_MAX) else return .constant [← near wordType subject]
  | _ => return .constant [← near wordType subject]

/-- An operator comparing a word of the type, its operand near `subject`. -/
def wordOperator (wordType : WordType) (subject : Option Word) : Draw Operator := do
  let comparison ← oneOf [Comparison.eq, .eq, .gt, .lt, .gte, .lte, .between, .in_, .in_, .bitmaskAll, .bitmaskAny,
    .bitmaskNone]
  return ⟨← percent 25, comparison, ← wordOperand wordType subject comparison⟩

/-- An operator comparing a length, its operand near `subject`'s. -/
def lengthOperator (subject : Option Value) : Draw Operator := do
  let length := (subject.bind Value.length?).map (BitVec.ofNat 256)
  let comparison ← oneOf [Comparison.lengthEq, .lengthGt, .lengthLt, .lengthGte, .lengthLte, .lengthBetween]
  let values ← listOf (if comparison == .lengthBetween then 2 else 1) (near LENGTH_TYPE length)
  let values := if ← percent 80 then values.mergeSort (·.toNat ≤ ·.toNat) else values
  return ⟨← percent 25, comparison, .constant values⟩

/-- An operator comparing a target of the type, near the value `subject` has there. -/
def operatorOn (target : AbiType) (subject : Option Value) : Draw Operator :=
  match target with
  | .word wordType => wordOperator wordType (match subject with | some (.word bits _) => some bits | _ => none)
  | _ => lengthOperator subject

/-- A test at a path within a value of type `start`. `subject` gives the value at a path, where a value exists. -/
def testOf (start : AbiType) (subject : Path → Draw (Option Value)) : Draw Rule := do
  let (path, target) ← oneOf (targets start)
  return .test path (← operatorOn target (← subject path))

/-- A context test, its operand near the property's value. -/
def contextTestOf (context : List (Option Word)) : Draw Rule := do
  let property ← natBetween 0 CTX_MAX
  return .contextTest property (← wordOperator (contextPropertyType property) (context[property]?).join)

/-- A loop over an array among `arrayTargets`, one to three body rules, at least one reading the element. -/
def loopOf (arguments : Value) (arrayTargets : List (Path × AbiType)) (context : List (Option Word)) : Draw Rule := do
  let (arrayPath, array) ← oneOf arrayTargets
  let element := match array with
    | .staticArray element _ | .dynamicArray element => element
    | other => other
  let elements := match arguments.at arrayPath with
    | some (.list items) => items
    | _ => []
  let subject path := do
    if elements.isEmpty then return none
    return (← oneOf elements).at path
  let first ← testOf element subject
  let rest ← listOf (← natBetween 0 2) do
    if ← percent 70 then testOf element subject else contextTestOf context
  return .loop (← oneOf [.all, .any]) arrayPath (first :: rest)

/-- A formula of one to three groups over the parameters, reading `arguments` and `context` for its operands. -/
def formulaOf (params : List AbiType) (arguments : Value) (context : List (Option Word)) : Draw Formula := do
  let start := AbiType.tuple params
  let arrayTargets := arrays start
  listOf (← natBetween 1 3) do
    listOf (← natBetween 1 4) do
      let roll ← natBetween 0 99
      if roll < 15 then contextTestOf context
      else if roll < 55 && !arrayTargets.isEmpty then loopOf arguments arrayTargets context
      else testOf start fun path => return arguments.at path

/-! ## Cases -/

/-- An enforcement case: a signature, its arguments, a formula and a context. -/
structure Case where
  signature : Signature
  arguments : Value
  formula : Formula
  context : List (Option Word)

/-- A case. -/
def caseOf : Draw Case := do
  let params ← listOf (← natBetween 1 4) (abiType 3)
  let arguments := Value.list (← params.mapM valueOf)
  let context ← contextOf
  let selector ← if ← percent 80 then some <$> UInt32.ofNat <$> natBetween 0 (2 ^ 32 - 1) else pure none
  return ⟨⟨selector, params⟩, arguments, ← formulaOf params arguments context, context⟩

/-- The calldata of a case: the selector, then the canonical encoding of the arguments. -/
def Case.callData (case : Case) : Bytes :=
  (case.signature.selector.map (beBytes Policy.SELECTOR_SIZE ·.toNat)).getD [] ++
    (AbiType.tuple case.signature.params).encode case.arguments

/-! ## Coverage -/

/-- The types a path passes through within a value of type `start`, its target last. -/
def visited : AbiType → Path → List AbiType
  | _, [] => []
  | .tuple fields, step :: steps => match fields[step]? with
    | some field => field :: visited field steps
    | none => []
  | .staticArray element _, _ :: steps | .dynamicArray element, _ :: steps => element :: visited element steps
  | _, _ :: _ => []

/-- Whether the type is a dynamic array of `element`. -/
def arrayOf (element : AbiType) : AbiType → Bool
  | .dynamicArray inner => inner == element
  | _ => false

/-- Whether the type is a static array of dynamic elements. -/
def staticOfDynamic : AbiType → Bool
  | .staticArray element _ => element.isDynamic
  | _ => false

/-- Whether the type is a tuple holding a dynamic field. -/
def dynamicTuple : AbiType → Bool
  | abiType@(.tuple _) => abiType.isDynamic
  | _ => false

/-- What a coverage count counts, by name. -/
abbrev Counts := Std.HashMap String Nat

/-- `counts` with each named count raised by one. -/
def Counts.raise (counts : Counts) (names : List String) : Counts :=
  names.foldl (fun counts name => counts.insert name (counts.getD name 0 + 1)) counts

/-- The names of the shape counts that `types` reaches, prefixed by where the test sits. -/
def shapes (place : String) (types : List AbiType) : List String :=
  [("bytes[]", types.any (arrayOf .bytes)), ("string[]", types.any (arrayOf .string)),
    ("static array of dynamic elements", types.any staticOfDynamic),
    ("tuple with a dynamic field", types.any dynamicTuple)].filterMap fun (name, reached) =>
      if reached then some s!"{place}: {name}" else none

/-- The names of the counts a test of `operator` on `subject`, a word of type `target`, reaches. -/
def wordCounts (target : AbiType) (operator : Operator) (subject : Option Value) : List String :=
  match subject, operator.comparison, operator.operand with
  | some (.word bits _), .in_, .constant members =>
    match members.idxOf? bits with
    | some 0 => ["IN member matched: first"]
    | some position => [if position + 1 == members.length then "IN member matched: last" else "IN member matched: inner"]
    | none => []
  | some (.word bits _), _, _ =>
    if target == .word (.uint (widthOf 32)) && 2 ^ 255 ≤ bits.toNat then
      [if bits.toNat == 2 ^ 255 then "uint256 subject at 2^255" else "uint256 subject above 2^255"]
    else []
  | _, _, _ => []

/-- The name of a target type's family. -/
def familyOf : AbiType → String
  | .word (.uint _) => "uintN"
  | .word (.int _) => "intN"
  | .word .address => "address"
  | .word .bool => "bool"
  | .word .function => "function"
  | .word (.fixedBytes _) => "bytesN"
  | .bytes => "bytes"
  | .string => "string"
  | _ => "dynamic array"

/-- The names of the counts any test of `operator` on a target of type `target` reaches. -/
def operatorCounts (target : AbiType) (operator : Operator) : List String :=
  [s!"comparison: {reprStr operator.comparison}", s!"target: {familyOf target}",
    match operator.operand with
    | .constant _ => "source: constant"
    | .context _ => "source: context"]

/-- The counts a case's compiled policy reaches. -/
def caseCounts (case : Case) (policy : CompiledPolicy) : List String := Id.run do
  let start := AbiType.tuple case.signature.params
  let mut names := []
  for rule in policy.groups.flatten do
    match rule with
    | .test (.test path _ operator) =>
      let types := visited start path
      let target := types.getLast?.getD start
      names := names ++ shapes "root test" types ++ operatorCounts target operator ++
        wordCounts target operator (case.arguments.at path)
    | .test (.contextTest property operator) =>
      names := names ++ operatorCounts (.word (contextPropertyType property)) operator
    | .loop quantifier arrayPath _ body =>
      let place := if quantifier == .all then "ALL" else "ANY"
      let arrayTypes := visited start arrayPath
      let array := arrayTypes.getLast?.getD start
      let element := match array with
        | .staticArray element _ | .dynamicArray element => element
        | other => other
      names := names ++ (shapes "loop array" [array]).filter (!·.endsWith "tuple with a dynamic field")
      let elements := match case.arguments.at arrayPath with
        | some (.list items) => items
        | _ => []
      for test in body do
        let .test path _ operator := test | continue
        let types := visited element path
        names := names ++ operatorCounts (types.getLast?.getD element) operator
        if operator.negated then names := names ++ [s!"NOT on a body test under {place}"]
        if dynamicTuple element && types.any AbiType.isDynamic then
          names := names ++ ["dynamic field inside a loop element"]
        if elements.any (·.at path |>.isNone) then
          names := names ++ [s!"index past an inner dynamic array's length under {place}"]
        for item in elements do
          names := names ++ wordCounts (types.getLast?.getD element) operator (item.at path)
  return names

/-- Every count the corpus must reach. -/
def requiredCounts : List String :=
  ["NOT on a body test under ALL", "NOT on a body test under ANY",
    "index past an inner dynamic array's length under ALL", "index past an inner dynamic array's length under ANY",
    "dynamic field inside a loop element", "IN member matched: first", "IN member matched: inner",
    "IN member matched: last", "uint256 subject at 2^255", "uint256 subject above 2^255"] ++
  shapes "root test" [.dynamicArray .bytes, .dynamicArray .string, .staticArray .bytes 1, .tuple [.bytes]] ++
  shapes "loop array" [.dynamicArray .bytes, .dynamicArray .string, .staticArray .bytes 1] ++
  [Comparison.eq, .gt, .lt, .gte, .lte, .between, .in_, .bitmaskAll, .bitmaskAny, .bitmaskNone, .lengthEq, .lengthGt,
    .lengthLt, .lengthGte, .lengthLte, .lengthBetween].map (s!"comparison: {reprStr ·}") ++
  ["uintN", "intN", "address", "bool", "function", "bytesN", "bytes", "string", "dynamic array"].map (s!"target: {·}") ++
  ["source: constant", "source: context", "outcome: pass", "outcome: fail", "storage: accept", "storage: reject",
    "storage: mutant accepted"] ++
  ["positive", "singleton", "context subject", "join", "hoist", "fuse", "rule repeat", "group repeat",
    "reorder"].map (s!"rewrite: {·}") ++
  ["CONTRADICTORY_RULE", "REDUNDANT_RULE", "VACUOUS_RULE", "DOMINATED_BOUND", "clean", "clean with a context operand",
    "CONTRADICTORY_RULE past a subject's first test", "REDUNDANT_RULE with a context operand", "body", "uintN", "intN",
    "bytesN", "bool"].map (s!"validation: {·}")

/-! ## Encoding -/

/-- The operator respelled: a comparison with a negated spelling as that spelling, an equality as a one-member set. -/
def respellOperator (operator : Operator) : Draw Operator := do
  match operator.negated, operator.comparison.negation?, operator.comparison, operator.operand with
  | false, some negated, _, _ =>
    if ← percent 40 then return { operator with negated := true, comparison := negated } else return operator
  | _, _, .eq, .constant [_] => if ← percent 40 then return { operator with comparison := .in_ } else return operator
  | _, _, _, _ => return operator

/-- A test respelled: its operator respelled, a context pair with the higher ID as subject, and a range split into its
lower and upper bounds. -/
def respellTest (rule : Rule) : Draw (List Rule) := do
  match rule with
  | .test path ⟨false, .between, .constant [lower, upper]⟩ =>
    if ← percent 40 then
      return [.test path ⟨false, .gte, .constant [lower]⟩, .test path ⟨false, .lte, .constant [upper]⟩]
    else return [rule]
  | .test path ⟨false, .lengthBetween, .constant [lower, upper]⟩ =>
    if ← percent 40 then
      return [.test path ⟨false, .lengthGte, .constant [lower]⟩, .test path ⟨false, .lengthLte, .constant [upper]⟩]
    else return [rule]
  | .test path operator => return [.test path (← respellOperator operator)]
  | .contextTest property operator =>
    let operator ← respellOperator operator
    match operator.operand, operator.comparison.swap? with
    | .context other, some swapped =>
      if property < other && (← percent 60) then
        return [.contextTest other { operator with comparison := swapped, operand := .context property }]
      else return [.contextTest property operator]
    | _, _ => return [.contextTest property operator]
  | .loop .. => return [rule]

/-- Rules with a repeat and in reverse order, at random. -/
def shuffle (rules : List Rule) : Draw (List Rule) := do
  let mut shuffled := rules
  if ← percent 15 then
    if let some rule := shuffled.head? then shuffled := shuffled ++ [rule]
  if ← percent 50 then shuffled := shuffled.reverse
  return shuffled

/-- A loop respelled: its body's tests respelled and shuffled, an `ALL` loop split into two over the same array. -/
def respellLoop (quantifier : Quantifier) (arrayPath : Path) (body : List Rule) : Draw (List Rule) := do
  let body ← shuffle (← body.flatMapM respellTest)
  if quantifier == .all && 2 ≤ body.length && (← percent 40) then
    let cut ← natBetween 1 (body.length - 1)
    return [.loop .all arrayPath (body.take cut), .loop .all arrayPath (body.drop cut)]
  return [.loop quantifier arrayPath body]

/-- A group respelled: its rules respelled, a root context test moved into an `ANY` body that reads the element. The
rules are shuffled in random order. -/
def respellGroup (group : Group) : Draw Group := do
  let mut rules := []
  for rule in group do
    rules := rules ++ (← match rule with
      | .loop quantifier arrayPath body => respellLoop quantifier arrayPath body
      | test => respellTest test)
  let hoistable := rules.findIdx? fun
    | .loop .any _ body => Group.readsElement body
    | _ => false
  let context := rules.findIdx? Rule.isContextTest
  if let (some loopIndex, some contextIndex) := (hoistable, context) then
    if ← percent 60 then
      if let (some (.loop .any arrayPath body), some contextTest) := (rules[loopIndex]?, rules[contextIndex]?) then
        rules := (rules.set loopIndex (.loop .any arrayPath (body ++ [contextTest]))).eraseIdx contextIndex
  shuffle rules

/-- A formula respelled: each group respelled, a group repeated and the groups reversed at random. -/
def respellFormula (formula : Formula) : Draw Formula := do
  let mut groups ← formula.mapM respellGroup
  if ← percent 10 then
    if let some group := groups.head? then groups := groups ++ [group]
  if ← percent 50 then groups := groups.reverse
  return groups

/-- The rule lists of a formula: its groups and every loop's body. -/
def ruleLists (formula : Formula) : List (List Rule) :=
  formula ++ formula.flatten.filterMap fun
    | .loop _ _ body => some body
    | _ => none

/-- The operators of a formula's tests, bodies included. -/
def operatorsOf (formula : Formula) : List Operator :=
  (ruleLists formula).flatten.filterMap fun
    | .test _ operator | .contextTest _ operator => some operator
    | .loop .. => none

/-- The counts of the rewrites normalization applies to `formula`, by the clause of `Formula.normal` it breaks. -/
def rewriteCounts (formula : Formula) : List String :=
  let lists := ruleLists formula
  [("rewrite: positive", (operatorsOf formula).any fun operator =>
      operator.negated && operator.comparison.negation?.isSome),
    ("rewrite: singleton", (operatorsOf formula).any Operator.isSingletonSet),
    ("rewrite: context subject", lists.flatten.any fun
      | .contextTest property operator => !Rule.subjectNormal property operator
      | _ => false),
    ("rewrite: join", formula.any (!Group.joinsApart ·)),
    ("rewrite: hoist", formula.any (!Group.nothingHoisted ·)),
    ("rewrite: fuse", lists.any (!Group.noLonePair ·)),
    ("rewrite: rule repeat", lists.any fun rules => !rules.Nodup),
    ("rewrite: group repeat", !formula.Nodup),
    ("rewrite: reorder", lists.any fun rules => !strictlySorted Rule.key rules.eraseDups)].filterMap
      fun (name, fired) => if fired then some name else none

/-! ## Storage -/

/-- The blob with one random edit: a byte replaced, nudged or set to an edge value, a cut, a deletion or an append. -/
def mutateOnce (blob : Bytes) : Draw Bytes := do
  if blob.isEmpty then return [← byte]
  let position ← natBetween 0 (blob.length - 1)
  match ← natBetween 0 6 with
  | 0 => return blob.set position (← byte)
  | 1 => return blob.set position (← oneOf [0x00, 0x01, 0x02, 0x7F, 0x80, 0xFE, 0xFF])
  | 2 => return blob.set position (blob[position]! + 1)
  | 3 => return blob.set position (blob[position]! - 1)
  | 4 => return blob.take position
  | 5 => return blob.eraseIdx position
  | _ => return blob ++ (← listOf (← natBetween 1 4) byte)

/-- The blob with one to three random edits. -/
def mutate (blob : Bytes) : Draw Bytes := do
  let mut result := blob
  for _ in [0:← natBetween 1 3] do result ← mutateOnce result
  return result

/-- The blobs of a storage vector file. -/
def vectorBlobs (path : String) : IO (List Bytes) := do
  let vectors ← IO.ofExcept ((Json.parse (← IO.FS.readFile path)).bind Json.getArr?)
  vectors.toList.mapM fun vector => do
    let some blob := parseHex (← IO.ofExcept (vector.getObjValAs? String "blob")) | throw (.userError "blob is not hex")
    return blob

/-! ## Validation -/

/-- The types whose every value the PV-9 oracle enumerates. -/
def validationTypes : List WordType := [.uint (widthOf 1), .int (widthOf 1), .fixedBytes (widthOf 1), .bool]

/-- The comparisons PV-5 admits with a constant operand against a target of one of `validationTypes`. -/
def comparisonsOn : WordType → List Comparison
  | .uint _ | .int _ =>
    [.eq, .gt, .gt, .lt, .lt, .gte, .lte, .between, .between, .between, .in_, .bitmaskAll, .bitmaskAny, .bitmaskAny,
      .bitmaskNone]
  | .bool => [.eq]
  | _ => [.eq, .in_, .bitmaskAll, .bitmaskAny, .bitmaskAny, .bitmaskNone]

/-- The context properties PV-5 pairs with a `uintN` target. -/
def uintProperties : List PropertyId :=
  (List.range (CTX_MAX + 1)).filter (contextPropertyType · != .address)

/-- The word of one of `validationTypes` whose byte is `pattern`. Its low byte is `pattern`, sign extended for `int8`.
For `bytes1`, its high byte is `pattern`. For `bool`, its low bit is the low bit of `pattern`. -/
def wordOfPattern (wordType : WordType) (pattern : Nat) : Word :=
  match wordType with
  | .int width => Word.signExtendFrom width (BitVec.ofNat 256 pattern)
  | .fixedBytes _ => BitVec.ofNat 256 pattern <<< 248
  | .bool => BitVec.ofNat 256 (pattern % 2)
  | _ => BitVec.ofNat 256 pattern

/-- An operator among `comparisons` on a target of one of `validationTypes`, negated `negations` percent of the time.
Its operand is a constant at or next to a byte of `pool`, or a mask of one to three bits. On `uintN`, the operand is a
context operand among `properties` for 40 percent of `EQ` to `LTE`. -/
def validationOperator (wordType : WordType) (comparisons : List Comparison) (negations : Nat) (pool : List Nat)
    (properties : List PropertyId) : Draw Operator := do
  let constant : Draw Word := do
    let pattern ← oneOf pool
    return wordOfPattern wordType (← oneOf [pattern, pattern, (pattern + 1) % 256, (pattern + 255) % 256])
  let comparison ← oneOf comparisons
  let operand : Operand ← match comparison with
    | .between => do
      let bounds := [← constant, ← constant]
      let ordered := bounds.mergeSort fun lower upper => !lessThan wordType.signed upper lower
      pure (.constant (if ← percent 85 then ordered else bounds))
    | .in_ => do pure (.constant (ascending (← listOf (← natBetween 2 3) constant)))
    | .bitmaskAll | .bitmaskAny | .bitmaskNone => do
      let bits ← listOf (← natBetween 1 3) (natBetween 0 7)
      pure (.constant [wordOfPattern wordType (bits.foldl (fun mask bit => mask ||| 1 <<< bit) 0)])
    | _ => do
      if wordType matches .uint _ && (← percent 40) then pure (.context (← oneOf properties))
      else pure (.constant [← constant])
  return ⟨← percent negations, comparison, operand⟩

/-- A validation case uses a type among `validationTypes` as one parameter, two, or the element of an array a loop
walks. It has one or two groups of one to eight tests on it. A quarter of the cases not on `bool` contain five to eight
bitmask tests, half negated, which the mask search needs. -/
def validationCaseOf : Draw (Signature × Formula) := do
  let wordType ← oneOf validationTypes
  let pool ← listOf 3 (oneOf [0, 1, 127, 128, 254, 255, ← natBetween 0 255, ← natBetween 0 255])
  let properties ← listOf (← natBetween 1 2) (oneOf uintProperties)
  let element := AbiType.word wordType
  let shape ← natBetween 0 3
  let masks := wordType != .bool && (← percent 25)
  let comparisons := if masks then [.bitmaskAll, .bitmaskAny, .bitmaskAny, .bitmaskNone] else comparisonsOn wordType
  let negations := if masks then 50 else 25
  let tests (paths : List Path) : Draw (List Rule) := do
    listOf (← if masks then natBetween 5 8 else oneOf [1, 2, 2, 3, 3, 4, 4, 5, 6, 8]) do
      return .test (← oneOf paths) (← validationOperator wordType comparisons negations pool properties)
  let formula ← listOf (← natBetween 1 2) do
    match shape with
    | 0 => do pure [.loop (← oneOf [.all, .any]) [0] (← tests [[]])]
    | 1 => tests [[0], [1]]
    | _ => tests [[0]]
  let params := match shape with
    | 0 => [.dynamicArray element]
    | 1 => [element, element]
    | _ => [element]
  return (⟨some 0, params⟩, formula)

/-- The counts a validation case reaches. -/
def validationCounts (signature : Signature) (formula : Formula) (issues : List Issue) : List String :=
  let readsContext := (operatorsOf formula).any (·.operand matches .context _)
  let families := signature.params.map fun
    | .dynamicArray element => familyOf element
    | param => familyOf param
  (families ++ issues.map (·.code)).map (s!"validation: {·}") ++
  [("body", formula.flatten.any Rule.isLoop),
    ("clean", issues.isEmpty),
    ("clean with a context operand", issues.isEmpty && readsContext),
    -- With one parameter, the tests of a list share one subject, so a test past the first is past a first prefix.
    ("CONTRADICTORY_RULE past a subject's first test", signature.params.length == 1 && issues.any fun issue =>
      issue.code == "CONTRADICTORY_RULE" && issue.location.getLast? != some 0),
    ("REDUNDANT_RULE with a context operand", issues.any fun issue =>
      issue.code == "REDUNDANT_RULE" && issue.operator.operand matches .context _)].filterMap
    fun (name, reached) => if reached then some s!"validation: {name}" else none

/-! ## Entry -/

/-- Validation cases per enforcement case. They are cheap to check, and a test that only an absent context property
keeps from being implied is rare among them. -/
def VALIDATION_CASES_PER_CASE : Nat := 4

/-- The percentage of validation cases with a contradiction kept, so most cases reach redundancy and dominance. -/
def CONTRADICTIONS_KEPT : Nat := 40

/-- How many mutants follow each storage blob. -/
def MUTANTS_PER_BLOB : Nat := 3

def main (args : List String) : IO UInt32 := do
  let (seed, cases, directory, policies) ← match args with
    | [seed, cases, directory] => pure (seed, cases, directory, "../vectors/policies.json")
    | [seed, cases, directory, policies] => pure (seed, cases, directory, policies)
    | _ => do
      IO.eprintln "usage: generate-corpus <seed> <cases> <directory> [<policies.json>]"
      return 2
  let some seed := seed.toNat? | do IO.eprintln "seed is not a number"; return 2
  let some cases := cases.toNat? | do IO.eprintln "cases is not a number"; return 2
  IO.println s!"seed: {seed}"
  IO.FS.createDirAll directory
  let mut generator := mkStdGen seed
  -- Respelling draws from a stream of its own, so the enforcement corpus does not depend on it.
  let mut respellGenerator := mkStdGen (seed + 1)
  let mut counts : Counts := {}
  let mut blobs := []
  let mut illFormed := 0
  let enforcement ← IO.FS.Handle.mk s!"{directory}/enforcement.txt" .write
  let encoding ← IO.FS.Handle.mk s!"{directory}/encoding.txt" .write
  for id in [0:cases] do
    let (case, next) := caseOf.run generator
    generator := next
    unless decide (Policy.WellFormed case.signature case.formula) do
      if illFormed < 5 then IO.eprintln s!"ill-formed case {id}: {reprStr case.formula}"
      illFormed := illFormed + 1
      continue
    let blob := Policy.encode case.signature case.formula
    let some policy := Policy.parse blob | do
      IO.eprintln s!"case {id}: the encoder's blob fails storage validation"
      return 1
    let context : Context := fun property => (case.context[property]?).join
    let outcome := Policy.outcome blob case.callData context
    counts := counts.raise (caseCounts case policy ++ [s!"outcome: {outcome.name}"])
    blobs := blob :: blobs
    enforcement.putStrLn s!"{id} {hexOf blob} {hexOf case.callData} {contextField context} {outcome.name}"
    let (respelled, next) := (respellFormula case.formula).run respellGenerator
    respellGenerator := next
    let wellFormed := decide (Policy.WellFormed case.signature respelled)
    let formula := if wellFormed then respelled else case.formula
    unless wellFormed do counts := counts.raise ["encoding: respelling not well formed"]
    let some raw := (CompiledPolicy.compile case.signature formula).map CompiledPolicy.write | do
      IO.eprintln s!"case {id}: the respelled formula does not compile"
      return 1
    let expected := Policy.encode case.signature formula
    unless Policy.validate raw && reencode raw == some expected do
      IO.eprintln s!"case {id}: the respelled blob fails storage validation or decodes to another formula"
      return 1
    counts := counts.raise (rewriteCounts formula)
    encoding.putStrLn s!"{id} {hexOf raw} {hexOf expected}"
  let storage ← IO.FS.Handle.mk s!"{directory}/storage.txt" .write
  let mut storageId := 0
  for blob in blobs.reverse ++ (← vectorBlobs policies) do
    let (mutants, next) := (listOf MUTANTS_PER_BLOB (mutate blob)).run generator
    generator := next
    for (candidate, mutant) in (blob, false) :: mutants.map ((·, true)) do
      let accepted := Policy.validate candidate
      counts := counts.raise ([if accepted then "storage: accept" else "storage: reject"] ++
        if mutant && accepted then ["storage: mutant accepted"] else [])
      storage.putStrLn s!"{storageId} {hexOf candidate} {if accepted then "accept" else "reject"}"
      storageId := storageId + 1
  let validation ← IO.FS.Handle.mk s!"{directory}/validation.txt" .write
  -- Validation draws from a stream of its own, so the other corpora do not depend on it.
  let mut validationGenerator := mkStdGen (seed + 2)
  let mut validationId := 0
  while validationId < VALIDATION_CASES_PER_CASE * cases do
    let (((signature, formula), keep), next) := (do
      return (← validationCaseOf, ← percent CONTRADICTIONS_KEPT)).run validationGenerator
    validationGenerator := next
    unless decide (Policy.WellFormed signature formula) do
      IO.eprintln s!"validation case {validationId} is not well formed: {reprStr formula}"
      return 1
    let blob := Policy.encode signature formula
    let some issues := (Policy.parse blob).bind validationIssues? | do
      IO.eprintln s!"validation case {validationId}: the oracle cannot read the blob"
      return 1
    if issues.any (·.code == "CONTRADICTORY_RULE") && !keep then continue
    counts := counts.raise (validationCounts signature formula issues)
    validation.putStrLn s!"{validationId} {hexOf blob} {issuesField issues}"
    validationId := validationId + 1
  for (name, count) in counts.toList.mergeSort (·.1 < ·.1) do
    IO.println s!"{name}: {count}"
  let missing := requiredCounts.filter (counts.getD · 0 == 0)
  for name in missing do IO.eprintln s!"not reached: {name}"
  if 0 < illFormed then IO.eprintln s!"{illFormed} ill-formed cases"
  return if missing.isEmpty && illFormed == 0 then 0 else 1
