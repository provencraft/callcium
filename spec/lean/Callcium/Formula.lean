import Callcium.Abi.Value

/-!
# Core formulas

The logical model of the policy core. A policy is a disjunction of groups. A group is a conjunction of rules. A rule is
a test, a context test or a loop whose body is again a group. `holds` is the denotation, `normalize` the canonical form,
and `Formula.WellFormed` what build-time validation accepts.
-/

namespace Callcium

/-! ## Limits and context properties -/

/-- The most path steps a test reads, counted from the arguments through every enclosing loop. -/
def MAX_PATH_DEPTH : Nat := 32

/-- The most elements a loop walks. -/
def MAX_QUANTIFIED_ARRAY_LENGTH : Nat := 256

/-- The first path-step value reserved for markers. The steps below it are field and element indices. -/
def PATH_MARKER_BASE : Nat := 0xFF00

/-- A context property ID. -/
abbrev PropertyId := Nat

/-- `msg.sender`. -/
def CTX_MSG_SENDER : PropertyId := 0x0000
/-- `msg.value`. -/
def CTX_MSG_VALUE : PropertyId := 0x0001
/-- `block.timestamp`. -/
def CTX_BLOCK_TIMESTAMP : PropertyId := 0x0002
/-- `block.number`. -/
def CTX_BLOCK_NUMBER : PropertyId := 0x0003
/-- `block.chainid`. -/
def CTX_CHAIN_ID : PropertyId := 0x0004
/-- `tx.origin`. -/
def CTX_TX_ORIGIN : PropertyId := 0x0005
/-- `block.basefee`. -/
def CTX_BASE_FEE : PropertyId := 0x0006
/-- `tx.gasprice`. -/
def CTX_GAS_PRICE : PropertyId := 0x0007
/-- The highest defined context property ID. -/
def CTX_MAX : PropertyId := CTX_GAS_PRICE

/-! ## Starting points -/

/-- What a path is relative to: a value, and inside a loop the position of the current element. -/
structure StartingPoint where
  /-- The value paths read from. -/
  value : Value
  /-- The element's index inside a loop, or `none` at the arguments. -/
  position : Option Nat
  deriving Repr

/-- The starting points, current first. The arguments lie at the bottom. -/
abbrev Stack := List StartingPoint

/-- The context properties a call provides, as raw words. -/
abbrev Context := PropertyId → Option Word

/-! ## Rules -/

/-- A comparison between a subject and its operand values. -/
inductive Comparison where
  | eq | gt | lt | gte | lte | between | in_
  | bitmaskAll | bitmaskAny | bitmaskNone
  | lengthEq | lengthGt | lengthLt | lengthGte | lengthLte | lengthBetween
  deriving Repr, BEq, DecidableEq

/-- Where a comparison's operand values come from. -/
inductive Operand where
  /-- One value. Two values for `BETWEEN` and `LENGTH_BETWEEN`. The ascending members for `IN`. -/
  | constant (values : List Word)
  /-- The value of a context property. -/
  | context (property : PropertyId)
  deriving Repr, BEq, DecidableEq

/-- A comparison, its operand, and whether the result is negated. -/
structure Operator where
  /-- Whether the result is inverted. -/
  negated : Bool
  /-- The comparison applied. -/
  comparison : Comparison
  /-- The source of the compared-against values. -/
  operand : Operand
  deriving Repr, BEq, DecidableEq

/-- How a loop's body combines over the elements. -/
inductive Quantifier where
  | all | any
  deriving Repr, BEq, DecidableEq

/-- A conjunct of a group. -/
inductive Rule where
  /-- The value at `path` from the current starting point, compared. -/
  | test (path : Path) (operator : Operator)
  /-- A context property, compared. -/
  | contextTest (property : PropertyId) (operator : Operator)
  /-- The body, a conjunction of rules, over each element of the array at `arrayPath`. -/
  | loop (quantifier : Quantifier) (arrayPath : Path) (body : List Rule)
  deriving Repr

/-- A conjunction of rules. -/
abbrev Group := List Rule

/-- A disjunction of groups: a policy, or a loop's body. -/
abbrev Formula := List Group

