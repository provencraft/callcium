import Callcium.Theorems.Normalize

/-!
# Extension sketches: language

Non-normative. The planned extensions of design Appendix A at the value level, as one language that adds cases to the
core and keeps the meaning of the core's (`ofCore_holds`). `Same` takes path steps from the marker range the core
reserves; OR inside loops is a rule of its own. Nested loops need no new case: the core already denotes them, and only
`Formula.WellFormed` rejects them. Validation, canonical form and evaluation arrive with each extension in Phase C.

Not sketched: hash tests take the shape of prefix tests with keccak-256 as the projection; extended comparisons
(`comparison = 0x1F`) and expression operands (`source = 11`) have no value-level content yet.
-/

namespace Callcium.Sketch

/-! ## Paths -/

/-- The number of `Same` markers: steps from `PATH_MARKER_BASE` up to it name the positions of the enclosing loops. -/
def SAME_LEVELS : Nat := 16

/-- The path step `Same level`: the position of the loop `level` starting points out. -/
def same (level : Nat) : Nat := PATH_MARKER_BASE + level

/-- The value at `path` from `value`. A step below `PATH_MARKER_BASE` is a field or element index; `Same level` reads
the position of `stack[level]`, counted from the rule's current starting point whichever starting point the path
starts from; other markers lead nowhere. -/
def navigate (stack : Stack) : Value → Path → Option Value
  | value, [] => some value
  | .list items, step :: steps =>
    let index :=
      if step < PATH_MARKER_BASE then some step
      else if step - PATH_MARKER_BASE < SAME_LEVELS then stack[step - PATH_MARKER_BASE]?.bind (·.position)
      else none
    index.bind fun index => items[index]?.bind (navigate stack · steps)
  | _, _ :: _ => none

/-- The value at `path` from the starting point `up` levels out. -/
def read (stack : Stack) (up : Nat) (path : Path) : Option Value :=
  stack[up]?.bind (navigate stack ·.value path)

/-! ## Operators -/

/-- The word of up to 32 bytes, left-aligned. -/
def leftAligned (bytes : List UInt8) : Word :=
  BitVec.ofNat 256 (bytes.foldl (fun word byte => word * 256 + byte.toNat) 0 * 256 ^ (32 - bytes.length))

/-- A comparison: a core one, or a prefix test (`comparison` in `0x08`–`0x0F`). -/
inductive Comparison where
  | core (comparison : Callcium.Comparison)
  /-- The core comparison on the first `width` bytes of a `bytes` or `string` value, left-aligned. `width` is the
  operand's width, `bytesN`; values erase it, so the sketch carries it here. -/
  | prefix_ (width : Nat) (comparison : Callcium.Comparison)
  deriving Repr, DecidableEq

/-- The comparison's result, or `none` where it does not apply. A value shorter than the prefix does not apply. -/
def Comparison.apply : Comparison → Value → List Word → Option Bool
  | .core comparison, subject, values => comparison.apply subject values
  | .prefix_ width comparison, .bytes data, values =>
    if width ≤ data.length ∧ width ≤ 32 then comparison.apply (.word (leftAligned (data.take width)) false) values
    else none
  | .prefix_ .., _, _ => none

/-- An operand: a core one, or a reference (`source = 10`). -/
inductive Operand where
  | core (operand : Callcium.Operand)
  /-- The word at `path` from the starting point `up` levels out. -/
  | reference (up : Nat) (path : Path)
  deriving Repr, DecidableEq

/-- The operand values, or `none` for a missing context property or a reference that reads no word. -/
def Operand.values (ctx : Context) (stack : Stack) : Operand → Option (List Word)
  | .core operand => operand.values ctx
  | .reference up path =>
    match read stack up path with
    | some (.word bits _) => some [bits]
    | _ => none

/-- A comparison, its operand, and whether the result is negated. -/
structure Operator where
  negated : Bool
  comparison : Comparison
  operand : Operand
  deriving Repr, DecidableEq

/-- Whether the operator holds on `subject`, as `Callcium.Operator.holds`. -/
def Operator.holds (operator : Operator) (ctx : Context) (stack : Stack) (subject : Option Value) : Bool :=
  match subject, operator.operand.values ctx stack with
  | some subject, some values =>
    match operator.comparison.apply subject values with
    | some result => result != operator.negated
    | none => false
  | _, _ => false

/-- The comparison over naturals, for the comparisons a sum takes. -/
def applyNat : Callcium.Comparison → Nat → List Nat → Option Bool
  | .eq, subject, [value] => some (subject == value)
  | .gt, subject, [bound] => some (bound < subject)
  | .lt, subject, [bound] => some (subject < bound)
  | .gte, subject, [bound] => some !(subject < bound)
  | .lte, subject, [bound] => some !(bound < subject)
  | .between, subject, [min, max] => some (!(subject < min) && !(max < subject))
  | .in_, subject, members => some (members.contains subject)
  | _, _, _ => none

