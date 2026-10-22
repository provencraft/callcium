import Callcium.Wire.Validate

/-!
# Wire encoding

`Policy.encode` writes a formula over a signature as a blob: it normalizes the formula, compiles every path into its
hint against the signature's parameter types (`Rule.compile`), and writes the result in the formula's order, which
over one signature is the order of the rules' size-free bytes. `Policy.WellFormed` is what the encoder needs: a
well-formed formula whose normal form compiles against the signature and fits the wire's field widths.
`Policy.decode` reads the formula back from a blob that passes storage validation.
-/

namespace Callcium

/-- A function signature: its selector, none for a policy over raw ABI-encoded arguments, and its parameter types. -/
structure Signature where
  /-- The function selector; none for raw ABI-encoded arguments. -/
  selector : Option UInt32
  /-- The parameter types. -/
  params : List AbiType

/-! ## Compilation -/

/-- Whether the operator compares a target of type code `code`: its comparison applies to the type, and every constant
is a value of the operand type. -/
def Operator.compares (operator : Operator) (code : UInt8) : Bool :=
  match operandType operator.comparison code, operator.operand with
  | some wordType, .constant values => values.all wordType.isCanonical
  | some _, .context _ => true
  | none, _ => false

/-- The test with its hint compiled from a starting point of type `start`; none when its path does not compile or its
operator does not compare the target. A loop is no test. -/
def Rule.compileTest (start : AbiType) : Rule → Option CompiledTest
  | .contextTest property operator =>
    if operator.compares (contextPropertyType property).code then some (.contextTest property operator) else none
  | .test path operator =>
    (start.compile? path).bind fun hint =>
      if operator.compares hint.target.code then some (.test path hint.wire operator) else none
  | .loop .. => none

/-- The rule with its hints compiled from a starting point of type `start`; a loop's body compiles from its element
type and holds tests only. -/
def Rule.compile (start : AbiType) : Rule → Option CompiledRule
  | .loop quantifier arrayPath body =>
    (start.compileLoop? arrayPath).bind fun hint =>
      (body.mapM (Rule.compileTest hint.element)).map (.loop quantifier arrayPath hint.frame)
  | rule => (rule.compileTest start).map .test

/-- The policy of `formula` over the signature, its paths compiled from the arguments. -/
def CompiledPolicy.compile (signature : Signature) (formula : Formula) : Option CompiledPolicy :=
  (formula.mapM (List.mapM (Rule.compile (.tuple signature.params)))).map
    (⟨signature.selector, Descriptor.encode signature.params, ·⟩)

/-! ## Field widths -/

/-- Whether a hop fits its fields: a delta below 2^32; a fixed index below `PATH_MARKER_BASE` and a stride within its 12
bits. -/
def Hop.fits : Hop → Bool
  | .plain delta => delta < 2 ^ 32
  | .element index array => index < PATH_MARKER_BASE && array.strideWords < META_STRIDE_LIMIT

/-- Whether a chain fits: at most `MAX_HOP_COUNT` hops, each fitting. -/
def hopsFit (hops : List Hop) : Bool :=
  hops.length ≤ MAX_HOP_COUNT && hops.all Hop.fits

/-- Whether a test's hint fits its fields. -/
def TestHint.fits (hint : TestHint) : Bool :=
  hopsFit hint.hops && hint.targetDelta < 2 ^ 32 && hint.targetMeta.all (·.strideWords < META_STRIDE_LIMIT)

/-- Whether a loop's hint fits its fields. -/
def FrameHint.fits (hint : FrameHint) : Bool :=
  hopsFit hint.hops && hint.arrayDelta < 2 ^ 32 && hint.count < 2 ^ 16 && hint.array.strideWords < META_STRIDE_LIMIT

/-- Whether a path fits: a one-byte depth, 2-byte steps. -/
def Path.fits (path : Path) : Bool :=
  path.length < 2 ^ 8 && path.all (· < 2 ^ 16)

