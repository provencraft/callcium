import Callcium.Sketch.Language
import Callcium.Theorems.Evaluate
import Callcium.Theorems.JointBinding

/-!
# Extension sketches: worked examples

Non-normative. One section per row of design Appendix A, each with the plan's worked example. Where Appendix A states
a canonical-form rule, the section proves the equivalence the rule rests on.
-/

namespace Callcium.Sketch

open JointBinding (treasury recipient noContext call)

/-! ## Fixtures -/

/-- An address on no list. -/
def outsider : Word := 0x3c7e15a9d2084fb6e91c0a5d47b3f2e86a1d9c05

/-- An unsigned integer value. -/
def uint (amount : Nat) : Value := .word (BitVec.ofNat 256 amount) false

/-- An address value. -/
def address (account : Word) : Value := .word account false

/-- The arguments of a call. -/
def args (values : List Value) : Stack := [⟨.list values, none⟩]

/-- An unnegated comparison against constants. -/
def compare (comparison : Callcium.Comparison) (values : List Word) : Operator :=
  ⟨false, .core comparison, .core (.constant values)⟩

/-- The 32 bytes of a word, most significant first. -/
def wordBytes (word : Word) : List UInt8 :=
  (List.range 32).reverse.map fun byte => (word >>> (8 * byte)).toNat.toUInt8

/-- Calldata: a selector and static words. -/
def encodeCall (selector : List UInt8) (words : List Word) : List UInt8 :=
  selector ++ words.flatMap wordBytes

/-- `transfer(address,uint256)`. -/
def transferSelector : List UInt8 := [0xa9, 0x05, 0x9c, 0xbb]

/-- `approve(address,uint256)`. -/
def approveSelector : List UInt8 := [0x09, 0x5e, 0xa7, 0xb3]

/-- `transferFrom(address,address,uint256)`. -/
def transferFromSelector : List UInt8 := [0x23, 0xb8, 0x72, 0xdd]

/-! ## OR inside loops: `∀(P ∨ Q)`

`f((address to, uint256 amount)[] transfers)`: every transfer goes to an allowlisted address or moves at most 100. The
body is one group holding an OR rule (a reserved scope), so an `ALL` loop over the same array joins by concatenation.
-/

/-- Every transfer is allowlisted or small. -/
def allowlistedOrSmall : Formula :=
  [[.loop .all [0] [.or [[.test [0] (compare .in_ [treasury, recipient])], [.test [1] (compare .lte [100])]]]]]

theorem allowlistedOrSmall_accepts :
    Formula.holds noContext (call [(treasury, 5000), (outsider, 100)]) allowlistedOrSmall = true := by decide

theorem allowlistedOrSmall_rejects : Formula.holds noContext (call [(outsider, 101)]) allowlistedOrSmall = false := by
  decide

theorem any_swap {First Second : Type} (firsts : List First) (seconds : List Second) (holds : First → Second → Bool) :
    (firsts.any fun first => seconds.any (holds first)) = (seconds.any fun second => firsts.any (holds · second)) := by
  apply Bool.eq_iff_iff.mpr
  simp only [List.any_eq_true]
  exact ⟨fun ⟨first, isFirst, second, isSecond, holding⟩ => ⟨second, isSecond, first, isFirst, holding⟩,
    fun ⟨second, isSecond, first, isFirst, holding⟩ => ⟨first, isFirst, second, isSecond, holding⟩⟩

/-- Under `ANY` a body that is one OR splits into root alternatives, `∃i.(P ∨ Q) ≡ ∃i.P ∨ ∃i.Q`. Canonical form rejects
any body of this shape. -/
theorem any_or_splits (ctx : Context) (stack : Stack) (arrayPath : Path) (groups : Formula) :
    (Rule.loop .any arrayPath [.or groups]).holds ctx stack =
      groups.any fun group => (Rule.loop .any arrayPath group).holds ctx stack := by
  simp only [Rule.holds]
  split
  · simp only [Quantifier.holds, Group.holds, Bool.and_true, Rule.holds, Formula.holds_eq, List.any_map,
      Function.comp_def, id]
    exact any_swap _ _ fun (element : Value × Nat) (group : Group) =>
      Group.holds ctx (⟨element.1, some element.2⟩ :: stack) group
  · simp

/-! ## Nested loops: the fee rule

`fill((address maker, (address recipient, uint256 amount)[] fees)[] orders)`: every order pays the fee recipient. A loop
inside a body is a core rule. Only `Formula.WellFormed` rejects it. Theorems 15, 16, 21 and 34 carry no well-formedness
hypothesis, so the evaluator already covers the shape.
-/