/-- Induction over rules, with a hypothesis for every rule of a loop's body. -/
@[induction_eliminator]
theorem Rule.induction {motive : Rule → Prop}
    (test : ∀ path operator, motive (.test path operator))
    (contextTest : ∀ property operator, motive (.contextTest property operator))
    (loop : ∀ quantifier arrayPath body, (∀ rule ∈ body, motive rule) → motive (.loop quantifier arrayPath body)) :
    ∀ rule, motive rule
  | .test path operator => test path operator
  | .contextTest property operator => contextTest property operator
  | .loop quantifier arrayPath body => loop quantifier arrayPath body fun rule _ruleIsMember =>
      Rule.induction test contextTest loop rule
termination_by rule => sizeOf rule
decreasing_by
  have := List.sizeOf_lt_of_mem _ruleIsMember
  simp_wf
  omega

/-! ## Denotation -/

/-- `left < right`, as two's complement when `signed`. -/
def lessThan (signed : Bool) (left right : Word) : Bool :=
  if signed then left.slt right else left.ult right

/-- The comparison's result on `subject` and the operand values, or `none` where it does not apply. -/
def Comparison.apply : Comparison → Value → List Word → Option Bool
  | .eq, .word bits _, [value] => some (bits == value)
  | .gt, .word bits signed, [bound] => some (lessThan signed bound bits)
  | .lt, .word bits signed, [bound] => some (lessThan signed bits bound)
  | .gte, .word bits signed, [bound] => some !(lessThan signed bits bound)
  | .lte, .word bits signed, [bound] => some !(lessThan signed bound bits)
  | .between, .word bits signed, [min, max] => some (!(lessThan signed bits min) && !(lessThan signed max bits))
  | .in_, .word bits _, members => some (members.contains bits)
  | .bitmaskAll, .word bits _, [mask] => some (bits &&& mask == mask)
  | .bitmaskAny, .word bits _, [mask] => some (bits &&& mask != 0)
  | .bitmaskNone, .word bits _, [mask] => some (bits &&& mask == 0)
  | .lengthEq, subject, [value] => subject.length?.map (· == value.toNat)
  | .lengthGt, subject, [bound] => subject.length?.map (bound.toNat < ·)
  | .lengthLt, subject, [bound] => subject.length?.map (· < bound.toNat)
  | .lengthGte, subject, [bound] => subject.length?.map fun length => !(length < bound.toNat)
  | .lengthLte, subject, [bound] => subject.length?.map fun length => !(bound.toNat < length)
  | .lengthBetween, subject, [min, max] =>
    subject.length?.map fun length => !(length < min.toNat) && !(max.toNat < length)
  | _, _, _ => none

/-- The operand values, or `none` for a context property the call does not provide. -/
def Operand.values (ctx : Context) : Operand → Option (List Word)
  | .constant values => some values
  | .context property => (ctx property).map ([·])

/-- Whether the operator holds on `subject`. A missing subject, a missing operand, or a comparison that does not apply
fails whether or not the operator is negated. -/
def Operator.holds (operator : Operator) (ctx : Context) (subject : Option Value) : Bool :=
  match subject, operator.operand.values ctx with
  | some subject, some values =>
    match operator.comparison.apply subject values with
    | some result => result != operator.negated
    | none => false
  | _, _ => false

/-- The value at `path` from the current starting point. -/
def Stack.at (stack : Stack) (path : Path) : Option Value :=
  stack.head?.bind (·.value.at path)

mutual
  /-- Whether `rule` holds with `stack` as the starting points. A loop over a value that is not an array fails. -/
  def Rule.holds (ctx : Context) (stack : Stack) : Rule → Bool
    | .test path operator => operator.holds ctx (stack.at path)
    | .contextTest property operator => operator.holds ctx ((ctx property).map (.word · false))
    | .loop quantifier arrayPath body =>
      match stack.at arrayPath with
      | some (.list elements) =>
        match quantifier with
        | .all => elements.zipIdx.all fun (element, position) =>
            Group.holds ctx (⟨element, some position⟩ :: stack) body
        | .any => elements.zipIdx.any fun (element, position) =>
            Group.holds ctx (⟨element, some position⟩ :: stack) body
      | _ => false

  /-- Whether every rule holds. -/
  def Group.holds (ctx : Context) (stack : Stack) : Group → Bool
    | [] => true
    | rule :: rules => rule.holds ctx stack && Group.holds ctx stack rules