/-- Whether the operator holds on a natural, comparing over naturals. -/
def Operator.holdsNat (operator : Operator) (ctx : Context) (stack : Stack) (subject : Nat) : Bool :=
  match operator.comparison, operator.operand.values ctx stack with
  | .core comparison, some values =>
    match applyNat comparison subject (values.map (·.toNat)) with
    | some result => result != operator.negated
    | none => false
  | _, _ => false

/-! ## Rules -/

/-- How a loop's body combines over the elements. -/
inductive Quantifier where
  | all | any
  /-- The number of elements whose body holds, compared (`quantifier = 0x03`). -/
  | count (operator : Operator)
  deriving Repr, DecidableEq

/-- An aggregate over the values an array's elements hold at one path (scope `0x03`). -/
inductive Aggregate where
  /-- The sum over naturals of `uintN` values, compared. -/
  | sum (operator : Operator)
  | distinct
  /-- Ascending; `strict` excludes equal neighbours. -/
  | sorted (strict : Bool)
  deriving Repr, DecidableEq

/-- A conjunct of a group. -/
inductive Rule where
  /-- The value at `path` from the current starting point, compared. -/
  | test (path : Path) (operator : Operator)
  /-- A context property, compared. -/
  | contextTest (property : PropertyId) (operator : Operator)
  /-- The body over each element of the array at `arrayPath`. -/
  | loop (quantifier : Quantifier) (arrayPath : Path) (body : List Rule)
  /-- The value at `path` from the starting point `up` levels out, compared (scope `0x04`). -/
  | outerTest (up : Nat) (path : Path) (operator : Operator)
  /-- The values at `elemPath` in each element of the array at `arrayPath`, aggregated (scope `0x03`). Each element is
  pushed as a starting point at its position, so `Same` level 0 in `elemPath` reads that position. -/
  | aggregate (aggregate : Aggregate) (arrayPath elemPath : Path)
  /-- The body over the arguments the `bytes` at `path` decode to (scope `0x05`), pushed as a starting point without a
  position: `up` and `Same` count across it. The sketch decodes `fieldCount` unsigned words after an optional selector;
  the descriptor and the ABI decoder arrive with M2. -/
  | decode (selector : Option (List UInt8)) (fieldCount : Nat) (path : Path) (body : List Rule)
  /-- Some group holds: OR inside a loop body (a reserved scope). -/
  | or (groups : List (List Rule))
  deriving Repr

/-- A conjunction of rules. -/
abbrev Group := List Rule

/-- A disjunction of groups. -/
abbrev Formula := List Group

/-! ## Denotation -/

/-- The word a value holds, if it is one. -/
def Value.word? : Value → Option Word
  | .word bits _ => some bits
  | _ => none

/-- Whether `next` may follow `prev` in ascending order. -/
def ascends (strict : Bool) : Value → Value → Bool
  | .word prev signed, .word next _ => if strict then lessThan signed prev next else !(lessThan signed next prev)
  | _, _ => false

/-- Whether the aggregate holds on the values. Every value must be a word. -/
def Aggregate.holds (ctx : Context) (stack : Stack) (aggregate : Aggregate) (values : List Value) : Bool :=
  match values.mapM Value.word?, aggregate with
  | some words, .sum operator => operator.holdsNat ctx stack (words.map (·.toNat)).sum
  | some words, .distinct => decide words.Nodup
  | some _, .sorted strict => (values.zip values.tail).all fun (prev, next) => ascends strict prev next
  | none, _ => false

/-- The arguments `data` decodes to: `fieldCount` unsigned words after the selector, or `none` when the selector does
not match or `data` is short. -/
def decodeCall (selector : Option (List UInt8)) (fieldCount : Nat) (data : List UInt8) : Option Value :=
  let args := match selector with
    | some selector => if data.take selector.length == selector then some (data.drop selector.length) else none
    | none => some data
  args.bind fun args =>
    if 32 * fieldCount ≤ args.length then
      some (.list ((List.range fieldCount).map fun field =>
        .word (leftAligned ((args.drop (32 * field)).take 32)) false))
    else none

/-- Whether the quantifier holds on the body's results at the elements, in index order. -/
def Quantifier.holds (ctx : Context) (stack : Stack) : Quantifier → List Bool → Bool
  | .all, results => results.all id
  | .any, results => results.any id
  | .count operator, results => operator.holds ctx stack (some (.word (BitVec.ofNat 256 (results.count true)) false))