/-- An order: its maker and its fees. -/
def order (fees : List (Word × Nat)) : Value :=
  .list [address outsider, .list (fees.map fun (recipient, amount) => .list [address recipient, uint amount])]

/-- Every order pays the treasury a nonzero fee. -/
def everyOrderPaysFee : Callcium.Formula :=
  [[.loop .all [0] [.loop .any [1] [.test [0] ⟨false, .eq, .constant [treasury]⟩,
    .test [1] ⟨false, .gt, .constant [0]⟩]]]]

theorem everyOrderPaysFee_accepts :
    everyOrderPaysFee.holds noContext
      (args [.list [order [(treasury, 3)], order [(recipient, 1), (treasury, 2)]]]) = true := by decide

theorem everyOrderPaysFee_rejects :
    everyOrderPaysFee.holds noContext
      (args [.list [order [(treasury, 3)], order [(recipient, 2)]]]) = false := by decide

theorem everyOrderPaysFee_passes :
    everyOrderPaysFee.evaluateValues noContext
      (args [.list [order [(treasury, 3)], order [(recipient, 1), (treasury, 2)]]]) = .pass := by decide

/-- Nesting multiplies work: the reason for `MAX_WORK`. -/
theorem everyOrderPaysFee_work :
    Formula.work (everyOrderPaysFee.map Group.ofCore) =
      MAX_QUANTIFIED_ARRAY_LENGTH * (MAX_QUANTIFIED_ARRAY_LENGTH * 2) := by
  simp [everyOrderPaysFee, Formula.work, Group.work, Rule.work, Group.ofCore, Rule.ofCore, Operator.ofCore]

/-! ## References: `from != to`

`transferFrom(address from, address to, uint256 amount)`: the operand is the value at another path (`source = 10`).
-/

/-- The sender is not the recipient. -/
def fromIsNotTo : Formula := [[.test [0] ⟨true, .core .eq, .reference 0 [1]⟩]]

theorem fromIsNotTo_accepts :
    Formula.holds noContext (args [address treasury, address recipient, uint 1]) fromIsNotTo = true := by decide

theorem fromIsNotTo_rejects :
    Formula.holds noContext (args [address treasury, address treasury, uint 1]) fromIsNotTo = false := by decide

/-! ## Outer tests and `Same`: parallel arrays

`execute(address[] targets, uint256[] values)`: for every `i`, `targets[i]` is allowlisted or `values[i] == 0`. The body
reads `values[i]` with an outer test one starting point away, indexed by `Same 0`, the loop's position. A shorter
`values` leaves `values[i]` unresolved: the test fails, a group-local fault.
-/

/-- Every target is allowlisted or receives nothing. -/
def allowlistedOrNoValue : Formula :=
  [[.loop .all [0] [.or [[.test [] (compare .in_ [treasury, recipient])],
    [.outerTest 1 [1, same 0] (compare .eq [0])]]]]]

theorem allowlistedOrNoValue_accepts :
    Formula.holds noContext (args [.list [address treasury, address outsider], .list [uint 7, uint 0]])
      allowlistedOrNoValue = true := by decide

theorem allowlistedOrNoValue_rejects :
    Formula.holds noContext (args [.list [address treasury, address outsider], .list [uint 0, uint 7]])
      allowlistedOrNoValue = false := by decide

/-- Under `ANY` a rule that reads no position leaves the loop as a conjunct, `∃i.(P ∧ Q(i)) ≡ P ∧ ∃i.Q(i)`. Canonical
form rejects it there. -/
theorem any_moves_out (ctx : Context) (stack : Stack) (arrayPath : Path) (rule : Rule) (group : Group)
    (held : Bool) (independent : ∀ point, rule.holds ctx (point :: stack) = held) :
    (Rule.loop .any arrayPath (rule :: group)).holds ctx stack =
      (held && (Rule.loop .any arrayPath group).holds ctx stack) := by
  simp only [Rule.holds]
  split <;> simp [Quantifier.holds, independent]
  cases held <;> simp