end

/-- Whether some group holds. -/
def Formula.holds (ctx : Context) (stack : Stack) : Formula → Bool
  | [] => false
  | group :: groups => Group.holds ctx stack group || Formula.holds ctx stack groups

/-! ## Limits -/

mutual
  /-- Whether every loop the rule can reach, under every element, walks at most `MAX_QUANTIFIED_ARRAY_LENGTH` elements.
  -/
  def Rule.withinLimits (stack : Stack) : Rule → Bool
    | .loop _ arrayPath body =>
      match stack.at arrayPath with
      | some (.list elements) =>
        elements.length ≤ MAX_QUANTIFIED_ARRAY_LENGTH && elements.zipIdx.all fun (element, position) =>
          Group.withinLimits (⟨element, some position⟩ :: stack) body
      | _ => true
    | _ => true

  /-- Whether every rule is within limits. -/
  def Group.withinLimits (stack : Stack) : Group → Bool
    | [] => true
    | rule :: rules => rule.withinLimits stack && Group.withinLimits stack rules
end

/-- Whether every rule of every group is within limits. -/
def Formula.withinLimits (stack : Stack) : Formula → Bool
  | [] => true
  | group :: groups => Group.withinLimits stack group && Formula.withinLimits stack groups

/-! ## Canonical form -/

/-- The comparison equal to `NOT comparison`, for the comparisons that have one. -/
def Comparison.negation? : Comparison → Option Comparison
  | .gt => some .lte
  | .lt => some .gte
  | .gte => some .lt
  | .lte => some .gt
  | .bitmaskAny => some .bitmaskNone
  | .bitmaskNone => some .bitmaskAny
  | .lengthGt => some .lengthLte
  | .lengthLt => some .lengthGte
  | .lengthGte => some .lengthLt
  | .lengthLte => some .lengthGt
  | _ => none

/-- The comparison that holds with subject and operand exchanged, for the comparisons a context operand takes. -/
def Comparison.swap? : Comparison → Option Comparison
  | .eq => some .eq
  | .gt => some .lt
  | .lt => some .gt
  | .gte => some .lte
  | .lte => some .gte
  | _ => none

/-- The operator with NOT dropped where a positive comparison expresses the negation. -/
def Operator.positive (operator : Operator) : Operator :=
  match operator.negated, operator.comparison.negation? with
  | true, some comparison => { operator with negated := false, comparison }
  | _, _ => operator

/-- The operator with a one-member set stated as an equality. -/
def Operator.unwrapSingleton (operator : Operator) : Operator :=
  match operator.comparison, operator.operand with
  | .in_, .constant [_] => { operator with comparison := .eq }
  | _, _ => operator

/-- The canonical form of an operator: NOT only where no positive comparison expresses it, no one-member set. -/
def Operator.normalize (operator : Operator) : Operator :=
  operator.positive.unwrapSingleton

/-- A context test, restated with the lower ID as subject when it compares two context properties. -/
def Rule.contextTestBySubject (property : PropertyId) (operator : Operator) : Rule :=
  match operator.operand, operator.comparison.swap? with
  | .context other, some swapped =>
    if other < property then .contextTest other { operator with comparison := swapped, operand := .context property }
    else .contextTest property operator
  | _, _ => .contextTest property operator

/-- The operand's source: `0` for a constant, `1` for a context property. -/
def Operand.source : Operand → Nat
  | .constant _ => 0
  | .context _ => 1

/-- A prefix-free serialization of the operand's values, given its source. -/
def Operand.key : Operand → List Nat
  | .constant values => values.length :: values.map (·.toNat)
  | .context property => [property]

