import Callcium.Evaluate
import Callcium.Wire.Encode
import Callcium.Abi.DecodeStrict

/-!
# Enforcement

`Policy.enforce` is the byte-level evaluator: the verdict the enforcer reaches on a stored blob, calldata and the call's
context. At entry it checks the format version. It reads the blob through `Policy.load`, which reads every field the
format defines where the format places it and checks none of the storage invariants: it fails only where a
field has no reading, a read past its region or a value outside every defined one. It evaluates the loaded policy in
the order `Formula.evaluateValues` fixes: groups in order, rules in order, elements in index order, each with the
short-circuits of `Quantifier.evaluate`. Within a test the checks run as the enforcer runs them: the hint resolves, the
word at the target loads, a declared length's payload must lie within the calldata or a word must be canonical for its
type, and the operator compares. Every calldata read goes through `loadWord`, which faults instead of reading past the
end.

`Policy.outcome` names why an evaluation aborts, and `Trace.steps` counts the rules and tests it evaluates.
-/

namespace Callcium

/-! ## Outcomes -/

/-- Why enforcement ends without a verdict. -/
inductive Abort where
  /-- The calldata is shorter than the selector (`MISSING_SELECTOR`). -/
  | missingSelector
  /-- The calldata's selector is not the policy's (`SELECTOR_MISMATCH`). -/
  | selectorMismatch
  /-- A word read, an offset or a declared payload past the end of the calldata (`CALLDATA_OUT_OF_BOUNDS`). -/
  | calldataOutOfBounds
  /-- A word that is not the canonical encoding of its type (`NON_CANONICAL_VALUE`). -/
  | nonCanonicalValue
  /-- An array longer than `MAX_QUANTIFIED_ARRAY_LENGTH` under a loop (`QUANTIFIER_LIMIT_EXCEEDED`). -/
  | quantifierLimitExceeded
  /-- A blob the enforcer does not evaluate: shorter than a field it reads, of another format version, or holding a
  value outside every defined one. -/
  | unsupportedPolicy
  deriving Repr, DecidableEq

/-- The outcome of enforcement: a verdict, or an abort and its reason. -/
inductive Outcome where
  | pass
  | fail
  | abort (reason : Abort)
  deriving Repr, DecidableEq

/-- The outcome of a test's result. -/
def Outcome.ofBool : Bool → Outcome
  | true => .pass
  | false => .fail

/-- The verdict of an outcome. -/
def Outcome.verdict : Outcome → Verdict
  | .pass => .pass
  | .fail => .fail
  | .abort _ => .abort

/-- The outcome a resolution fault gives: an index past a dynamic array's length fails the group, a read past the end
of the calldata aborts. -/
def Fault.outcome : Fault → Outcome
  | .calldataOutOfBounds => .abort .calldataOutOfBounds
  | .arrayIndexOutOfBounds => .fail

/-- An outcome and the steps taken to reach it. -/
structure Trace where
  /-- The outcome. -/
  outcome : Outcome
  /-- One per root rule evaluated, and one per body test for each element its loop visits. -/
  steps : Nat
  deriving Repr

/-- Runs `items` in order as `Quantifier.evaluate` does, adding up the steps of the items it runs. -/
def Quantifier.run {Item : Type} (run : Item → Trace) : Quantifier → List Item → Trace
  | .all, [] => ⟨.pass, 0⟩
  | .any, [] => ⟨.fail, 0⟩
  | .all, item :: items =>
    let first := run item
    match first.outcome with
    | .pass =>
      let rest := Quantifier.run run .all items
      ⟨rest.outcome, first.steps + rest.steps⟩
    | outcome => ⟨outcome, first.steps⟩
  | .any, item :: items =>
    let first := run item
    match first.outcome with
    | .fail =>
      let rest := Quantifier.run run .any items
      ⟨rest.outcome, first.steps + rest.steps⟩
    | outcome => ⟨outcome, first.steps⟩

/-! ## Comparisons on lengths -/

/-- The comparison's result on a value of `length` elements or bytes, as `Comparison.apply` gives it on such a value:
none for a comparison that reads a word. -/
def Comparison.applyLength : Comparison → Nat → List Word → Option Bool
  | .lengthEq, length, [value] => some (length == value.toNat)
  | .lengthGt, length, [bound] => some (bound.toNat < length)
  | .lengthLt, length, [bound] => some (length < bound.toNat)
  | .lengthGte, length, [bound] => some !(length < bound.toNat)
  | .lengthLte, length, [bound] => some !(bound.toNat < length)
  | .lengthBetween, length, [min, max] => some (!(length < min.toNat) && !(max.toNat < length))
  | _, _, _ => none