mutual
  /-- Whether `rule` holds with `stack` as the starting points. -/
  def Rule.holds (ctx : Context) (stack : Stack) : Rule → Bool
    | .test path operator => operator.holds ctx stack (read stack 0 path)
    | .contextTest property operator => operator.holds ctx stack ((ctx property).map (.word · false))
    | .loop quantifier arrayPath body =>
      match read stack 0 arrayPath with
      | some (.list elements) =>
        quantifier.holds ctx stack (elements.zipIdx.map fun (element, position) =>
          Group.holds ctx (⟨element, some position⟩ :: stack) body)
      | _ => false
    | .outerTest up path operator => operator.holds ctx stack (read stack up path)
    | .aggregate aggregate arrayPath elemPath =>
      match read stack 0 arrayPath with
      | some (.list elements) =>
        match elements.zipIdx.mapM fun (element, position) =>
          navigate (⟨element, some position⟩ :: stack) element elemPath with
        | some values => aggregate.holds ctx stack values
        | none => false
      | _ => false
    | .decode selector fieldCount path body =>
      match read stack 0 path with
      | some (.bytes data) =>
        match decodeCall selector fieldCount data with
        | some args => Group.holds ctx (⟨args, none⟩ :: stack) body
        | none => false
      | _ => false
    | .or groups => Formula.holds ctx stack groups

  /-- Whether some group holds. -/
  def Formula.holds (ctx : Context) (stack : Stack) : Formula → Bool
    | [] => false
    | group :: groups => Group.holds ctx stack group || Formula.holds ctx stack groups

  /-- Whether every rule holds. -/
  def Group.holds (ctx : Context) (stack : Stack) : Group → Bool
    | [] => true
    | rule :: rules => rule.holds ctx stack && Group.holds ctx stack rules
end

/-! ## Work -/

mutual
  /-- The design's work bound, with every array at `MAX_QUANTIFIED_ARRAY_LENGTH` elements: a test costs one, plus one
  per reference; a loop costs its body once per element; `DISTINCT` costs one per pair of elements, other aggregates
  one per element; a decode costs one plus its body, a placeholder until `MAX_WORK` is set; an OR costs its groups. -/
  def Rule.work : Rule → Nat
    | .test _ operator | .outerTest _ _ operator | .contextTest _ operator =>
      match operator.operand with
      | .reference .. => 2
      | .core _ => 1
    | .loop _ _ body => MAX_QUANTIFIED_ARRAY_LENGTH * Group.work body
    | .aggregate .distinct .. => MAX_QUANTIFIED_ARRAY_LENGTH * (MAX_QUANTIFIED_ARRAY_LENGTH - 1) / 2
    | .aggregate .. => MAX_QUANTIFIED_ARRAY_LENGTH
    | .decode _ _ _ body => 1 + Group.work body
    | .or groups => Formula.work groups

  /-- The work of every group. -/
  def Formula.work : Formula → Nat
    | [] => 0
    | group :: groups => Group.work group + Formula.work groups

  /-- The work of every rule. -/
  def Group.work : Group → Nat
    | [] => 0
    | rule :: rules => rule.work + Group.work rules
end

/-! ## The core embeds unchanged -/

/-- The core operator, in the extended language. -/
def Operator.ofCore (operator : Callcium.Operator) : Operator :=
  ⟨operator.negated, .core operator.comparison, .core operator.operand⟩

/-- The core quantifier, in the extended language. -/
def Quantifier.ofCore : Callcium.Quantifier → Quantifier
  | .all => .all
  | .any => .any

mutual
  /-- The core rule, in the extended language. -/
  def Rule.ofCore : Callcium.Rule → Rule
    | .test path operator => .test path (.ofCore operator)
    | .contextTest property operator => .contextTest property (.ofCore operator)
    | .loop quantifier arrayPath body => .loop (.ofCore quantifier) arrayPath (Group.ofCore body)

  /-- The core group, in the extended language. -/
  def Group.ofCore : Callcium.Group → Group
    | [] => []
    | rule :: rules => Rule.ofCore rule :: Group.ofCore rules
end

mutual
  /-- Whether every path of the core rule holds indices only, as `Formula.WellFormed` requires. -/
  def Rule.coreIndicesOnly : Callcium.Rule → Bool
    | .test path _ => path.indicesOnly
    | .contextTest .. => true
    | .loop _ arrayPath body => arrayPath.indicesOnly && Group.coreIndicesOnly body

  /-- Whether every path of every rule holds indices only. -/
  def Group.coreIndicesOnly : Callcium.Group → Bool
    | [] => true
    | rule :: rules => Rule.coreIndicesOnly rule && Group.coreIndicesOnly rules