/-- A prefix-free serialization of an operator, in the bit order of its `opCode`: NOT, source, comparison. -/
def Operator.key (operator : Operator) : List Nat :=
  operator.negated.toNat :: operator.operand.source :: operator.comparison.ctorIdx :: operator.operand.key

mutual
  /-- A prefix-free serialization of a rule: the sort key of the canonical order. -/
  def Rule.key : Rule → List Nat
    | .contextTest property operator => 0 :: property :: operator.key
    | .test path operator => 1 :: path.length :: path ++ operator.key
    | .loop quantifier arrayPath body =>
      2 :: quantifier.ctorIdx :: arrayPath.length :: arrayPath ++ body.length :: Group.keyOf body

  /-- The keys of the rules, concatenated: the sort key of a group. -/
  def Group.keyOf : Group → List Nat
    | [] => []
    | rule :: rules => rule.key ++ Group.keyOf rules
end

theorem Comparison.ctorIdx_inj {comparison other : Comparison} (same : comparison.ctorIdx = other.ctorIdx) :
    comparison = other := by
  cases comparison <;> cases other <;> first | rfl | simp [Comparison.ctorIdx] at same

theorem Operand.key_append_inj {operand other : Operand} {rest otherRest : List Nat}
    (source : operand.source = other.source) (same : operand.key ++ rest = other.key ++ otherRest) :
    operand = other ∧ rest = otherRest := by
  cases operand <;> cases other <;> simp [Operand.source] at source <;> simp only [Operand.key] at same
  · rename_i values otherValues
    simp only [List.cons_append, List.cons.injEq] at same
    obtain ⟨sameLength, same⟩ := same
    obtain ⟨sameWords, sameRest⟩ := List.append_inj same (by simpa using sameLength)
    refine ⟨?_, sameRest⟩
    rw [List.map_inj_right fun _ _ equal => BitVec.toNat_inj.mp equal] at sameWords
    rw [sameWords]
  · simp_all

theorem Operator.key_append_inj {operator other : Operator} {rest otherRest : List Nat}
    (same : operator.key ++ rest = other.key ++ otherRest) : operator = other ∧ rest = otherRest := by
  rcases operator with ⟨negated, comparison, operand⟩
  rcases other with ⟨otherNegated, otherComparison, otherOperand⟩
  simp only [Operator.key, List.cons_append, List.cons.injEq] at same
  obtain ⟨sameNegated, sameSource, sameComparison, same⟩ := same
  obtain ⟨rfl, rfl⟩ := Operand.key_append_inj sameSource same
  cases negated <;> cases otherNegated <;> simp_all [Comparison.ctorIdx_inj sameComparison]

/-- Rule keys are a prefix-free code: a key followed by anything determines the rule and what follows. -/
theorem Rule.key_append_inj (rule : Rule) :
    ∀ (other : Rule) (rest otherRest : List Nat), rule.key ++ rest = other.key ++ otherRest →
      rule = other ∧ rest = otherRest := by
  induction rule with
  | test path operator =>
    intro other rest otherRest same
    cases other <;> simp only [Rule.key, List.cons_append, List.append_assoc, List.cons.injEq] at same <;>
      try omega
    rename_i otherPath otherOperator
    obtain ⟨-, sameLength, same⟩ := same
    obtain ⟨rfl, afterPath⟩ := List.append_inj same sameLength
    obtain ⟨rfl, rfl⟩ := Operator.key_append_inj afterPath
    exact ⟨rfl, rfl⟩
  | contextTest property operator =>
    intro other rest otherRest same
    cases other <;> simp only [Rule.key, List.cons_append, List.cons.injEq] at same <;> try omega
    obtain ⟨-, rfl, same⟩ := same
    obtain ⟨rfl, rfl⟩ := Operator.key_append_inj same
    exact ⟨rfl, rfl⟩
  | loop quantifier arrayPath body bodyInjective =>
    intro other rest otherRest same
    cases other <;> simp only [Rule.key, List.cons_append, List.append_assoc, List.cons.injEq] at same <;>
      try omega
    rename_i otherQuantifier otherPath otherBody
    obtain ⟨-, sameIndex, sameLength, same⟩ := same
    have sameQuantifier : quantifier = otherQuantifier := by
      cases quantifier <;> cases otherQuantifier <;> simp_all [Quantifier.ctorIdx]
    obtain ⟨rfl, afterPath⟩ := List.append_inj same sameLength
    simp only [List.cons.injEq] at afterPath
    obtain ⟨rfl, rfl⟩ := Group.keyOf_append_inj body bodyInjective otherBody afterPath.1 afterPath.2
    exact ⟨by rw [sameQuantifier], rfl⟩