/-- Whether the operator holds on a value of `length` elements or bytes, as `Operator.holds` decides it. -/
def Operator.holdsLength (operator : Operator) (ctx : Context) (length : Nat) : Bool :=
  match operator.operand.values ctx with
  | some values =>
    match operator.comparison.applyLength length values with
    | some result => result != operator.negated
    | none => false
  | none => false

/-! ## Resolution from wire hints -/

/-- Where the test's target starts, from a starting point whose encoding starts at `start`. -/
def TestHint.resolve (hint : TestHint) (data : Bytes) (start : Nat) : Except Fault Nat :=
  (resolveHops data hint.hops start).map (advance · hint.targetDelta)

/-- Where the loop's elements start and how many there are, from a starting point whose encoding starts at `start`. A
dynamic array's length precedes its elements. -/
def FrameHint.resolveArray (hint : FrameHint) (data : Bytes) (start : Nat) : Except Fault (Nat × Nat) := do
  let array := advance (← resolveHops data hint.hops start) hint.arrayDelta
  if hint.count = 0 then
    let count := (← loadWord data array).toNat
    pure (advance array WORD_SIZE, count)
  else pure (array, hint.count)

/-- Where element `position` of the loop's array starts, its elements starting at `elements`. -/
def FrameHint.resolveElement (hint : FrameHint) (data : Bytes) (elements position : Nat) : Except Fault Nat :=
  hint.array.elementAt data elements position

/-! ## Evaluation -/

/-- The bytes per item a target's declared length counts: an element's head for a dynamic array, one for `bytes` and
`string`. -/
def TestHint.payloadStride (hint : TestHint) : Nat :=
  match hint.targetMeta with
  | some array => WORD_SIZE * array.strideWords
  | none => 1

/-- The outcome of a test whose target starts at `target`. A target with a calldata length compares its length, whose
payload must lie within the calldata; any other target compares its word, which must be canonical for its type. -/
def TestHint.compare (hint : TestHint) (operator : Operator) (ctx : Context) (data : Bytes) (target : Nat) :
    Outcome :=
  match loadWord data target with
  | .error fault => fault.outcome
  | .ok word =>
    if hasCalldataLength hint.typeCode then
      if target + WORD_SIZE + word.toNat * hint.payloadStride ≤ data.length then
        .ofBool (operator.holdsLength ctx word.toNat)
      else .abort .calldataOutOfBounds
    else
      match WordType.ofCode? hint.typeCode with
      | some wordType =>
        if wordType.isCanonical word then .ofBool (operator.holds ctx (some (.word word wordType.signed)))
        else .abort .nonCanonicalValue
      | none => .abort .unsupportedPolicy

/-- The outcome of a test from a starting point whose encoding starts at `start`. -/
def CompiledTest.outcome (data : Bytes) (ctx : Context) (start : Nat) : CompiledTest → Outcome
  | .contextTest property operator => .ofBool (operator.holds ctx ((ctx property).map (.word · false)))
  | .test _ hint operator =>
    match hint.resolve data start with
    | .ok target => hint.compare operator ctx data target
    | .error fault => fault.outcome

/-- A test, one step. -/
def CompiledTest.run (data : Bytes) (ctx : Context) (start : Nat) (test : CompiledTest) : Trace :=
  ⟨test.outcome data ctx start, 1⟩

/-- A rule from a starting point whose encoding starts at `start`. A loop resolves its array, aborts above
`MAX_QUANTIFIED_ARRAY_LENGTH` before reading an element, and runs its body from each element in index order. -/
def CompiledRule.run (data : Bytes) (ctx : Context) (start : Nat) : CompiledRule → Trace
  | .test compiled => compiled.run data ctx start
  | .loop quantifier _ hint body =>
    match hint.resolveArray data start with
    | .error fault => ⟨fault.outcome, 1⟩
    | .ok (elements, count) =>
      if MAX_QUANTIFIED_ARRAY_LENGTH < count then ⟨.abort .quantifierLimitExceeded, 1⟩
      else
        let walked := quantifier.run (fun position =>
          match hint.resolveElement data elements position with
          | .ok element => Quantifier.run (CompiledTest.run data ctx element) .all body
          | .error fault => ⟨fault.outcome, 0⟩) (List.range count)
        ⟨walked.outcome, walked.steps + 1⟩