/-- Under `ALL` an OR group that reads no position leaves the loop as a root alternative, `∀i.(P ∨ Q(i)) ≡ P ∨ ∀i.Q(i)`.
Canonical form rejects such a group. -/
theorem all_moves_out (ctx : Context) (stack : Stack) (arrayPath : Path) (elements : List Value)
    (found : read stack 0 arrayPath = some (.list elements)) (outer : Group) (groups : Formula) (held : Bool)
    (independent : ∀ point, Group.holds ctx (point :: stack) outer = held) :
    (Rule.loop .all arrayPath [.or (outer :: groups)]).holds ctx stack =
      (held || (Rule.loop .all arrayPath [.or groups]).holds ctx stack) := by
  simp only [Group.holds_eq] at independent
  simp only [Rule.holds, found, Quantifier.holds, Group.holds_eq, List.all_cons, List.all_nil, Bool.and_true,
    Rule.holds, Formula.holds_eq, List.any_cons, independent, List.all_map]
  cases held <;> simp [Function.comp_def]

/-- An `ALL` body that reads no position holds exactly when its rules do or the array is empty, `∀i.P ≡ P ∨ (array
empty)`. Canonical form rejects it. The author writes the two root groups instead. -/
theorem all_independent_body (ctx : Context) (stack : Stack) (arrayPath : Path) (elements : List Value)
    (found : read stack 0 arrayPath = some (.list elements)) (body : Group) (held : Bool)
    (independent : ∀ point, Group.holds ctx (point :: stack) body = held) :
    (Rule.loop .all arrayPath body).holds ctx stack = (held || elements.isEmpty) := by
  simp only [Group.holds_eq] at independent
  simp only [Rule.holds, found, Quantifier.holds, List.all_map, Function.comp_def, Group.holds_eq, independent]
  cases held <;> cases elements <;> simp

/-- Beside a rule that reads the position, a rule that reads none stays inside `ALL`. An empty array passes the loop
whatever the outer rule says, `∀i.(P ∧ Q(i)) ≢ P ∧ ∀i.Q(i)`. A context test is such a rule. -/
theorem all_keeps_conjunct :
    let senderIsTreasury : Callcium.Rule := .contextTest CTX_MSG_SENDER ⟨false, .eq, .constant [treasury]⟩
    let paysTreasury : Callcium.Rule := .test [0] ⟨false, .eq, .constant [treasury]⟩
    Callcium.Formula.holds noContext (call []) [[.loop .all [0] [senderIsTreasury, paysTreasury]]] = true ∧
      Callcium.Formula.holds noContext (call []) [[senderIsTreasury, .loop .all [0] [paysTreasury]]] = false := by
  decide

/-- A context test reads no position. -/
theorem contextTest_independent (property : PropertyId) (operator : Callcium.Operator) (ctx : Context)
    (stack : Stack) (point : StartingPoint) :
    (Rule.ofCore (.contextTest property operator)).holds ctx (point :: stack) =
      (Callcium.Rule.contextTest property operator).holds ctx stack :=
  rfl

/-- An outer test over field and element indices reads no position. -/
theorem outerTest_independent (up : Nat) (path : Path) (indices : path.indicesOnly = true)
    (operator : Callcium.Operator) (ctx : Context) (stack : Stack) (point : StartingPoint) :
    (Rule.outerTest (up + 1) path (.ofCore operator)).holds ctx (point :: stack) =
      (Rule.outerTest up path (.ofCore operator)).holds ctx stack := by
  simp [Rule.holds, read, navigate_indices _ _ indices]
  rfl

/-! ## `COUNT`: exactly one fee transfer

`f((address to, uint256 amount)[] transfers)`: exactly one transfer goes to the treasury (`quantifier = 0x03`).
-/

/-- Exactly one transfer pays the treasury. -/
def oneFeeTransfer : Formula :=
  [[.loop (.count (compare .eq [1])) [0] [.test [0] (compare .eq [treasury])]]]

theorem oneFeeTransfer_accepts :
    Formula.holds noContext (call [(recipient, 5), (treasury, 1)]) oneFeeTransfer = true := by decide

theorem oneFeeTransfer_rejects_two :
    Formula.holds noContext (call [(treasury, 5), (treasury, 1)]) oneFeeTransfer = false := by decide

theorem oneFeeTransfer_rejects_none : Formula.holds noContext (call [(recipient, 5)]) oneFeeTransfer = false := by
  decide

/-! ## Aggregates: `sum ≤ msg.value` and distinct recipients

`f((address to, uint256 amount)[] transfers)`, scope `0x03`. The sum is over naturals and takes `uintN` values only: a
sum past `2²⁵⁶` compares above every operand rather than wrapping.
-/

/-- A call that sends `value`. -/
def sending (value : Nat) : Context := fun property => if property = CTX_MSG_VALUE then some (BitVec.ofNat 256 value)
  else none