where
  /-- Rule lists with as many members, whose rules are prefix-free, are prefix-free. -/
  Group.keyOf_append_inj (group : Group)
      (injective : ∀ rule ∈ group, ∀ (other : Rule) (rest otherRest : List Nat),
        rule.key ++ rest = other.key ++ otherRest → rule = other ∧ rest = otherRest) :
      ∀ (other : Group) {rest otherRest : List Nat}, group.length = other.length →
        Group.keyOf group ++ rest = Group.keyOf other ++ otherRest → group = other ∧ rest = otherRest := by
    induction group with
    | nil => intro other _ _ sameCount same; cases other <;> simp_all [Group.keyOf]
    | cons rule rules rulesInjective =>
      intro other rest otherRest sameCount same
      cases other with
      | nil => simp at sameCount
      | cons otherRule otherRules =>
        simp only [Group.keyOf, List.append_assoc] at same
        obtain ⟨rfl, afterRule⟩ := injective rule (by simp) otherRule _ _ same
        obtain ⟨rfl, rfl⟩ := rulesInjective (fun inner isMember => injective inner (by simp [isMember]))
          otherRules (by simpa using sameCount) afterRule
        exact ⟨rfl, rfl⟩

theorem Rule.key_injective {rule other : Rule} (same : rule.key = other.key) : rule = other :=
  (Rule.key_append_inj rule other [] [] (by simpa using same)).1

instance : DecidableEq Rule := fun rule other =>
  if same : rule.key = other.key then isTrue (Rule.key_injective same) else isFalse fun equal => same (equal ▸ rfl)

/-- Sorts ascending by a key, ordered lexicographically, and drops repeats. -/
def sortByKey {Item : Type} [DecidableEq Item] (key : Item → List Nat) (items : List Item) : List Item :=
  (items.mergeSort fun first second => decide (key first ≤ key second)).eraseDups

/-- The canonical order of a group's rules. A repeated rule adds nothing to a conjunction. -/
def sortRules (rules : List Rule) : List Rule :=
  sortByKey Rule.key rules

/-- The canonical order of a formula's groups, compared by their rules. A repeated group adds nothing to a disjunction.
-/
def sortGroups (groups : List (List Rule)) : List (List Rule) :=
  sortByKey Group.keyOf groups

/-- Whether the rule is a loop. -/
def Rule.isLoop : Rule → Bool
  | .loop .. => true
  | _ => false

/-- The array path and body of an `ALL` loop whose body contains no loop. -/
def Rule.joinable? : Rule → Option (Path × Group)
  | .loop .all arrayPath group => if group.all (!·.isLoop) then some (arrayPath, group) else none
  | _ => none

/-- Whether the rule is a joinable loop over `arrayPath`. -/
def Rule.joinsOn (arrayPath : Path) (rule : Rule) : Bool :=
  rule.joinable?.any (·.1 == arrayPath)

/-- What a test or context test compares: a path from the current starting point, or a context property. -/
inductive Subject where
  | path (path : Path)
  | property (property : PropertyId)
  deriving Repr, DecidableEq

/-- The test or context test comparing the subject by `operator`. -/
def Subject.rule (operator : Operator) : Subject → Rule
  | .path steps => .test steps operator
  | .property propertyId => .contextTest propertyId operator

/-- The bound an operator places: whether it bounds a length, whether from below, and the bound. Only an unnegated
constant `GTE`, `LTE`, `LENGTH_GTE` or `LENGTH_LTE` places one. -/
def Operator.bound? : Operator → Option (Bool × Bool × Word)
  | ⟨false, .gte, .constant [bound]⟩ => some (false, true, bound)
  | ⟨false, .lte, .constant [bound]⟩ => some (false, false, bound)
  | ⟨false, .lengthGte, .constant [bound]⟩ => some (true, true, bound)
  | ⟨false, .lengthLte, .constant [bound]⟩ => some (true, false, bound)
  | _ => none