/-- Where the arguments' encoding starts: past the selector, or at 0 for raw ABI-encoded arguments. -/
def Policy.argumentsStart (selector : Option UInt32) : Nat :=
  if selector.isSome then Policy.SELECTOR_SIZE else 0

/-- The policy's groups against `data`, in order. -/
def CompiledPolicy.runGroups (policy : CompiledPolicy) (data : Bytes) (ctx : Context) : Trace :=
  Quantifier.run (Quantifier.run (CompiledRule.run data ctx (Policy.argumentsStart policy.selector)) .all) .any
    policy.groups

/-- The policy against `data`: the selector check, then the groups in order. -/
def CompiledPolicy.run (policy : CompiledPolicy) (data : Bytes) (ctx : Context) : Trace :=
  match policy.selector with
  | none => policy.runGroups data ctx
  | some selector =>
    if data.length < Policy.SELECTOR_SIZE then ⟨.abort .missingSelector, 0⟩
    else if beNat (data.take Policy.SELECTOR_SIZE) = selector.toNat then policy.runGroups data ctx
    else ⟨.abort .selectorMismatch, 0⟩

/-! ## The enforcer's view of a blob -/

namespace Reader

/-- Runs `reader` over the next `size` bytes, whatever it leaves of them. -/
def within {Item : Type} (size : Nat) (reader : Reader Item) : Reader Item := do
  let region ← take size
  match reader region with
  | some (item, _) => pure item
  | none => failure

end Reader

open Reader

/-- A hop: a plain hop where the index is `HINT_NO_INDEX`, an element hop at any other index, its meta word read with
the reserved bits ignored. -/
def Hop.load : Reader Hop := do
  let delta ← field 4
  let index ← field 2
  let metaWord ← field 2
  pure (if index = HINT_NO_INDEX then .plain delta else .element index (.ofWordMasked metaWord))

/-- A hint header, then as many hops as it counts. -/
def loadHops : Reader (List Hop) := do
  let hopCount := (← byte).toNat
  many Hop.load hopCount

/-- A test's hint; the target meta word is read for a dynamic array only. -/
def TestHint.load : Reader TestHint := do
  let hops ← loadHops
  let targetDelta ← field 4
  let metaWord ← field 2
  let typeCode ← byte
  pure ⟨hops, targetDelta, if typeCode = TypeCode.DYNAMIC_ARRAY then some (.ofWordMasked metaWord) else none, typeCode⟩

/-- A loop's hint. -/
def FrameHint.load : Reader FrameHint := do
  let hops ← loadHops
  let arrayDelta ← field 4
  let count ← field 2
  let metaWord ← field 2
  pure ⟨hops, arrayDelta, count, .ofWordMasked metaWord⟩

/-- A path: its depth, then its steps. -/
def loadPath : Reader Path := do
  let depth := (← byte).toNat
  many (field 2) depth

/-- An operator against a target of type code `code`. Constants are as wide as the operand type, as many as the
comparison takes whatever `dataLength` states, and for `IN` as many as `dataLength` holds; a context source names a
property in 2 bytes. -/
def Operator.load (code : UInt8) : Reader Operator := do
  let opCode := (← byte).toNat
  let negated := decide (opCode / NOT_FLAG = 1)
  let source := opCode % NOT_FLAG / 2 ^ SOURCE_SHIFT
  let comparison ← some? (Comparison.ofCode? (opCode % 2 ^ SOURCE_SHIFT))
  let wordType ← some? (operandType comparison code)
  let dataLength ← field 2
  if source = SOURCE_CONSTANT then
    let count := comparison.arity.getD (dataLength / wordType.width)
    let values := (← many (take wordType.width) count).map wordType.load
    pure ⟨negated, comparison, .constant values⟩
  else if source = SOURCE_CONTEXT then
    let property ← field 2
    pure ⟨negated, comparison, .context property⟩
  else failure

/-- A test or a context test after its `scope` byte. A context test's property follows its one-byte path depth. -/
def CompiledTest.loadScoped (scope : UInt8) : Reader CompiledTest := do
  if scope = SCOPE_CONTEXT then
    let _ ← byte
    let property ← field 2
    let operator ← Operator.load (contextPropertyType property).code
    pure (.contextTest property operator)
  else if scope = SCOPE_CALLDATA then
    let path ← loadPath
    let hint ← TestHint.load
    let operator ← Operator.load hint.typeCode
    pure (.test path hint operator)
  else failure