end

@[simp] theorem Group.holds_eq (ctx : Context) (stack : Stack) (group : Group) :
    Group.holds ctx stack group = group.all (·.holds ctx stack) := by
  induction group <;> simp [Group.holds, *]

@[simp] theorem Formula.holds_eq (ctx : Context) (stack : Stack) (formula : Formula) :
    Formula.holds ctx stack formula = formula.any (Group.holds ctx stack) := by
  induction formula <;> simp [Formula.holds, *]

@[simp] theorem Group.ofCore_eq (group : Callcium.Group) : Group.ofCore group = group.map Rule.ofCore := by
  induction group <;> simp [Group.ofCore, *]

@[simp] theorem Group.coreIndicesOnly_eq (group : Callcium.Group) :
    Group.coreIndicesOnly group = group.all Rule.coreIndicesOnly := by
  induction group <;> simp [Group.coreIndicesOnly, *]

theorem navigate_indices (stack : Stack) (path : Callcium.Path) (indices : path.indicesOnly = true) :
    ∀ value, navigate stack value path = value.at path := by
  induction path with
  | nil => intro value; cases value <;> rfl
  | cons step steps rest =>
    simp only [Path.indicesOnly, List.all_cons, Bool.and_eq_true, decide_eq_true_eq] at indices
    intro value
    cases value <;> simp only [navigate, Value.at, ite_eq_left indices.1, Option.bind_some]
    rename_i items
    cases items[step]? <;> simp [rest indices.2]

theorem read_indices (stack : Stack) (path : Callcium.Path) (indices : path.indicesOnly = true) :
    read stack 0 path = stack.at path := by
  cases stack <;> simp [read, Stack.at, navigate_indices _ _ indices]

theorem Operator.ofCore_holds (operator : Callcium.Operator) (ctx : Context) (stack : Stack)
    (subject : Option Value) : (Operator.ofCore operator).holds ctx stack subject = operator.holds ctx subject :=
  rfl

theorem Group.ofCore_holds (group : Callcium.Group)
    (preserved : ∀ rule ∈ group, ∀ ctx stack, Rule.coreIndicesOnly rule = true →
      (Rule.ofCore rule).holds ctx stack = rule.holds ctx stack)
    (ctx : Context) (stack : Stack) (indices : Group.coreIndicesOnly group = true) :
    Group.holds ctx stack (Group.ofCore group) = Callcium.Group.holds ctx stack group := by
  simp only [Group.coreIndicesOnly_eq, List.all_eq_true] at indices
  simp only [Group.ofCore_eq, Group.holds_eq, Callcium.Group.holds_eq, List.all_map]
  exact all_congr_mem fun rule isMember => preserved rule isMember ctx stack (indices rule isMember)

/-- The core's cases keep their meaning in the extended language, on paths of indices. -/
theorem Rule.ofCore_holds (rule : Callcium.Rule) :
    ∀ ctx stack, Rule.coreIndicesOnly rule = true → (Rule.ofCore rule).holds ctx stack = rule.holds ctx stack := by
  induction rule with
  | test path operator =>
    intro ctx stack indices
    simp only [Rule.ofCore, Rule.holds, read_indices stack path indices]
    rfl
  | contextTest property operator => intro ctx stack _; rfl
  | loop quantifier arrayPath body bodyPreserved =>
    intro ctx stack indices
    simp only [Rule.coreIndicesOnly, Bool.and_eq_true] at indices
    simp only [Rule.ofCore, Rule.holds, Callcium.Rule.holds, read_indices stack arrayPath indices.1]
    rcases stack.at arrayPath with _ | (_ | _ | elements) <;> try rfl
    cases quantifier <;> simp only [Quantifier.ofCore, Quantifier.holds, List.all_map, List.any_map,
      Function.comp_def, id, Group.ofCore_holds body bodyPreserved _ _ indices.2]

/-- A core formula whose paths hold indices only keeps its meaning in the extended language. -/
theorem ofCore_holds (formula : Callcium.Formula) (ctx : Context) (stack : Stack)
    (indices : formula.all Group.coreIndicesOnly = true) :
    Formula.holds ctx stack (formula.map Group.ofCore) = Callcium.Formula.holds ctx stack formula := by
  simp only [List.all_eq_true] at indices
  simp only [Formula.holds_eq, Callcium.Formula.holds_eq, List.any_map]
  exact any_congr_mem fun group isMember =>
    Group.ofCore_holds group (fun rule _ => Rule.ofCore_holds rule) ctx stack (indices group isMember)

end Callcium.Sketch