/-- The side of a range a rule bounds: its subject, whether it bounds a length, whether from below. -/
abbrev BoundSide := Subject × Bool × Bool

/-- The side a test or context test bounds, and its bound. -/
def Rule.bound? : Rule → Option (BoundSide × Word)
  | .test path operator => operator.bound?.map fun (length, lower, bound) => ((.path path, length, lower), bound)
  | .contextTest property operator =>
    operator.bound?.map fun (length, lower, bound) => ((.property property, length, lower), bound)
  | .loop .. => none

/-- The rules bounding one side. -/
def boundsOn (rules : List Rule) (side : BoundSide) : List Rule :=
  rules.filter fun rule => (rule.bound?.map (·.1)) == some side

/-- The opposite side of a range. -/
def BoundSide.opposite : BoundSide → BoundSide
  | (subject, length, lower) => (subject, length, !lower)

/-- The range on a subject between two bounds. -/
def Subject.range (subject : Subject) (length : Bool) (lower upper : Word) : Rule :=
  subject.rule ⟨false, if length then .lengthBetween else .between, .constant [lower, upper]⟩

/-- The other bound of the lone pair the rule belongs to: one rule bounds each side of its subject. -/
def Rule.lonePartner? (rules : List Rule) (rule : Rule) : Option Rule :=
  match rule.bound? with
  | some (side, _) =>
    match boundsOn rules side, boundsOn rules side.opposite with
    | [_], [partner] => some partner
    | _, _ => none
  | none => none

/-- What a rule becomes when the lone pairs of `rules` fuse. The lower bound of a lone pair becomes the range. The upper
bound leaves, and every other rule stays. -/
def Rule.fused (rules : List Rule) (rule : Rule) : Option Rule :=
  match rule.bound?, rule.lonePartner? rules with
  | some ((subject, length, true), lower), some partner =>
    partner.bound?.map fun (_, upper) => subject.range length lower upper
  | some _, some _ => none
  | _, _ => some rule

/-- Fuses each lone pair of bounds on one subject into a range. The range is defined as the pair, so no bound needs to
be compared with another bound. -/
def fuseRanges (rules : List Rule) : List Rule :=
  rules.filterMap (Rule.fused rules)

/-- Sorts, drops repeats, fuses lone range pairs, and sorts again. Fusing counts distinct rules, so it follows dropping
repeats. A range can repeat a rule already present, so sorting follows fusing. -/
def finishRules (rules : List Rule) : List Rule :=
  sortRules (fuseRanges (sortRules rules))

/-- Whether the rule is a test, the only core rule that reads the element a loop visits. -/
def Rule.isTest : Rule → Bool
  | .test .. => true
  | _ => false

/-- Whether the rule is a context test. -/
def Rule.isContextTest : Rule → Bool
  | .contextTest .. => true
  | _ => false

/-- The context tests an `ANY` loop gives up to its group. The loop gives up all of them when its body contains a test
that reads the element. -/
def Rule.hoisted : Rule → List Rule
  | .loop .any _ body => if body.any Rule.isTest then body.filter Rule.isContextTest else []
  | _ => []

/-- The rule without the context tests it gives up. -/
def Rule.withoutHoisted : Rule → Rule
  | .loop .any arrayPath body =>
    if body.any Rule.isTest then .loop .any arrayPath (body.filter (!·.isContextTest))
    else .loop .any arrayPath body
  | rule => rule

/-- Moves the context tests of every `ANY` loop whose body reads the element into the group. The rewrite is `∃i.(P ∧
Q(i)) ≡ P ∧ ∃i.Q(i)`, and `P` runs once instead of once per element. -/
def hoistContext (rules : List Rule) : List Rule :=
  rules.map Rule.withoutHoisted ++ rules.flatMap Rule.hoisted