/-- A rule's content within the region its `ruleSize` gives. -/
def loadFramed {Item : Type} (reader : Reader Item) : Reader Item := do
  let ruleSize ← field 2
  within (ruleSize - Policy.RULE_SIZE_SIZE) reader

/-- A body test. -/
def CompiledTest.load : Reader CompiledTest :=
  loadFramed do CompiledTest.loadScoped (← byte)

/-- A root rule. -/
def CompiledRule.load : Reader CompiledRule := loadFramed do
  let scope ← byte
  if scope = SCOPE_LOOP then
    let quantifier ← some? (Quantifier.ofCode? (← byte))
    let arrayPath ← loadPath
    let hint ← FrameHint.load
    let ruleCount ← field 2
    let body ← many CompiledTest.load ruleCount
    pure (.loop quantifier arrayPath hint body)
  else .test <$> CompiledTest.loadScoped scope

/-- A root group: as many rules as `ruleCount` states, within the region `groupSize` gives. -/
def loadGroup : Reader (List CompiledRule) := do
  let ruleCount ← field 2
  let groupSize ← field 4
  within groupSize (many CompiledRule.load ruleCount)

/-- The policy as the enforcer reads it: the selector unless the header flags it absent, the descriptor's length to
pass it, and as many groups as `groupCount` states. -/
def Policy.loadPolicy : Reader CompiledPolicy := do
  let header := (← byte).toNat
  let selector ← field Policy.SELECTOR_SIZE
  let desc ← take (← field 2)
  let groupCount := (← byte).toNat
  let groups ← many loadGroup groupCount
  let selectorless := header &&& Policy.FLAG_NO_SELECTOR = Policy.FLAG_NO_SELECTOR
  pure ⟨if selectorless then none else some (UInt32.ofNat selector), desc, groups⟩

/-- The policy as the enforcer reads it from `blob`; none where a field has no reading. -/
def Policy.load (blob : Bytes) : Option CompiledPolicy :=
  (Policy.loadPolicy blob).map (·.1)

/-! ## Entry -/

namespace Policy

/-- Whether the enforcer evaluates a blob whose header byte is `header`: `major` is `MAJOR` and `minor` at most
`MINOR`. -/
def supports (header : UInt8) : Bool :=
  header.toNat >>> MAJOR_SHIFT = MAJOR && (header.toNat >>> MINOR_SHIFT) &&& MINOR_MASK ≤ MINOR

/-- The enforcer on a blob, calldata and the call's context: an unsupported format version or a blob it cannot read
aborts, otherwise the loaded policy decides. -/
def run (blob data : Bytes) (ctx : Context) : Trace :=
  match blob.head?.filter supports, load blob with
  | some _, some policy => policy.run data ctx
  | _, _ => ⟨.abort .unsupportedPolicy, 0⟩

/-- The enforcer's outcome. -/
def outcome (blob data : Bytes) (ctx : Context) : Outcome :=
  (run blob data ctx).outcome

/-- The enforcer's verdict. -/
def enforce (blob data : Bytes) (ctx : Context) : Verdict :=
  (outcome blob data ctx).verdict

end Policy

/-! ## Work -/

/-- The most steps a rule takes: one, and for a loop its body per element, at most `MAX_QUANTIFIED_ARRAY_LENGTH`
elements or a static array's declared length. -/
def CompiledRule.workBound : CompiledRule → Nat
  | .test _ => 1
  | .loop _ _ hint body =>
    1 + (if hint.count = 0 then MAX_QUANTIFIED_ARRAY_LENGTH else min hint.count MAX_QUANTIFIED_ARRAY_LENGTH) *
      body.length

/-- The most steps a policy takes: every rule of every group. -/
def CompiledPolicy.workBound (policy : CompiledPolicy) : Nat :=
  (policy.groups.map fun rules => (rules.map CompiledRule.workBound).sum).sum

/-! ## Calls -/

/-- The arguments as Solidity's decoder reads them from `data`. -/
def Signature.decodeSolc (signature : Signature) (data : Bytes) : Value :=
  (AbiType.tuple signature.params).decodeSolc data (Policy.argumentsStart signature.selector)

/-- The arguments whose canonical encoding `data` holds after the signature's selector; none for any other data. -/
def Signature.decodeStrict (signature : Signature) (data : Bytes) : Option Value :=
  if signature.selector.all fun selector =>
      data.take Policy.SELECTOR_SIZE = beBytes Policy.SELECTOR_SIZE selector.toNat then
    (AbiType.tuple signature.params).decodeStrict data (Policy.argumentsStart signature.selector)
  else none

end Callcium