/-- Whether an operator against a target of type code `code` fits: a context property ID in 2 bytes, data within
`dataLength`. -/
def Operator.fits (operator : Operator) (code : UInt8) : Bool :=
  (match operator.operand with
    | .context property => property < 2 ^ 16
    | .constant _ => true) &&
    (operator.data code).length < 2 ^ 16

/-- Whether a test fits its fields, `ruleSize` included. -/
def CompiledTest.fits (test : CompiledTest) : Bool :=
  test.write.length < 2 ^ 16 &&
    match test with
    | .contextTest property operator => property < 2 ^ 16 && operator.fits (contextPropertyType property).code
    | .test path hint operator => Path.fits path && hint.fits && operator.fits hint.typeCode

/-- Whether a rule fits its fields, `ruleSize` and every body test included. -/
def CompiledRule.fits (rule : CompiledRule) : Bool :=
  rule.write.length < 2 ^ 16 &&
    match rule with
    | .test compiled => compiled.fits
    | .loop _ arrayPath hint body =>
      Path.fits arrayPath && hint.fits && body.length < 2 ^ 16 && body.all CompiledTest.fits

/-- Whether a group fits: `ruleCount` in 2 bytes, `groupSize` in 4, every rule fitting. -/
def groupFits (rules : List CompiledRule) : Bool :=
  rules.length < 2 ^ 16 && (rules.flatMap CompiledRule.write).length < 2 ^ 32 && rules.all CompiledRule.fits

/-- Whether a policy fits: `descLength` in 2 bytes, `groupCount` in 1, every group fitting. -/
def CompiledPolicy.fits (policy : CompiledPolicy) : Bool :=
  policy.desc.length < 2 ^ 16 && policy.groups.length < 2 ^ 8 && policy.groups.all groupFits

/-! ## Canonical order -/

/-- Whether the items ascend strictly by their bytes, compared lexicographically. -/
def ascendingBytes {Item : Type} (bytes : Item → Bytes) (items : List Item) : Bool :=
  decide (items.Pairwise fun item other => bytes item < bytes other)

/-- Whether a loop's body tests ascend strictly by their size-free bytes; a test holds no body. -/
def CompiledRule.ordered : CompiledRule → Bool
  | .test _ => true
  | .loop _ _ _ body => ascendingBytes CompiledTest.sizeFree body

/-- Whether the policy's rules and groups are in canonical order: the rules of every group and every loop body
strictly ascending by their size-free bytes, and the groups by the concatenation of their rules' size-free bytes. -/
def CompiledPolicy.ordered (policy : CompiledPolicy) : Bool :=
  ascendingBytes (·.flatMap CompiledRule.sizeFree) policy.groups &&
    policy.groups.all fun rules => ascendingBytes CompiledRule.sizeFree rules && rules.all CompiledRule.ordered

/-! ## Encoding and decoding -/

namespace Policy

/-- What the encoder takes: a well-formed formula, a signature a descriptor describes, and a normal form that compiles
against it and fits the wire's field widths. Domain analysis, the types a bitmask applies to and the pairing of a
context operand's type with its subject's lie outside: no theorem of the wire needs them. -/
def WellFormed (signature : Signature) (formula : Formula) : Prop :=
  formula.WellFormed ∧ Descriptor.withinLimits signature.params = true ∧
    ((CompiledPolicy.compile signature (normalize formula)).map CompiledPolicy.fits) = some true

instance (signature : Signature) : DecidablePred (WellFormed signature) :=
  fun _ => inferInstanceAs (Decidable (_ ∧ _ ∧ _))

/-- The blob of a formula over a signature: its normal form, compiled and written; empty when it does not compile. -/
def encode (signature : Signature) (formula : Formula) : Bytes :=
  ((CompiledPolicy.compile signature (normalize formula)).map CompiledPolicy.write).getD []

/-- The formula a blob states; none unless it passes storage validation. -/
def decode (blob : Bytes) : Option Formula :=
  (parse blob).map CompiledPolicy.formula

end Policy

end Callcium