/-- Joins every joinable loop into the first joinable loop over the same array. `ANY` loops stay apart, because each of
them is an independent existential. -/
def joinLoops : List Rule → List Rule
  | [] => []
  | rule :: rules =>
    match rule.joinable? with
    | some (arrayPath, group) =>
      let joined := rules.filter (·.joinsOn arrayPath)
      .loop .all arrayPath (finishRules (group ++ joined.flatMap fun rule => (rule.joinable?.map (·.2)).getD [])) ::
        joinLoops (rules.filter (!·.joinsOn arrayPath))
    | none => rule :: joinLoops rules
termination_by rules => rules.length
decreasing_by
  all_goals simp_wf
  exact Nat.lt_succ_of_le (Nat.le_trans (List.length_filter_le _ _) (by simp))

mutual
  /-- The canonical form of a rule: its operator in canonical form, the lower context property as subject, and loop
  bodies in canonical form. -/
  def Rule.normalize : Rule → Rule
    | .test path operator => .test path operator.normalize
    | .contextTest property operator => Rule.contextTestBySubject property operator.normalize
    | .loop quantifier arrayPath body =>
      .loop quantifier arrayPath (finishRules (hoistContext (joinLoops (Group.normalizeEach body))))

  /-- Every rule in canonical form. -/
  def Group.normalizeEach : Group → Group
    | [] => []
    | rule :: rules => rule.normalize :: Group.normalizeEach rules
end

/-- The canonical form of a group. Its rules are in canonical form, joinable loops are joined and context tests are
hoisted out of `ANY` bodies. Repeats are dropped, lone range pairs are fused and the rules are sorted. -/
def Group.normalize (group : Group) : Group :=
  finishRules (hoistContext (joinLoops (Group.normalizeEach group)))

/-- The canonical form of a formula: groups in canonical form, sorted. -/
def normalize (formula : Formula) : Formula :=
  sortGroups (formula.map Group.normalize)

/-! ## Normal form -/

/-- Whether the operator is a one-member set. -/
def Operator.isSingletonSet (operator : Operator) : Bool :=
  match operator.comparison, operator.operand with
  | .in_, .constant [_] => true
  | _, _ => false

/-- Whether the operator keeps NOT only on a comparison no positive comparison expresses, and is no one-member set. -/
def Operator.normal (operator : Operator) : Bool :=
  (!operator.negated || operator.comparison.negation?.isNone) && !operator.isSingletonSet

/-- Whether a context test against a context property has the lower ID as subject. -/
def Rule.subjectNormal (property : PropertyId) (operator : Operator) : Bool :=
  match operator.operand, operator.comparison.swap? with
  | .context other, some _ => !decide (other < property)
  | _, _ => true

/-- The array of a joinable loop. -/
def Rule.joinPath? (rule : Rule) : Option Path :=
  rule.joinable?.map (·.1)

/-- Whether the items ascend strictly by key. -/
def strictlySorted {Item : Type} (key : Item → List Nat) (items : List Item) : Bool :=
  decide (items.Pairwise fun first second => key first < key second)

/-- Whether no two joinable loops of the group share an array. -/
def Group.joinsApart (group : Group) : Bool :=
  decide (group.Pairwise fun first second => first.joinPath? = none ∨ first.joinPath? ≠ second.joinPath?)

/-- Whether no rule belongs to a lone pair of bounds. -/
def Group.noLonePair (group : Group) : Bool :=
  group.all fun rule => (rule.lonePartner? group).isNone

/-- Whether no rule gives up context tests to the group. -/
def Group.nothingHoisted (group : Group) : Bool :=
  group.all fun rule => rule.hoisted.isEmpty

/-- Whether a group's rules are in canonical arrangement. The arrangement means strictly ascending order, joinable loops
over distinct arrays, no lone pair of bounds, and no context test left to hoist. -/
def Group.arranged (group : Group) : Bool :=
  strictlySorted Rule.key group && Group.joinsApart group && Group.noLonePair group && Group.nothingHoisted group