/-- The amounts sum to at most `msg.value`. -/
def coveredByValue : Formula :=
  [[.aggregate (.sum ⟨false, .core .lte, .core (.context CTX_MSG_VALUE)⟩) [0] [1]]]

theorem coveredByValue_accepts :
    Formula.holds (sending 1000) (call [(treasury, 400), (recipient, 600)]) coveredByValue = true := by decide

theorem coveredByValue_rejects :
    Formula.holds (sending 1000) (call [(treasury, 400), (recipient, 601)]) coveredByValue = false := by decide

theorem coveredByValue_rejects_overflow :
    Formula.holds (sending 1000) (call [(treasury, 2 ^ 256 - 1), (recipient, 1)]) coveredByValue = false := by decide

/-- No two transfers share a recipient. -/
def distinctRecipients : Formula := [[.aggregate .distinct [0] [0]]]

theorem distinctRecipients_accepts :
    Formula.holds noContext (call [(treasury, 1), (recipient, 1)]) distinctRecipients = true := by decide

theorem distinctRecipients_rejects :
    Formula.holds noContext (call [(treasury, 1), (treasury, 2)]) distinctRecipients = false := by decide

/-! ## Decode: an inner `transfer` from `execute`

`execute(address target, uint256 value, bytes data)`: `data` is a `transfer` to the treasury of at most 1000 (scope
`0x05`). A selector mismatch fails the rule, which is group-local.
-/

/-- The inner call pays the treasury at most 1000. -/
def innerTransfer : Formula :=
  [[.decode (some transferSelector) 2 [2] [.test [0] (compare .eq [treasury]), .test [1] (compare .lte [1000])]]]

/-- An `execute` call carrying `data`. -/
def execute (data : List UInt8) : Stack := args [address outsider, uint 0, .bytes data]

theorem innerTransfer_accepts :
    Formula.holds noContext (execute (encodeCall transferSelector [treasury, 1000])) innerTransfer = true := by decide

theorem innerTransfer_rejects :
    Formula.holds noContext (execute (encodeCall transferSelector [treasury, 1001])) innerTransfer = false := by decide

theorem innerTransfer_rejects_selector :
    Formula.holds noContext (execute (encodeCall approveSelector [treasury, 1000])) innerTransfer = false := by decide

/-! ## Decode inside a loop: a multicall of allowed calls

`multicall(bytes[] calls)`: every call is a `transfer` to an allowlisted address or an `approve` of the treasury. The
body is one OR whose groups each decode the element itself, with an empty path.
-/

/-- Every call is an allowed `transfer` or `approve`. -/
def allowedCalls : Formula :=
  [[.loop .all [0] [.or
    [[.decode (some transferSelector) 2 [] [.test [0] (compare .in_ [treasury, recipient])]],
     [.decode (some approveSelector) 2 [] [.test [0] (compare .eq [treasury])]]]]]]

theorem allowedCalls_accepts :
    Formula.holds noContext
      (args [.list [.bytes (encodeCall transferSelector [recipient, 5]),
        .bytes (encodeCall approveSelector [treasury, 10])]]) allowedCalls = true := by decide

theorem allowedCalls_rejects :
    Formula.holds noContext
      (args [.list [.bytes (encodeCall transferSelector [recipient, 5]),
        .bytes (encodeCall transferFromSelector [treasury, recipient, 10])]]) allowedCalls = false := by decide

/-! ## Prefix tests: the selector of `data` in a set

`execute(address target, uint256 value, bytes data)`: `bytes4(data)` is `transfer` or `approve` (`comparison` in
`0x08`–`0x0F`). The prefix is as wide as the operand. A `data` shorter than the prefix fails.
-/

/-- The inner call is a `transfer` or an `approve`. Members ascend by their words. -/
def selectorAllowed : Formula :=
  [[.test [2] ⟨false, .prefix_ 4 .in_, .core (.constant [leftAligned approveSelector, leftAligned transferSelector])⟩]]

theorem selectorAllowed_accepts :
    Formula.holds noContext (execute (encodeCall transferSelector [treasury, 1])) selectorAllowed = true := by decide

theorem selectorAllowed_rejects :
    Formula.holds noContext (execute (encodeCall transferFromSelector [treasury, recipient, 1])) selectorAllowed =
      false := by decide

theorem selectorAllowed_rejects_short :
    Formula.holds noContext (execute (transferSelector.take 3)) selectorAllowed = false := by decide

end Callcium.Sketch