mutual
  /-- Whether a rule is in canonical form. -/
  def Rule.normal : Rule → Bool
    | .test _ operator => operator.normal
    | .contextTest property operator => operator.normal && Rule.subjectNormal property operator
    | .loop _ _ body => Group.rulesNormal body && Group.arranged body

  /-- Whether every rule is in canonical form. -/
  def Group.rulesNormal : Group → Bool
    | [] => true
    | rule :: rules => rule.normal && Group.rulesNormal rules
end

/-- Whether a group is in canonical form: canonical rules in canonical arrangement. -/
def Group.normal (group : Group) : Bool :=
  Group.rulesNormal group && Group.arranged group

/-- Whether a formula is in canonical form: canonical groups, strictly ascending. The rewrites of `normalize` have
nothing left to do on it. -/
def Formula.normal (formula : Formula) : Bool :=
  formula.all Group.normal && strictlySorted Group.keyOf formula

/-! ## Well-formedness -/

/-- Whether the operand has the shape the comparison takes. A context operand serves `EQ`, `GT`, `LT`, `GTE` and `LTE`.
`IN` takes at least two members, strictly ascending. Normalization turns a one-member set into `EQ`. -/
def Operator.admissible (operator : Operator) : Bool :=
  match operator.comparison, operator.operand with
  | .eq, .context property | .gt, .context property | .lt, .context property | .gte, .context property
  | .lte, .context property => property ≤ CTX_MAX
  | .eq, .constant [_] | .gt, .constant [_] | .lt, .constant [_] | .gte, .constant [_] | .lte, .constant [_]
  | .bitmaskAll, .constant [_] | .bitmaskAny, .constant [_] | .bitmaskNone, .constant [_]
  | .lengthEq, .constant [_] | .lengthGt, .constant [_] | .lengthLt, .constant [_] | .lengthGte, .constant [_]
  | .lengthLte, .constant [_] | .between, .constant [_, _] | .lengthBetween, .constant [_, _] => true
  | .in_, .constant members => 2 ≤ members.length && (members.zip members.tail).all fun (lower, upper) => lower.ult upper
  | _, _ => false

/-- Whether every step of the path is a field or element index: the marker range is reserved. -/
def Path.indicesOnly (path : Path) : Bool :=
  path.all (· < PATH_MARKER_BASE)

/-- Whether a test or context test is admissible after `depth` path steps. At the root, a test's path is nonempty. -/
def Rule.admissibleTest (root : Bool) (depth : Nat) : Rule → Bool
  | .test path operator =>
    (!root || !path.isEmpty) && path.indicesOnly && depth + path.length ≤ MAX_PATH_DEPTH && operator.admissible
  | .contextTest property operator => property ≤ CTX_MAX && operator.admissible
  | .loop .. => false

/-- Whether a loop's body contains a test that reads the element. A body of context tests alone means `P ∨ (array
empty)` under `ALL` and `P ∧ (array nonempty)` under `ANY`. Rewriting either needs to know whether the array is static,
which normalization does not. -/
def Group.readsElement (body : Group) : Bool :=
  body.any Rule.isTest

/-- Whether a root rule is admissible. A loop's body is a nonempty group of tests and context tests. -/
def Rule.admissible : Rule → Bool
  | .loop _ arrayPath body =>
    !arrayPath.isEmpty && arrayPath.indicesOnly && arrayPath.length ≤ MAX_PATH_DEPTH && !body.isEmpty &&
      body.all (·.admissibleTest false arrayPath.length) && Group.readsElement body
  | rule => rule.admissibleTest true 0

/-- Whether a formula is admissible: at least one group, and every group nonempty and made of admissible rules. -/
def Formula.admissible (formula : Formula) : Bool :=
  !formula.isEmpty && formula.all fun group => !group.isEmpty && group.all Rule.admissible

/-- What build-time validation accepts: a formula whose canonical form is admissible. Typing, operand widths, encoding
sizes and domain analysis read the signature and lie outside this predicate. -/
def Formula.WellFormed (formula : Formula) : Prop :=
  (normalize formula).admissible = true

instance : DecidablePred Formula.WellFormed :=
  fun formula => inferInstanceAs (Decidable ((normalize formula).admissible = true))

end Callcium
