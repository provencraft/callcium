import Callcium.Formula

/-!
# Canonical form

Theorem 22: normalizing keeps the meaning. Theorem 23: normalizing twice changes nothing. Theorem 25: normalizing keeps
the limits. Theorem 32: the author's order and repetitions do not reach the canonical form. Theorem 33: normal forms
are exactly the fixed points of `normalize`. The last two follow from two facts per level: `normalize` emits a normal
form, and normalizing a normal form changes nothing.
-/

namespace Callcium

/-! ## Equations -/

@[simp] theorem Group.holds_eq (ctx : Context) (stack : Stack) (group : Group) :
    Group.holds ctx stack group = group.all (·.holds ctx stack) := by
  induction group <;> simp [Group.holds, *]

@[simp] theorem Formula.holds_eq (ctx : Context) (stack : Stack) (formula : Formula) :
    Formula.holds ctx stack formula = formula.any (Group.holds ctx stack) := by
  induction formula <;> simp [Formula.holds, *]

@[simp] theorem Group.withinLimits_eq (stack : Stack) (group : Group) :
    Group.withinLimits stack group = group.all (·.withinLimits stack) := by
  induction group <;> simp [Group.withinLimits, *]

@[simp] theorem Formula.withinLimits_eq (stack : Stack) (formula : Formula) :
    Formula.withinLimits stack formula = formula.all (Group.withinLimits stack) := by
  induction formula <;> simp [Formula.withinLimits, *]

@[simp] theorem Group.normalizeEach_eq (group : Group) : Group.normalizeEach group = group.map Rule.normalize := by
  induction group <;> simp [Group.normalizeEach, *]

theorem Rule.normalize_loop (quantifier : Quantifier) (arrayPath : Path) (body : Group) :
    (Rule.loop quantifier arrayPath body).normalize = .loop quantifier arrayPath (Group.normalize body) :=
  rfl

/-! ## Lists -/

theorem all_congr_mem {Item : Type} {items : List Item} {first second : Item → Bool}
    (same : ∀ item ∈ items, first item = second item) : items.all first = items.all second := by
  induction items <;> simp_all

theorem any_congr_mem {Item : Type} {items : List Item} {first second : Item → Bool}
    (same : ∀ item ∈ items, first item = second item) : items.any first = items.any second := by
  induction items <;> simp_all

theorem all_and_distrib {Item : Type} (items : List Item) (first second : Item → Bool) :
    (items.all fun item => first item && second item) = (items.all first && items.all second) := by
  induction items <;> simp_all [Bool.and_assoc, Bool.and_left_comm]

theorem all_eq_of_members {Item : Type} {items other : List Item} (same : ∀ item, item ∈ items ↔ item ∈ other)
    (predicate : Item → Bool) : items.all predicate = other.all predicate := by
  apply Bool.eq_iff_iff.mpr
  simp [List.all_eq_true, same]

theorem any_eq_of_members {Item : Type} {items other : List Item} (same : ∀ item, item ∈ items ↔ item ∈ other)
    (predicate : Item → Bool) : items.any predicate = other.any predicate := by
  apply Bool.eq_iff_iff.mpr
  simp [List.any_eq_true, same]

theorem eraseDups_sublist {Item : Type} [DecidableEq Item] : ∀ items : List Item, items.eraseDups.Sublist items
  | [] => by simp
  | item :: items => by
    rw [List.eraseDups_cons]
    exact ((eraseDups_sublist _).trans (List.filter_sublist)).cons_cons item
termination_by items => items.length
decreasing_by exact Nat.lt_succ_of_le (List.length_filter_le _ _)

theorem nodup_eraseDups {Item : Type} [DecidableEq Item] : ∀ items : List Item, items.eraseDups.Nodup
  | [] => List.nodup_nil
  | item :: items => by
    rw [List.eraseDups_cons]
    exact List.nodup_cons.mpr ⟨by simp, nodup_eraseDups _⟩
termination_by items => items.length
decreasing_by exact Nat.lt_succ_of_le (List.length_filter_le _ _)

theorem eraseDups_of_nodup {Item : Type} [DecidableEq Item] : ∀ {items : List Item}, items.Nodup →
    items.eraseDups = items
  | [], _ => rfl
  | item :: items, nodup => by
    obtain ⟨fresh, rest⟩ := List.nodup_cons.mp nodup
    rw [List.eraseDups_cons, List.filter_eq_self.mpr fun other isMember => by
      simpa using fun equal : other = item => fresh (equal ▸ isMember), eraseDups_of_nodup rest]

theorem any_and_const {Item : Type} (items : List Item) (constant : Bool) (predicate : Item → Bool) :
    (items.any fun item => constant && predicate item) = (constant && items.any predicate) := by
  induction items <;> cases constant <;> simp_all

theorem filterMap_of_forall_some {Item : Type} {function : Item → Option Item} :
    ∀ {items : List Item}, (∀ item ∈ items, function item = some item) → items.filterMap function = items
  | [], _ => rfl
  | item :: items, keeps => by
    rw [List.filterMap_cons, keeps item (by simp)]
    exact congrArg _ (filterMap_of_forall_some fun other isMember => keeps other (by simp [isMember]))

theorem all_filter_split {Item : Type} (keep : Item → Bool) (predicate : Item → Bool) (items : List Item) :
    ((items.filter keep).all predicate && (items.filter (!keep ·)).all predicate) = items.all predicate := by
  apply Bool.eq_iff_iff.mpr
  simp only [Bool.and_eq_true, List.all_eq_true, List.mem_filter]
  refine ⟨fun ⟨kept, dropped⟩ item isMember => ?_, fun all => ⟨fun item ⟨isMember, _⟩ => all item isMember,
    fun item ⟨isMember, _⟩ => all item isMember⟩⟩
  cases keepItem : keep item
  · exact dropped item ⟨isMember, by simp [keepItem]⟩
  · exact kept item ⟨isMember, keepItem⟩

/-! ## Sorting -/

@[simp] theorem mem_sortByKey {Item : Type} [DecidableEq Item] (key : Item → List Nat) (items : List Item)
    (item : Item) : item ∈ sortByKey key items ↔ item ∈ items := by
  simp [sortByKey]

theorem all_sortByKey {Item : Type} [DecidableEq Item] (key : Item → List Nat) (items : List Item)
    (predicate : Item → Bool) : (sortByKey key items).all predicate = items.all predicate :=
  all_eq_of_members (mem_sortByKey key items) predicate

theorem any_sortByKey {Item : Type} [DecidableEq Item] (key : Item → List Nat) (items : List Item)
    (predicate : Item → Bool) : (sortByKey key items).any predicate = items.any predicate :=
  any_eq_of_members (mem_sortByKey key items) predicate

theorem sortByKey_sublist {Item : Type} [DecidableEq Item] (key : Item → List Nat) (items : List Item) :
    ∃ sorted, sorted.Perm items ∧ (sortByKey key items).Sublist sorted :=
  ⟨_, List.mergeSort_perm _ _, eraseDups_sublist _⟩

theorem sortByKey_sorted {Item : Type} [DecidableEq Item] (key : Item → List Nat) (items : List Item) :
    (sortByKey key items).Pairwise fun first second => decide (key first ≤ key second) :=
  (List.pairwise_mergeSort (le := fun first second => decide (key first ≤ key second))
    (fun _ _ _ first second => by simp only [decide_eq_true_eq] at *; exact List.le_trans first second)
    (fun first second => by simpa using List.le_total (key first) (key second)) items).sublist
    (eraseDups_sublist _)

theorem sortByKey_idem {Item : Type} [DecidableEq Item] (key : Item → List Nat) (items : List Item) :
    sortByKey key (sortByKey key items) = sortByKey key items := by
  rw [sortByKey, List.mergeSort_of_pairwise (sortByKey_sorted key items)]
  exact eraseDups_of_nodup (nodup_eraseDups _)

@[simp] theorem sortByKey_singleton {Item : Type} [DecidableEq Item] (key : Item → List Nat) (item : Item) :
    sortByKey key [item] = [item] := by
  simp [sortByKey, List.eraseDups_cons]

/-- Under an injective key, sorting changes nothing exactly on a strictly ascending list. -/
theorem sortByKey_eq_self_iff {Item : Type} [DecidableEq Item] {key : Item → List Nat}
    (injective : ∀ {first second : Item}, key first = key second → first = second) {items : List Item} :
    sortByKey key items = items ↔ strictlySorted key items = true := by
  simp only [strictlySorted, decide_eq_true_eq]
  constructor
  · intro fixed
    have sorted := sortByKey_sorted key items
    have nodup := nodup_eraseDups (items.mergeSort fun first second => decide (key first ≤ key second))
    rw [← sortByKey, fixed] at nodup
    rw [fixed] at sorted
    exact (sorted.and nodup).imp fun ⟨lower, different⟩ =>
      Std.lt_of_le_of_ne (of_decide_eq_true lower) fun same => different (injective same)
  · intro strict
    have sorted : items.Pairwise fun first second => decide (key first ≤ key second) :=
      strict.imp fun lower => decide_eq_true (List.le_of_lt lower)
    have nodup : items.Nodup := strict.imp fun {first second} lower (same : first = second) => by
      subst same
      exact List.lt_irrefl _ lower
    rw [sortByKey, List.mergeSort_of_pairwise sorted, eraseDups_of_nodup nodup]

theorem strictlySorted_sortByKey {Item : Type} [DecidableEq Item] {key : Item → List Nat}
    (injective : ∀ {first second : Item}, key first = key second → first = second) (items : List Item) :
    strictlySorted key (sortByKey key items) = true :=
  (sortByKey_eq_self_iff injective).mp (sortByKey_idem key items)

theorem nodup_sortRules (rules : List Rule) : (sortRules rules).Nodup :=
  nodup_eraseDups _

@[simp] theorem mem_sortRules (rules : List Rule) (rule : Rule) : rule ∈ sortRules rules ↔ rule ∈ rules :=
  mem_sortByKey _ _ _

/-- A strictly ascending list has no repeats. -/
theorem nodup_of_strictlySorted {Item : Type} {key : Item → List Nat} {items : List Item}
    (strict : strictlySorted key items = true) : items.Nodup := by
  simp only [strictlySorted, decide_eq_true_eq] at strict
  exact strict.imp fun {first second} lower (same : first = second) => by
    subst same
    exact List.lt_irrefl _ lower

/-- A sublist of a strictly ascending list is strictly ascending. -/
theorem strictlySorted_sublist {Item : Type} {key : Item → List Nat} {items other : List Item}
    (strict : strictlySorted key items = true) (sublist : other.Sublist items) : strictlySorted key other = true := by
  simp only [strictlySorted, decide_eq_true_eq] at *
  exact strict.sublist sublist

/-- Two lists sorted by an injective key, without repeats, and with the same members are equal. -/
theorem eq_of_sorted {Item : Type} {key : Item → List Nat}
    (injective : ∀ {first second : Item}, key first = key second → first = second) :
    ∀ {items other : List Item}, items.Pairwise (fun first second => decide (key first ≤ key second)) →
      other.Pairwise (fun first second => decide (key first ≤ key second)) → items.Nodup → other.Nodup →
      (∀ item, item ∈ items ↔ item ∈ other) → items = other
  | [], [], _, _, _, _, _ => rfl
  | [], item :: _, _, _, _, _, same => absurd ((same item).mpr (by simp)) (by simp)
  | item :: _, [], _, _, _, _, same => absurd ((same item).mp (by simp)) (by simp)
  | item :: items, other :: others, sorted, otherSorted, nodup, otherNodup, same => by
    rw [List.pairwise_cons] at sorted otherSorted
    obtain ⟨fresh, restNodup⟩ := List.nodup_cons.mp nodup
    obtain ⟨otherFresh, otherRestNodup⟩ := List.nodup_cons.mp otherNodup
    have head : item = other := by
      rcases List.mem_cons.mp ((same item).mp (by simp)) with equal | later
      · exact equal
      · rcases List.mem_cons.mp ((same other).mpr (by simp)) with equal | earlier
        · exact equal.symm
        · exact injective (List.le_antisymm (of_decide_eq_true (sorted.1 other earlier))
            (of_decide_eq_true (otherSorted.1 item later)))
    subst head
    have tails : ∀ member, member ∈ items ↔ member ∈ others := fun member =>
      ⟨fun isMember => (List.mem_cons.mp ((same member).mp (List.mem_cons_of_mem _ isMember))).resolve_left
          fun equal => fresh (equal ▸ isMember),
        fun isMember => (List.mem_cons.mp ((same member).mpr (List.mem_cons_of_mem _ isMember))).resolve_left
          fun equal => otherFresh (equal ▸ isMember)⟩
    rw [eq_of_sorted injective sorted.2 otherSorted.2 restNodup otherRestNodup tails]

theorem sortByKey_eq_of_members {Item : Type} [DecidableEq Item] {key : Item → List Nat}
    (injective : ∀ {first second : Item}, key first = key second → first = second) {items other : List Item}
    (same : ∀ item, item ∈ items ↔ item ∈ other) : sortByKey key items = sortByKey key other :=
  eq_of_sorted injective (sortByKey_sorted key items) (sortByKey_sorted key other) (nodup_eraseDups _)
    (nodup_eraseDups _) fun item => by simp [same]

/-! ## Operators -/

theorem Comparison.apply_negation {comparison negation : Comparison} (negates : comparison.negation? = some negation)
    (subject : Value) (values : List Word) :
    negation.apply subject values = (comparison.apply subject values).map (!·) := by
  rcases values with _ | ⟨_, _ | ⟨_, _ | ⟨_, _⟩⟩⟩ <;> cases subject <;> cases comparison <;>
    simp [Comparison.negation?] at negates <;> subst negates <;>
    simp [Comparison.apply, Option.map_map, Function.comp_def, bne]

theorem Operator.positive_holds (operator : Operator) (ctx : Context) (subject : Option Value) :
    operator.positive.holds ctx subject = operator.holds ctx subject := by
  rcases operator with ⟨_ | _, comparison, operand⟩ <;> unfold Operator.positive <;> try rfl
  rcases negates : comparison.negation? with _ | negation
  · rfl
  · simp only [Operator.holds, Comparison.apply_negation negates]
    split <;> try rfl
    split <;> simp_all

theorem Comparison.apply_in_singleton (subject : Value) (value : Word) :
    Comparison.in_.apply subject [value] = Comparison.eq.apply subject [value] := by
  cases subject <;> simp [Comparison.apply] <;> rfl

theorem Operator.unwrapSingleton_holds (operator : Operator) (ctx : Context) (subject : Option Value) :
    operator.unwrapSingleton.holds ctx subject = operator.holds ctx subject := by
  rcases operator with ⟨negated, comparison, (_ | ⟨value, _ | ⟨_, _⟩⟩) | property⟩ <;> cases comparison <;>
    simp only [Operator.unwrapSingleton]
  rcases subject with _ | subject
  · rfl
  · simp only [Operator.holds, Operand.values, Comparison.apply_in_singleton]

theorem Operator.normalize_holds (operator : Operator) (ctx : Context) (subject : Option Value) :
    operator.normalize.holds ctx subject = operator.holds ctx subject := by
  simp only [Operator.normalize, Operator.unwrapSingleton_holds, Operator.positive_holds]

theorem Operator.normal_normalize (operator : Operator) : operator.normalize.normal = true := by
  rcases operator with ⟨_ | _, comparison, (_ | ⟨_, _ | ⟨_, _⟩⟩) | _⟩ <;> cases comparison <;> rfl

theorem Operator.normalize_of_normal {operator : Operator} (normal : operator.normal = true) :
    operator.normalize = operator := by
  rcases operator with ⟨_ | _, comparison, (_ | ⟨_, _ | ⟨_, _⟩⟩) | _⟩ <;> cases comparison <;>
    simp_all [Operator.normal, Operator.normalize, Operator.positive, Operator.unwrapSingleton,
      Operator.isSingletonSet, Comparison.negation?]

/-! ## Context subjects -/

theorem Comparison.apply_swap {comparison swapped : Comparison} (swaps : comparison.swap? = some swapped)
    (subject other : Word) :
    swapped.apply (.word other false) [subject] = comparison.apply (.word subject false) [other] := by
  cases comparison <;> simp [Comparison.swap?] at swaps <;> subst swaps <;> simp [Comparison.apply, Bool.beq_comm]

theorem Rule.contextTestBySubject_holds (property : PropertyId) (operator : Operator) (ctx : Context) (stack : Stack) :
    (Rule.contextTestBySubject property operator).holds ctx stack = (Rule.contextTest property operator).holds ctx stack := by
  unfold Rule.contextTestBySubject
  split
  · rename_i other swapped _ swaps
    split
    · simp only [Rule.holds, Operator.holds, Operand.values, *]
      cases ctx other <;> cases ctx property <;> simp [Comparison.apply_swap swaps]
    · rfl
  · rfl

theorem Rule.contextTestBySubject_of_subjectNormal {property : PropertyId} {operator : Operator}
    (normal : Rule.subjectNormal property operator = true) :
    Rule.contextTestBySubject property operator = .contextTest property operator := by
  unfold Rule.contextTestBySubject
  unfold Rule.subjectNormal at normal
  split
  · rename_i other swapped operandIs swaps
    simp only [operandIs, swaps] at normal
    have notLower : ¬other < property := by simpa using normal
    simp [notLower]
  · rfl

theorem Rule.normal_contextTestBySubject {property : PropertyId} {operator : Operator} (normal : operator.normal = true) :
    (Rule.contextTestBySubject property operator).normal = true := by
  rcases operator with ⟨_ | _, comparison, (_ | ⟨_, _ | ⟨_, _⟩⟩) | other⟩ <;> cases comparison <;>
    simp only [Rule.contextTestBySubject, Comparison.swap?] <;> (try by_cases lower : other < property) <;>
    (try simp only [lower, ↓reduceIte]) <;>
    simp_all [Rule.normal, Operator.normal, Rule.subjectNormal, Comparison.negation?, Comparison.swap?,
      Operator.isSingletonSet] <;> exact Nat.le_of_lt lower

theorem Rule.contextTestBySubject_isLoop (property : PropertyId) (operator : Operator) :
    (Rule.contextTestBySubject property operator).isLoop = false := by
  unfold Rule.contextTestBySubject
  split <;> (try split) <;> rfl

theorem Rule.normalize_isLoop (rule : Rule) : rule.normalize.isLoop = rule.isLoop := by
  cases rule
  · rfl
  · exact Rule.contextTestBySubject_isLoop _ _
  · rfl

/-! ## Ranges -/

/-- The comparison a bound on one side of a range uses. -/
def boundComparison : Bool → Bool → Comparison
  | false, true => .gte
  | false, false => .lte
  | true, true => .lengthGte
  | true, false => .lengthLte

/-- What a subject reads: the value at its path, or its context property as a word. -/
def Subject.read (ctx : Context) (stack : Stack) : Subject → Option Value
  | .path steps => stack.at steps
  | .property propertyId => (ctx propertyId).map (.word · false)

/-- The bound rule on one side of a subject. -/
def Subject.bound (subject : Subject) (length lower : Bool) (bound : Word) : Rule :=
  subject.rule ⟨false, boundComparison length lower, .constant [bound]⟩

theorem Subject.rule_holds (subject : Subject) (operator : Operator) (ctx : Context) (stack : Stack) :
    (subject.rule operator).holds ctx stack = operator.holds ctx (subject.read ctx stack) := by
  cases subject <;> rfl

@[simp] theorem Subject.rule_isLoop (subject : Subject) (operator : Operator) : (subject.rule operator).isLoop = false := by
  cases subject <;> rfl

theorem Operator.eq_of_bound? {operator : Operator} {length lower : Bool} {bound : Word}
    (bounds : operator.bound? = some (length, lower, bound)) :
    operator = ⟨false, boundComparison length lower, .constant [bound]⟩ := by
  rcases operator with ⟨_ | _, comparison, (_ | ⟨_, _ | ⟨_, _⟩⟩) | _⟩ <;> cases comparison <;>
    simp [Operator.bound?] at bounds <;> obtain ⟨rfl, rfl, rfl⟩ := bounds <;> rfl

theorem Rule.eq_of_bound? {rule : Rule} {subject : Subject} {length lower : Bool} {bound : Word}
    (bounds : rule.bound? = some ((subject, length, lower), bound)) : rule = subject.bound length lower bound := by
  rcases rule with ⟨path, operator⟩ | ⟨property, operator⟩ | _ <;> simp only [Rule.bound?, Option.map_eq_some_iff] at bounds
  · obtain ⟨⟨_, _, _⟩, bounds, same⟩ := bounds
    simp only [Prod.mk.injEq] at same
    obtain ⟨⟨rfl, rfl, rfl⟩, rfl⟩ := same
    rw [Operator.eq_of_bound? bounds]
    rfl
  · obtain ⟨⟨_, _, _⟩, bounds, same⟩ := bounds
    simp only [Prod.mk.injEq] at same
    obtain ⟨⟨rfl, rfl, rfl⟩, rfl⟩ := same
    rw [Operator.eq_of_bound? bounds]
    rfl
  · simp at bounds

theorem Subject.range_bound? (subject : Subject) (length : Bool) (lower upper : Word) :
    (subject.range length lower upper).bound? = none := by
  cases subject <;> cases length <;> rfl

@[simp] theorem Subject.range_isLoop (subject : Subject) (length : Bool) (lower upper : Word) :
    (subject.range length lower upper).isLoop = false :=
  Subject.rule_isLoop _ _

theorem Operator.range_holds (length : Bool) (lower upper : Word) (ctx : Context) (subject : Option Value) :
    (Operator.mk false (if length then .lengthBetween else .between) (.constant [lower, upper])).holds ctx subject =
      ((Operator.mk false (boundComparison length true) (.constant [lower])).holds ctx subject &&
        (Operator.mk false (boundComparison length false) (.constant [upper])).holds ctx subject) := by
  cases length <;> rcases subject with _ | (_ | _ | _) <;>
    simp [Operator.holds, Operand.values, Comparison.apply, boundComparison, Value.length?]

theorem Subject.range_holds (subject : Subject) (length : Bool) (lower upper : Word) (ctx : Context) (stack : Stack) :
    (subject.range length lower upper).holds ctx stack =
      ((subject.bound length true lower).holds ctx stack && (subject.bound length false upper).holds ctx stack) := by
  simp only [Subject.range, Subject.bound, Subject.rule_holds, Operator.range_holds]

/-! ## Fusing lone range pairs -/

theorem mem_boundsOn {rules : List Rule} {side : BoundSide} {rule : Rule} :
    rule ∈ boundsOn rules side ↔ rule ∈ rules ∧ rule.bound?.map (·.1) = some side := by
  simp [boundsOn]

@[simp] theorem BoundSide.opposite_opposite (side : BoundSide) : side.opposite.opposite = side := by
  obtain ⟨_, _, _⟩ := side
  simp [BoundSide.opposite]

theorem Rule.lonePartner?_eq_some {rules : List Rule} {rule partner : Rule} :
    rule.lonePartner? rules = some partner ↔ ∃ (side : BoundSide) (bound : Word) (single : Rule), rule.bound? = some (side, bound) ∧
      boundsOn rules side = [single] ∧ boundsOn rules side.opposite = [partner] := by
  unfold Rule.lonePartner?
  rcases rule.bound? with _ | ⟨side, bound⟩
  · simp
  · simp only [Option.some.injEq, Prod.mk.injEq, exists_and_left]
    split <;> simp_all

theorem Rule.lonePartner?_eq_none_of_length {rules : List Rule} {rule : Rule} {side : BoundSide} {bound : Word}
    (bounds : rule.bound? = some (side, bound))
    (notLone : ¬((boundsOn rules side).length = 1 ∧ (boundsOn rules side.opposite).length = 1)) :
    rule.lonePartner? rules = none := by
  unfold Rule.lonePartner?
  rw [bounds]
  dsimp only
  split
  · rename_i single partner sideBounds oppositeBounds
    exact absurd ⟨by simp [sideBounds], by simp [oppositeBounds]⟩ notLone
  · rfl

/-- The pair a lone bound belongs to: each side contains one rule, the rule itself on its own side. -/
theorem Rule.lone_spec {rules : List Rule} {rule partner : Rule} (isMember : rule ∈ rules)
    (lone : rule.lonePartner? rules = some partner) :
    ∃ (subject : Subject) (length lower : Bool) (bound other : Word), rule.bound? = some ((subject, length, lower), bound) ∧
      partner.bound? = some ((subject, length, !lower), other) ∧ partner ∈ rules ∧
      boundsOn rules (subject, length, lower) = [rule] ∧ boundsOn rules (subject, length, !lower) = [partner] := by
  obtain ⟨⟨subject, length, lower⟩, bound, single, bounds, sideBounds, oppositeBounds⟩ := Rule.lonePartner?_eq_some.mp lone
  have ruleOnSide : rule ∈ boundsOn rules (subject, length, lower) := mem_boundsOn.mpr ⟨isMember, by simp [bounds]⟩
  rw [sideBounds, List.mem_singleton] at ruleOnSide
  subst ruleOnSide
  have partnerOnOpposite : partner ∈ boundsOn rules (subject, length, !lower) := by
    simp [BoundSide.opposite] at oppositeBounds
    simp [oppositeBounds]
  obtain ⟨partnerIsMember, partnerSide⟩ := mem_boundsOn.mp partnerOnOpposite
  obtain ⟨⟨partnerPair, other⟩, partnerBounds, same⟩ := Option.map_eq_some_iff.mp partnerSide
  dsimp only at same
  subst same
  exact ⟨subject, length, lower, bound, other, bounds, partnerBounds, partnerIsMember, sideBounds,
    by simpa [BoundSide.opposite] using oppositeBounds⟩

/-- The partner of a lone bound is a lone bound whose partner is the first. -/
theorem Rule.lonePartner?_symm {rules : List Rule} {rule partner : Rule} (isMember : rule ∈ rules)
    (lone : rule.lonePartner? rules = some partner) : partner.lonePartner? rules = some rule := by
  obtain ⟨subject, length, lower, bound, other, _, partnerBounds, _, sideBounds, oppositeBounds⟩ :=
    Rule.lone_spec isMember lone
  exact Rule.lonePartner?_eq_some.mpr ⟨(subject, length, !lower), other, partner, partnerBounds, oppositeBounds,
    by simpa [BoundSide.opposite] using sideBounds⟩

theorem Rule.fused_of_lonePartner?_none {rules : List Rule} {rule : Rule} (notLone : rule.lonePartner? rules = none) :
    rule.fused rules = some rule := by
  unfold Rule.fused
  rw [notLone]
  split <;> simp_all

/-- What fusing makes of a rule: the rule itself, or the range of the lone pair it bounds from below. -/
theorem Rule.fused_spec {rules : List Rule} {rule result : Rule} (isMember : rule ∈ rules)
    (fused : rule.fused rules = some result) :
    result = rule ∨ ∃ (subject : Subject) (length : Bool) (lower upper : Word) (partner : Rule),
      rule = subject.bound length true lower ∧
      partner ∈ rules ∧ partner = subject.bound length false upper ∧ result = subject.range length lower upper := by
  rcases lone : rule.lonePartner? rules with _ | partner
  · rw [Rule.fused_of_lonePartner?_none lone] at fused
    exact .inl (Option.some.inj fused).symm
  · obtain ⟨subject, length, lower, bound, other, bounds, partnerBounds, partnerIsMember, _, _⟩ :=
      Rule.lone_spec isMember lone
    unfold Rule.fused at fused
    rw [bounds, lone] at fused
    cases lower
    · simp at fused
    · simp only [partnerBounds, Option.map_some, Option.some.injEq] at fused
      exact .inr ⟨subject, length, bound, other, partner, Rule.eq_of_bound? bounds, partnerIsMember,
        Rule.eq_of_bound? partnerBounds, fused.symm⟩

theorem mem_fuseRanges {rules : List Rule} {result : Rule} (isMember : result ∈ fuseRanges rules) :
    result ∈ rules ∨ ∃ (subject : Subject) (length : Bool) (lower upper : Word), result = subject.range length lower upper := by
  obtain ⟨rule, ruleIsMember, fused⟩ := List.mem_filterMap.mp isMember
  rcases Rule.fused_spec ruleIsMember fused with rfl | ⟨subject, length, lower, upper, _, _, _, _, rfl⟩
  · exact .inl ruleIsMember
  · exact .inr ⟨subject, length, lower, upper, rfl⟩

/-- Fusing keeps every predicate under which a range is the conjunction of its two bounds. -/
theorem fuseRanges_all (predicate : Rule → Bool)
    (range : ∀ (subject : Subject) (length : Bool) (lower upper : Word), predicate (subject.range length lower upper) =
      (predicate (subject.bound length true lower) && predicate (subject.bound length false upper)))
    (rules : List Rule) : (fuseRanges rules).all predicate = rules.all predicate := by
  apply Bool.eq_iff_iff.mpr
  simp only [List.all_eq_true]
  constructor
  · intro fusedHold rule isMember
    rcases lone : rule.lonePartner? rules with _ | partner
    · exact fusedHold rule (List.mem_filterMap.mpr ⟨rule, isMember, Rule.fused_of_lonePartner?_none lone⟩)
    · obtain ⟨subject, length, lower, bound, other, bounds, partnerBounds, partnerIsMember, _, _⟩ :=
        Rule.lone_spec isMember lone
      cases lower
      · -- The rule is the upper bound; its partner, the lower bound, becomes the range.
        have partnerLone := Rule.lonePartner?_symm isMember lone
        have partnerFused : partner.fused rules = some (subject.range length other bound) := by
          unfold Rule.fused
          simp [partnerBounds, partnerLone, bounds]
        have rangeHolds := fusedHold _ (List.mem_filterMap.mpr ⟨partner, partnerIsMember, partnerFused⟩)
        rw [range, Bool.and_eq_true] at rangeHolds
        rw [Rule.eq_of_bound? bounds]
        exact rangeHolds.2
      · have ruleFused : rule.fused rules = some (subject.range length bound other) := by
          unfold Rule.fused
          simp [bounds, lone, partnerBounds]
        have rangeHolds := fusedHold _ (List.mem_filterMap.mpr ⟨rule, isMember, ruleFused⟩)
        rw [range, Bool.and_eq_true] at rangeHolds
        rw [Rule.eq_of_bound? bounds]
        exact rangeHolds.1
  · intro ruleHolds result isMember
    obtain ⟨rule, ruleIsMember, fused⟩ := List.mem_filterMap.mp isMember
    rcases Rule.fused_spec ruleIsMember fused with rfl | ⟨subject, length, lower, upper, partner, rfl, partnerIsMember,
      rfl, rfl⟩
    · exact ruleHolds result ruleIsMember
    · rw [range, ruleHolds _ ruleIsMember, ruleHolds _ partnerIsMember]
      rfl

theorem fuseRanges_of_noLonePair {rules : List Rule} (noLone : Group.noLonePair rules = true) :
    fuseRanges rules = rules := by
  simp only [Group.noLonePair, List.all_eq_true, Option.isNone_iff_eq_none] at noLone
  exact filterMap_of_forall_some fun rule isMember => Rule.fused_of_lonePartner?_none (noLone rule isMember)

/-- On a list without repeats, a side keeps its bounds through fusing unless it belongs to a lone pair, and fusing
removes that lone pair. -/
theorem mem_boundsOn_fuseRanges {rules : List Rule} {side : BoundSide} {rule : Rule} :
    rule ∈ boundsOn (fuseRanges rules) side ↔ rule ∈ boundsOn rules side ∧ rule.lonePartner? rules = none := by
  simp only [mem_boundsOn]
  constructor
  · rintro ⟨isMember, ruleSide⟩
    obtain ⟨original, originalIsMember, fused⟩ := List.mem_filterMap.mp isMember
    rcases Rule.fused_spec originalIsMember fused with same | ⟨subject, length, lower, upper, _, _, _, _, rfl⟩
    · subst same
      refine ⟨⟨originalIsMember, ruleSide⟩, ?_⟩
      rcases lone : rule.lonePartner? rules with _ | partner
      · rfl
      · obtain ⟨_, _, lower, _, _, bounds, _, _, _, _⟩ := Rule.lone_spec originalIsMember lone
        unfold Rule.fused at fused
        rw [bounds, lone] at fused
        cases lower
        · simp at fused
        · obtain ⟨_, _, same⟩ := Option.map_eq_some_iff.mp fused
          subst same
          simp [Subject.range_bound?] at bounds
    · simp [Subject.range_bound?] at ruleSide
  · rintro ⟨⟨isMember, ruleSide⟩, notLone⟩
    exact ⟨List.mem_filterMap.mpr ⟨rule, isMember, Rule.fused_of_lonePartner?_none notLone⟩, ruleSide⟩

/-- Every rule of a side shares the side's lone status: `lonePartner?` reads only the rule's side. -/
theorem Rule.lonePartner?_isNone_eq {rules : List Rule} {rule other : Rule} {side : BoundSide} {bound otherBound : Word}
    (bounds : rule.bound? = some (side, bound)) (otherBounds : other.bound? = some (side, otherBound)) :
    (rule.lonePartner? rules).isNone = (other.lonePartner? rules).isNone := by
  unfold Rule.lonePartner?
  rw [bounds, otherBounds]

theorem boundsOn_nodup {rules : List Rule} (nodup : rules.Nodup) (side : BoundSide) : (boundsOn rules side).Nodup :=
  List.filter_sublist.nodup nodup

/-- After fusing a list without repeats and sorting, no lone pair remains. -/
theorem noLonePair_sortRules_fuseRanges {rules : List Rule} (nodup : rules.Nodup) :
    Group.noLonePair (sortRules (fuseRanges rules)) = true := by
  simp only [Group.noLonePair, List.all_eq_true, Option.isNone_iff_eq_none, mem_sortRules]
  intro rule isMember
  rcases bounds : rule.bound? with _ | ⟨side, bound⟩
  · unfold Rule.lonePartner?
    rw [bounds]
  · -- The side kept its bounds, so neither it nor its opposite is a lone pair in `rules`.
    have onSide : rule ∈ boundsOn (fuseRanges rules) side := mem_boundsOn.mpr ⟨isMember, by simp [bounds]⟩
    obtain ⟨inRules, notLone⟩ := mem_boundsOn_fuseRanges.mp onSide
    have sameMembers : ∀ target, ∀ member,
        member ∈ boundsOn (sortRules (fuseRanges rules)) target ↔ member ∈ boundsOn (fuseRanges rules) target := by
      intro target member
      simp [mem_boundsOn]
    have keptLength : ∀ target, (∀ member ∈ boundsOn rules target, member.lonePartner? rules = none) →
        (boundsOn (sortRules (fuseRanges rules)) target).length = (boundsOn rules target).length := by
      intro target allKept
      refine List.Perm.length_eq ((List.perm_ext_iff_of_nodup (boundsOn_nodup (nodup_sortRules _) _)
        (boundsOn_nodup nodup _)).mpr fun member => ?_)
      rw [sameMembers, mem_boundsOn_fuseRanges]
      exact ⟨fun ⟨isMember, _⟩ => isMember, fun isMember => ⟨isMember, allKept member isMember⟩⟩
    have sideKept : ∀ member ∈ boundsOn rules side, member.lonePartner? rules = none := by
      intro member memberOnSide
      obtain ⟨_, memberSide⟩ := mem_boundsOn.mp memberOnSide
      obtain ⟨⟨_, memberBound⟩, memberBounds, same⟩ := Option.map_eq_some_iff.mp memberSide
      dsimp only at same
      subst same
      have := Rule.lonePartner?_isNone_eq (rules := rules) bounds memberBounds
      simp_all
    have rulesNotLone : ¬((boundsOn rules side).length = 1 ∧ (boundsOn rules side.opposite).length = 1) := by
      rintro ⟨sideOne, oppositeOne⟩
      obtain ⟨single, singleIs⟩ := List.length_eq_one_iff.mp sideOne
      obtain ⟨partner, partnerIs⟩ := List.length_eq_one_iff.mp oppositeOne
      have : rule.lonePartner? rules = some partner := by
        unfold Rule.lonePartner?
        rw [bounds]
        simp [singleIs, partnerIs]
      simp_all
    have oppositeKept : ∀ member ∈ boundsOn rules side.opposite, member.lonePartner? rules = none := by
      intro member memberOnOpposite
      obtain ⟨_, memberSide⟩ := mem_boundsOn.mp memberOnOpposite
      obtain ⟨⟨_, memberBound⟩, memberBounds, same⟩ := Option.map_eq_some_iff.mp memberSide
      dsimp only at same
      subst same
      refine Rule.lonePartner?_eq_none_of_length memberBounds fun ⟨oppositeOne, sideOne⟩ => rulesNotLone ⟨?_, oppositeOne⟩
      simpa using sideOne
    refine Rule.lonePartner?_eq_none_of_length bounds fun ⟨sideOne, oppositeOne⟩ => rulesNotLone ⟨?_, ?_⟩
    · rwa [keptLength side sideKept] at sideOne
    · rwa [keptLength side.opposite oppositeKept] at oppositeOne

/-! ## Finishing a group -/

theorem finishRules_all (predicate : Rule → Bool)
    (range : ∀ (subject : Subject) (length : Bool) (lower upper : Word), predicate (subject.range length lower upper) =
      (predicate (subject.bound length true lower) && predicate (subject.bound length false upper)))
    (rules : List Rule) : (finishRules rules).all predicate = rules.all predicate := by
  simp only [finishRules, sortRules, all_sortByKey]
  rw [fuseRanges_all predicate range, all_sortByKey]

theorem mem_finishRules {rules : List Rule} {result : Rule} (isMember : result ∈ finishRules rules) :
    result ∈ rules ∨ ∃ (subject : Subject) (length : Bool) (lower upper : Word), result = subject.range length lower upper := by
  rw [finishRules, mem_sortRules] at isMember
  rcases mem_fuseRanges isMember with inSorted | range
  · exact .inl ((mem_sortRules _ _).mp inSorted)
  · exact .inr range

theorem strictlySorted_finishRules (rules : List Rule) : strictlySorted Rule.key (finishRules rules) = true :=
  strictlySorted_sortByKey Rule.key_injective _

theorem noLonePair_finishRules (rules : List Rule) : Group.noLonePair (finishRules rules) = true :=
  noLonePair_sortRules_fuseRanges (nodup_sortRules rules)

theorem finishRules_of_arranged {rules : List Rule} (sorted : strictlySorted Rule.key rules = true)
    (noLone : Group.noLonePair rules = true) : finishRules rules = rules := by
  have sortedFixed : sortRules rules = rules := (sortByKey_eq_self_iff Rule.key_injective).mpr sorted
  rw [finishRules, sortedFixed, fuseRanges_of_noLonePair noLone, sortedFixed]

theorem finishRules_idem (rules : List Rule) : finishRules (finishRules rules) = finishRules rules :=
  finishRules_of_arranged (strictlySorted_finishRules rules) (noLonePair_finishRules rules)

theorem finishRules_eq_of_members {rules other : List Rule} (same : ∀ rule, rule ∈ rules ↔ rule ∈ other) :
    finishRules rules = finishRules other := by
  rw [finishRules, finishRules, show sortRules rules = sortRules other from
    sortByKey_eq_of_members Rule.key_injective same]

/-! ## Hoisting context tests -/

theorem Rule.holds_of_isContextTest {rule : Rule} (isContext : rule.isContextTest = true) (ctx : Context)
    (stack other : Stack) : rule.holds ctx stack = rule.holds ctx other := by
  cases rule <;> simp_all [Rule.isContextTest, Rule.holds]

theorem Rule.isLoop_of_isContextTest {rule : Rule} (isContext : rule.isContextTest = true) : rule.isLoop = false := by
  cases rule <;> simp_all [Rule.isContextTest, Rule.isLoop]

theorem Rule.withinLimits_of_isLoop {rule : Rule} (notLoop : rule.isLoop = false) (stack : Stack) :
    rule.withinLimits stack = true := by
  cases rule <;> simp_all [Rule.isLoop, Rule.withinLimits]

theorem mem_hoisted {rule member : Rule} (isMember : member ∈ rule.hoisted) :
    member.isContextTest = true ∧ ∃ arrayPath body, rule = .loop .any arrayPath body ∧ member ∈ body := by
  rcases rule with _ | _ | ⟨_ | _, arrayPath, body⟩ <;> simp only [Rule.hoisted, List.not_mem_nil] at isMember
  split at isMember
  · obtain ⟨inBody, isContext⟩ := List.mem_filter.mp isMember
    exact ⟨isContext, arrayPath, body, rfl, inBody⟩
  · simp at isMember

theorem Rule.holds_hoist (rule : Rule) (ctx : Context) (stack : Stack) :
    rule.holds ctx stack = (rule.withoutHoisted.holds ctx stack && rule.hoisted.all (·.holds ctx stack)) := by
  rcases rule with _ | _ | ⟨_ | _, arrayPath, body⟩ <;> simp only [Rule.withoutHoisted, Rule.hoisted] <;> try simp
  split
  · have contexts : ∀ other : Stack, (body.filter Rule.isContextTest).all (·.holds ctx other) =
        (body.filter Rule.isContextTest).all (·.holds ctx stack) := fun other =>
      all_congr_mem fun member isMember =>
        Rule.holds_of_isContextTest (List.mem_filter.mp isMember).2 ctx other stack
    have split : ∀ other : Stack, Group.holds ctx other body =
        ((body.filter Rule.isContextTest).all (·.holds ctx stack) &&
          Group.holds ctx other (body.filter (!·.isContextTest))) := by
      intro other
      rw [Group.holds_eq, Group.holds_eq, ← all_filter_split Rule.isContextTest, contexts]
    simp only [Rule.holds]
    split
    · simp only [split, any_and_const, Bool.and_comm]
    · simp
  · simp

theorem Rule.withinLimits_hoist (rule : Rule) (stack : Stack) :
    rule.withinLimits stack = (rule.withoutHoisted.withinLimits stack && rule.hoisted.all (·.withinLimits stack)) := by
  rcases rule with _ | _ | ⟨_ | _, arrayPath, body⟩ <;> simp only [Rule.withoutHoisted, Rule.hoisted] <;> try simp
  split
  · have contexts : ∀ other : Stack, (body.filter Rule.isContextTest).all (·.withinLimits other) = true := fun other =>
      List.all_eq_true.mpr fun member isMember =>
        Rule.withinLimits_of_isLoop (Rule.isLoop_of_isContextTest (List.mem_filter.mp isMember).2) other
    have hoisted : (body.filter Rule.isContextTest).all (·.withinLimits stack) = true := contexts stack
    have split : ∀ other : Stack, Group.withinLimits other body = Group.withinLimits other (body.filter (!·.isContextTest)) := by
      intro other
      rw [Group.withinLimits_eq, Group.withinLimits_eq, ← all_filter_split Rule.isContextTest, contexts, Bool.true_and]
    simp only [Rule.withinLimits, hoisted, Bool.and_true, split]
  · simp

theorem hoistContext_all (predicate : Rule → Bool)
    (hoist : ∀ rule, predicate rule = (predicate rule.withoutHoisted && rule.hoisted.all predicate)) (rules : List Rule) :
    (hoistContext rules).all predicate = rules.all predicate := by
  simp only [hoistContext, List.all_append, List.all_map, List.all_flatMap]
  rw [← all_and_distrib]
  exact all_congr_mem fun rule _ => (hoist rule).symm

theorem mem_hoistContext {rules : List Rule} {member : Rule} :
    member ∈ hoistContext rules ↔ (∃ rule ∈ rules, member = rule.withoutHoisted) ∨ ∃ rule ∈ rules, member ∈ rule.hoisted := by
  simp only [hoistContext, List.mem_append, List.mem_map, List.mem_flatMap]
  constructor
  · rintro (⟨rule, isMember, rfl⟩ | ⟨rule, isMember, inHoisted⟩)
    · exact .inl ⟨rule, isMember, rfl⟩
    · exact .inr ⟨rule, isMember, inHoisted⟩
  · rintro (⟨rule, isMember, rfl⟩ | ⟨rule, isMember, inHoisted⟩)
    · exact .inl ⟨rule, isMember, rfl⟩
    · exact .inr ⟨rule, isMember, inHoisted⟩

theorem Rule.hoisted_withoutHoisted (rule : Rule) : rule.withoutHoisted.hoisted = [] := by
  rcases rule with _ | _ | ⟨_ | _, arrayPath, body⟩ <;> simp only [Rule.withoutHoisted] <;> try rfl
  split
  · simp [Rule.hoisted, List.filter_filter]
  · rename_i noTest
    simp [Rule.hoisted, noTest]

theorem Rule.withoutHoisted_of_hoisted {rule : Rule} (nothing : rule.hoisted = []) : rule.withoutHoisted = rule := by
  rcases rule with _ | _ | ⟨_ | _, arrayPath, body⟩ <;> simp only [Rule.withoutHoisted] <;> try rfl
  simp only [Rule.hoisted] at nothing
  split
  · rename_i reads
    simp only [reads, ↓reduceIte, List.filter_eq_nil_iff] at nothing
    simp only [Rule.loop.injEq, true_and]
    exact List.filter_eq_self.mpr fun member isMember => by simpa using nothing member isMember
  · rfl

theorem hoistContext_of_nothingHoisted {rules : List Rule} (nothing : Group.nothingHoisted rules = true) :
    hoistContext rules = rules := by
  simp only [Group.nothingHoisted, List.all_eq_true, List.isEmpty_iff] at nothing
  simp only [hoistContext]
  rw [List.map_congr_left (fun rule isMember => Rule.withoutHoisted_of_hoisted (nothing rule isMember)), List.map_id',
    List.flatMap_eq_nil_iff.mpr (fun rule isMember => nothing rule isMember), List.append_nil]

theorem Rule.withoutHoisted_joinable? (rule : Rule) : rule.withoutHoisted.joinable? = rule.joinable? := by
  rcases rule with _ | _ | ⟨_ | _, arrayPath, body⟩ <;> simp only [Rule.withoutHoisted] <;> try rfl
  split <;> rfl

theorem Rule.withoutHoisted_isLoop (rule : Rule) : rule.withoutHoisted.isLoop = rule.isLoop := by
  rcases rule with _ | _ | ⟨_ | _, arrayPath, body⟩ <;> simp only [Rule.withoutHoisted] <;> try rfl
  split <;> rfl

theorem Rule.joinable?_of_isContextTest {rule : Rule} (isContext : rule.isContextTest = true) : rule.joinable? = none := by
  cases rule <;> simp_all [Rule.isContextTest, Rule.joinable?]

/-- Removing the context tests leaves every side a path bounds as it was. -/
theorem boundsOn_filter_contextTests (rules : List Rule) (steps : Path) (length lower : Bool) :
    boundsOn (rules.filter (!·.isContextTest)) (.path steps, length, lower) = boundsOn rules (.path steps, length, lower) := by
  simp only [boundsOn, List.filter_filter]
  refine List.filter_congr fun rule _ => ?_
  rcases bounds : rule.bound? with _ | ⟨⟨subject, ruleLength, ruleLower⟩, bound⟩
  · simp
  · rw [Rule.eq_of_bound? bounds]
    cases subject <;> simp [Subject.bound, Subject.rule, Rule.isContextTest] <;>
      cases ruleLength <;> cases ruleLower <;> simp [boundComparison, Operator.bound?]

theorem Group.noLonePair_filter_contextTests {rules : List Rule} (noLone : Group.noLonePair rules = true) :
    Group.noLonePair (rules.filter (!·.isContextTest)) = true := by
  simp only [Group.noLonePair, List.all_eq_true, Option.isNone_iff_eq_none] at *
  intro rule isMember
  obtain ⟨inRules, notContext⟩ := List.mem_filter.mp isMember
  rcases bounds : rule.bound? with _ | ⟨⟨subject, length, lower⟩, bound⟩
  · unfold Rule.lonePartner?
    rw [bounds]
  · cases subject with
    | property propertyId =>
      rw [Rule.eq_of_bound? bounds] at notContext
      simp [Subject.bound, Subject.rule, Rule.isContextTest] at notContext
    | path steps =>
      have rulesNone := noLone rule inRules
      unfold Rule.lonePartner? at rulesNone ⊢
      rw [bounds] at rulesNone ⊢
      simpa only [BoundSide.opposite, boundsOn_filter_contextTests] using rulesNone

/-! ## Joining loops -/

theorem Rule.eq_of_joinable? {rule : Rule} {arrayPath : Path} {group : Group}
    (joinable : rule.joinable? = some (arrayPath, group)) : rule = .loop .all arrayPath group := by
  rcases rule with _ | _ | ⟨_ | _, _, _⟩ <;> simp [Rule.joinable?] at joinable
  obtain ⟨_, rfl, rfl⟩ := joinable
  rfl

theorem Rule.loopFree_of_joinable? {rule : Rule} {arrayPath : Path} {group : Group}
    (joinable : rule.joinable? = some (arrayPath, group)) : ∀ member ∈ group, member.isLoop = false := by
  rcases rule with _ | _ | ⟨_ | _, _, _⟩ <;> simp [Rule.joinable?] at joinable
  obtain ⟨loopFree, rfl, rfl⟩ := joinable
  simpa using loopFree

theorem Rule.joinable?_of_joinsOn {rule : Rule} {arrayPath : Path} (joins : rule.joinsOn arrayPath) :
    ∃ group, rule.joinable? = some (arrayPath, group) := by
  unfold Rule.joinsOn at joins
  rcases joinable : rule.joinable? with _ | ⟨path, group⟩ <;> simp_all

theorem Rule.joinsOn_iff {rule : Rule} {arrayPath : Path} :
    rule.joinsOn arrayPath ↔ ∃ group, rule.joinable? = some (arrayPath, group) := by
  refine ⟨Rule.joinable?_of_joinsOn, fun ⟨_, joinable⟩ => ?_⟩
  simp [Rule.joinsOn, joinable]

theorem Rule.joinsOn_of_joinable?_none {rule : Rule} (none : rule.joinable? = none) (arrayPath : Path) :
    rule.joinsOn arrayPath = false := by
  simp [Rule.joinsOn, none]

theorem Rule.joinable?_of_isLoop {rule : Rule} (notLoop : rule.isLoop = false) : rule.joinable? = none := by
  cases rule <;> simp_all [Rule.isLoop, Rule.joinable?]

/-- A rule predicate over which a joined loop splits into the loops it joins, and which finishing a body keeps. -/
structure JoinSplits (predicate : Rule → Bool) : Prop where
  split : ∀ arrayPath first second,
    predicate (.loop .all arrayPath (first ++ second)) =
      (predicate (.loop .all arrayPath first) && predicate (.loop .all arrayPath second))
  finish : ∀ arrayPath rules, predicate (.loop .all arrayPath (finishRules rules)) = predicate (.loop .all arrayPath rules)

theorem JoinSplits.joined {predicate : Rule → Bool} (splits : JoinSplits predicate) (arrayPath : Path) :
    ∀ (joined : List Rule) (group : Group), (∀ rule ∈ joined, rule.joinsOn arrayPath) →
      predicate (.loop .all arrayPath (group ++ joined.flatMap fun rule => (rule.joinable?.map (·.2)).getD [])) =
        (predicate (.loop .all arrayPath group) && joined.all predicate)
  | [], group, _ => by simp
  | rule :: joined, group, joins => by
    obtain ⟨body, joinable⟩ := Rule.joinable?_of_joinsOn (joins rule (by simp))
    have tail := splits.joined arrayPath joined (group ++ body) fun other isMember => joins other (by simp [isMember])
    rw [List.flatMap_cons, joinable, Option.map_some, Option.getD_some, ← List.append_assoc, tail,
      splits.split, Rule.eq_of_joinable? joinable]
    simp [Bool.and_assoc]

theorem JoinSplits.all_joinLoops {predicate : Rule → Bool} (splits : JoinSplits predicate) (rules : List Rule) :
    (joinLoops rules).all predicate = rules.all predicate := by
  induction rules using joinLoops.induct with
  | case1 => simp [joinLoops]
  | case2 rule rules arrayPath group joinable restAll =>
    simp only [List.unattach_filter, List.unattach_attach] at restAll
    rw [joinLoops, joinable]
    simp only [List.all_cons, restAll]
    rw [splits.finish, splits.joined arrayPath _ _ (by simp), ← Rule.eq_of_joinable? joinable, Bool.and_assoc,
      all_filter_split]
  | case3 rule rules none restAll => simp [joinLoops, none, restAll]

theorem joinLoops_of_loopFree {rules : List Rule} (loopFree : ∀ rule ∈ rules, rule.isLoop = false) :
    joinLoops rules = rules := by
  induction rules with
  | nil => simp [joinLoops]
  | cons rule rules restFixed =>
    rw [joinLoops, Rule.joinable?_of_isLoop (loopFree rule (by simp)),
      restFixed fun other isMember => loopFree other (by simp [isMember])]

theorem mem_joinedBodies {arrayPath : Path} {joined : List Rule} {rule : Rule}
    (joins : ∀ other ∈ joined, other.joinsOn arrayPath)
    (isMember : rule ∈ joined.flatMap fun other => (other.joinable?.map (·.2)).getD []) :
    ∃ other ∈ joined, ∃ body, other.joinable? = some (arrayPath, body) ∧ rule ∈ body := by
  obtain ⟨other, otherIsMember, inOtherBody⟩ := List.mem_flatMap.mp isMember
  obtain ⟨body, joinable⟩ := Rule.joinable?_of_joinsOn (joins other otherIsMember)
  exact ⟨other, otherIsMember, body, joinable, by simpa [joinable] using inOtherBody⟩

/-- The body of a loop `joinLoops` emits, before finishing: the first loop's body and the bodies joined into it. -/
theorem mem_joinedBody {rule : Rule} {rules : List Rule} {arrayPath : Path} {group : Group}
    (joinable : rule.joinable? = some (arrayPath, group)) {member : Rule}
    (isMember : member ∈ group ++ (rules.filter (·.joinsOn arrayPath)).flatMap
      fun other => (other.joinable?.map (·.2)).getD []) :
    ∃ other ∈ rule :: rules, ∃ body, other.joinable? = some (arrayPath, body) ∧ member ∈ body := by
  rcases List.mem_append.mp isMember with inGroup | inJoined
  · exact ⟨rule, by simp, group, joinable, inGroup⟩
  · obtain ⟨other, otherIsMember, body, otherJoinable, inBody⟩ :=
      mem_joinedBodies (fun other isMember => (List.mem_filter.mp isMember).2) inJoined
    exact ⟨other, by simp [(List.mem_filter.mp otherIsMember).1], body, otherJoinable, inBody⟩

/-- A finished body of loop-free rules is loop-free. -/
theorem loopFree_finishRules {rules : List Rule} (loopFree : ∀ rule ∈ rules, rule.isLoop = false) :
    ∀ rule ∈ finishRules rules, rule.isLoop = false := by
  intro rule isMember
  rcases mem_finishRules isMember with inRules | ⟨subject, length, lower, upper, rfl⟩
  · exact loopFree rule inRules
  · exact Subject.range_isLoop _ _ _ _

theorem Rule.joinable?_loop {arrayPath : Path} {body : Group}
    (loopFree : ∀ member ∈ body, member.isLoop = false) :
    (Rule.loop .all arrayPath body).joinable? = some (arrayPath, body) := by
  simpa [Rule.joinable?] using loopFree

theorem loopFree_joined {rule : Rule} {rules : List Rule} {arrayPath : Path} {group : Group}
    (joinable : rule.joinable? = some (arrayPath, group)) :
    ∀ member ∈ finishRules (group ++ (rules.filter (·.joinsOn arrayPath)).flatMap
      fun other => (other.joinable?.map (·.2)).getD []), member.isLoop = false :=
  loopFree_finishRules fun member isMember => by
    obtain ⟨other, _, otherBody, otherJoinable, inBody⟩ := mem_joinedBody joinable isMember
    exact Rule.loopFree_of_joinable? otherJoinable member inBody

theorem joinable?_joined {rule : Rule} {rules : List Rule} {arrayPath : Path} {group : Group}
    (joinable : rule.joinable? = some (arrayPath, group)) :
    (Rule.loop .all arrayPath (finishRules (group ++ (rules.filter (·.joinsOn arrayPath)).flatMap
      fun other => (other.joinable?.map (·.2)).getD []))).joinable? =
      some (arrayPath, finishRules (group ++ (rules.filter (·.joinsOn arrayPath)).flatMap
        fun other => (other.joinable?.map (·.2)).getD [])) :=
  Rule.joinable?_loop (loopFree_joined joinable)

/-- Every loop `joinLoops` emits joins on an array some input loop joins on. -/
theorem joinsOn_of_mem_joinLoops {rules : List Rule} {arrayPath : Path} :
    ∀ rule ∈ joinLoops rules, rule.joinsOn arrayPath → ∃ other ∈ rules, other.joinsOn arrayPath := by
  induction rules using joinLoops.induct with
  | case1 => simp [joinLoops]
  | case2 rule rules loopPath group joinable fromRest =>
    simp only [List.unattach_filter, List.unattach_attach] at fromRest
    rw [joinLoops, joinable]
    dsimp only
    intro emitted isMember joins
    rcases List.mem_cons.mp isMember with rfl | inRest
    · rw [Rule.joinsOn_iff, joinable?_joined joinable] at joins
      obtain ⟨_, same⟩ := joins
      cases same
      exact ⟨rule, by simp, Rule.joinsOn_iff.mpr ⟨group, joinable⟩⟩
    · obtain ⟨other, otherIsMember, otherJoins⟩ := fromRest emitted inRest joins
      exact ⟨other, by simp [(List.mem_filter.mp otherIsMember).1], otherJoins⟩
  | case3 rule rules notJoinable fromRest =>
    rw [joinLoops, notJoinable]
    dsimp only
    intro emitted isMember joins
    rcases List.mem_cons.mp isMember with rfl | inRest
    · exact ⟨emitted, by simp, joins⟩
    · obtain ⟨other, otherIsMember, otherJoins⟩ := fromRest emitted inRest joins
      exact ⟨other, by simp [otherIsMember], otherJoins⟩

/-- Joining has nothing left to do: joinable loops have finished bodies and pairwise distinct arrays. -/
def Joined (rules : List Rule) : Prop :=
  (∀ rule ∈ rules, ∀ arrayPath group, rule.joinable? = some (arrayPath, group) → finishRules group = group) ∧
    rules.Pairwise fun first second => ∀ arrayPath, ¬(first.joinsOn arrayPath ∧ second.joinsOn arrayPath)

theorem Joined.perm {rules other : List Rule} (joined : Joined rules) (permutation : rules.Perm other) : Joined other :=
  ⟨fun rule isMember => joined.1 rule (permutation.mem_iff.mpr isMember),
    (permutation.pairwise_iff fun distinct arrayPath both => distinct arrayPath ⟨both.2, both.1⟩).mp joined.2⟩

theorem Joined.sublist {rules other : List Rule} (joined : Joined rules) (sublist : other.Sublist rules) :
    Joined other :=
  ⟨fun rule isMember => joined.1 rule (sublist.subset isMember), joined.2.sublist sublist⟩

theorem Joined.sortRules {rules : List Rule} (joined : Joined rules) : Joined (sortRules rules) :=
  let ⟨_, permutation, sublist⟩ := sortByKey_sublist Rule.key rules
  (joined.perm permutation.symm).sublist sublist

/-- A rule that joins on no array relates to every rule. -/
theorem joinsApart_of_none {first second : Rule} (none : first.joinable? = none ∨ second.joinable? = none) :
    ∀ arrayPath, ¬(first.joinsOn arrayPath ∧ second.joinsOn arrayPath) := by
  intro arrayPath both
  rcases none with none | none
  · simp [Rule.joinsOn_of_joinable?_none none] at both
  · simp [Rule.joinsOn_of_joinable?_none none] at both

theorem Rule.fused_joinable? {rules : List Rule} {rule result : Rule} (fused : rule.fused rules = some result) :
    result = rule ∨ result.joinable? = none := by
  unfold Rule.fused at fused
  split at fused
  · obtain ⟨_, _, rfl⟩ := Option.map_eq_some_iff.mp fused
    exact .inr (Rule.joinable?_of_isLoop (Subject.range_isLoop _ _ _ _))
  · simp at fused
  · exact .inl (Option.some.inj fused).symm

theorem Joined.fuseRanges {rules : List Rule} (joined : Joined rules) : Joined (fuseRanges rules) := by
  refine ⟨fun result isMember arrayPath group joinable => ?_, ?_⟩
  · obtain ⟨rule, ruleIsMember, fused⟩ := List.mem_filterMap.mp isMember
    rcases Rule.fused_joinable? fused with rfl | none
    · exact joined.1 result ruleIsMember arrayPath group joinable
    · simp [none] at joinable
  · refine List.pairwise_filterMap.mpr (joined.2.imp fun distinct first firstFused second secondFused => ?_)
    rcases Rule.fused_joinable? firstFused with rfl | none
    · rcases Rule.fused_joinable? secondFused with rfl | otherNone
      · exact distinct
      · exact joinsApart_of_none (.inr otherNone)
    · exact joinsApart_of_none (.inl none)

theorem Joined.finishRules {rules : List Rule} (joined : Joined rules) : Joined (finishRules rules) :=
  joined.sortRules.fuseRanges.sortRules

theorem Joined.hoistContext {rules : List Rule} (joined : Joined rules) : Joined (hoistContext rules) := by
  refine ⟨fun result isMember arrayPath group joinable => ?_, ?_⟩
  · rcases mem_hoistContext.mp isMember with ⟨rule, ruleIsMember, rfl⟩ | ⟨rule, _, inHoisted⟩
    · rw [Rule.withoutHoisted_joinable?] at joinable
      exact joined.1 rule ruleIsMember arrayPath group joinable
    · simp [Rule.joinable?_of_isContextTest (mem_hoisted inHoisted).1] at joinable
  · simp only [Callcium.hoistContext]
    refine List.pairwise_append.mpr ⟨?_, ?_, ?_⟩
    · refine List.pairwise_map.mpr (joined.2.imp fun distinct arrayPath both => distinct arrayPath ?_)
      simpa [Rule.joinsOn, Rule.withoutHoisted_joinable?] using both
    · exact List.pairwise_of_forall_mem_list fun first firstIsMember _ _ =>
        joinsApart_of_none (.inl (by
          obtain ⟨rule, _, inHoisted⟩ := List.mem_flatMap.mp firstIsMember
          exact Rule.joinable?_of_isContextTest (mem_hoisted inHoisted).1))
    · intro _ _ second secondIsMember
      obtain ⟨rule, _, inHoisted⟩ := List.mem_flatMap.mp secondIsMember
      exact joinsApart_of_none (.inr (Rule.joinable?_of_isContextTest (mem_hoisted inHoisted).1))

theorem joinLoops_of_joined {rules : List Rule} (joined : Joined rules) : joinLoops rules = rules := by
  induction rules with
  | nil => simp [joinLoops]
  | cons rule rules restFixed =>
    obtain ⟨finished, distinct⟩ := joined
    rw [List.pairwise_cons] at distinct
    have rest := restFixed ⟨fun other isMember => finished other (by simp [isMember]), distinct.2⟩
    rcases joinable : rule.joinable? with _ | ⟨arrayPath, group⟩
    · rw [joinLoops, joinable]
      dsimp only
      rw [rest]
    · have apart : ∀ other ∈ rules, other.joinsOn arrayPath = false := by
        intro other isMember
        cases joins : other.joinsOn arrayPath
        · rfl
        · exact absurd ⟨Rule.joinsOn_iff.mpr ⟨group, joinable⟩, joins⟩ (distinct.1 other isMember arrayPath)
      rw [joinLoops, joinable]
      dsimp only
      rw [List.filter_eq_nil_iff.mpr (fun other isMember => by simp [apart other isMember]),
        List.filter_eq_self.mpr (fun other isMember => by simp [apart other isMember]), rest, List.flatMap_nil,
        List.append_nil, finished rule (by simp) arrayPath group joinable, ← Rule.eq_of_joinable? joinable]

theorem joined_joinLoops (rules : List Rule) : Joined (joinLoops rules) := by
  induction rules using joinLoops.induct with
  | case1 => simp [joinLoops, Joined]
  | case2 rule rules arrayPath group joinable restJoined =>
    simp only [List.unattach_filter, List.unattach_attach] at restJoined
    rw [joinLoops, joinable]
    dsimp only
    refine ⟨fun emitted isMember loopPath body emittedJoinable => ?_, List.pairwise_cons.mpr ⟨?_, restJoined.2⟩⟩
    · rcases List.mem_cons.mp isMember with rfl | inRest
      · rw [joinable?_joined joinable] at emittedJoinable
        cases emittedJoinable
        exact finishRules_idem _
      · exact restJoined.1 emitted inRest loopPath body emittedJoinable
    · intro emitted isMember loopPath both
      have firstJoins := both.1
      rw [Rule.joinsOn_iff, joinable?_joined joinable] at firstJoins
      obtain ⟨_, same⟩ := firstJoins
      cases same
      obtain ⟨other, otherIsMember, otherJoins⟩ := joinsOn_of_mem_joinLoops emitted isMember both.2
      simp_all [List.mem_filter]
  | case3 rule rules notJoinable restJoined =>
    rw [joinLoops, notJoinable]
    dsimp only
    refine ⟨fun emitted isMember loopPath body emittedJoinable => ?_, List.pairwise_cons.mpr ⟨?_, restJoined.2⟩⟩
    · rcases List.mem_cons.mp isMember with rfl | inRest
      · simp_all
      · exact restJoined.1 emitted inRest loopPath body emittedJoinable
    · intro _ _ loopPath both
      simp_all [Rule.joinsOn_iff]

/-! ## Theorem 22: normalizing keeps the meaning -/

theorem finishRules_holds (rules : List Rule) (ctx : Context) (stack : Stack) :
    Group.holds ctx stack (finishRules rules) = Group.holds ctx stack rules := by
  simp only [Group.holds_eq]
  exact finishRules_all _ (fun subject length lower upper => Subject.range_holds subject length lower upper ctx stack) rules

theorem finishRules_withinLimits (rules : List Rule) (stack : Stack) :
    Group.withinLimits stack (finishRules rules) = Group.withinLimits stack rules := by
  simp only [Group.withinLimits_eq]
  exact finishRules_all _ (fun subject length lower upper => by
    simp [Rule.withinLimits_of_isLoop (Subject.range_isLoop _ _ _ _), Subject.bound,
      Rule.withinLimits_of_isLoop (Subject.rule_isLoop _ _)]) rules

theorem Rule.holds_loop_split (ctx : Context) (stack : Stack) : JoinSplits (·.holds ctx stack) where
  split arrayPath first second := by
    simp only [Rule.holds]
    split <;> simp [all_and_distrib]
  finish arrayPath rules := by
    simp only [Rule.holds]
    split <;> try rfl
    simp only [finishRules_holds]

theorem Group.normalize_holds (group : Group)
    (preserved : ∀ rule ∈ group, ∀ ctx stack, rule.normalize.holds ctx stack = rule.holds ctx stack)
    (ctx : Context) (stack : Stack) : Group.holds ctx stack (Group.normalize group) = Group.holds ctx stack group := by
  simp only [Group.holds_eq, Group.normalize, Group.normalizeEach_eq]
  rw [finishRules_all _ (fun subject length lower upper => Subject.range_holds subject length lower upper ctx stack),
    hoistContext_all _ (fun rule => Rule.holds_hoist rule ctx stack), (Rule.holds_loop_split ctx stack).all_joinLoops,
    List.all_map]
  exact all_congr_mem fun rule isMember => preserved rule isMember ctx stack

theorem Rule.normalize_holds (rule : Rule) :
    ∀ ctx stack, rule.normalize.holds ctx stack = rule.holds ctx stack := by
  induction rule with
  | test path operator => intro ctx stack; simp [Rule.normalize, Rule.holds, Operator.normalize_holds]
  | contextTest property operator =>
    intro ctx stack
    simp [Rule.normalize, Rule.contextTestBySubject_holds, Rule.holds, Operator.normalize_holds]
  | loop quantifier arrayPath body bodyPreserved =>
    intro ctx stack
    simp only [Rule.normalize_loop, Rule.holds, Group.normalize_holds body bodyPreserved]

/-- Theorem 22. -/
theorem normalize_holds (formula : Formula) (ctx : Context) (stack : Stack) :
    (normalize formula).holds ctx stack = formula.holds ctx stack := by
  simp only [normalize, sortGroups, Formula.holds_eq]
  rw [any_sortByKey, List.any_map]
  exact any_congr_mem fun group _ => Group.normalize_holds group (fun rule _ => rule.normalize_holds) ctx stack

/-! ## Theorem 25: normalizing keeps the limits -/

theorem Rule.withinLimits_loop_split (stack : Stack) : JoinSplits (·.withinLimits stack) where
  split arrayPath first second := by
    simp only [Rule.withinLimits]
    split <;> simp [all_and_distrib] <;> cases decide (_ ≤ MAX_QUANTIFIED_ARRAY_LENGTH) <;> simp
  finish arrayPath rules := by
    simp only [Rule.withinLimits]
    split <;> try rfl
    simp only [finishRules_withinLimits]

theorem Group.normalize_withinLimits (group : Group)
    (preserved : ∀ rule ∈ group, ∀ stack, rule.normalize.withinLimits stack = rule.withinLimits stack)
    (stack : Stack) : Group.withinLimits stack (Group.normalize group) = Group.withinLimits stack group := by
  simp only [Group.withinLimits_eq, Group.normalize, Group.normalizeEach_eq]
  rw [finishRules_all _ (fun subject length lower upper => by
      simp [Rule.withinLimits_of_isLoop (Subject.range_isLoop _ _ _ _), Subject.bound,
        Rule.withinLimits_of_isLoop (Subject.rule_isLoop _ _)]),
    hoistContext_all _ (fun rule => Rule.withinLimits_hoist rule stack),
    (Rule.withinLimits_loop_split stack).all_joinLoops, List.all_map]
  exact all_congr_mem fun rule isMember => preserved rule isMember stack

theorem Rule.normalize_withinLimits (rule : Rule) :
    ∀ stack, rule.normalize.withinLimits stack = rule.withinLimits stack := by
  induction rule with
  | loop quantifier arrayPath body bodyPreserved =>
    intro stack
    simp only [Rule.normalize_loop, Rule.withinLimits, Group.normalize_withinLimits body bodyPreserved]
  | _ =>
    intro stack
    rw [Rule.withinLimits_of_isLoop (by rw [Rule.normalize_isLoop]; rfl), Rule.withinLimits_of_isLoop rfl]

/-- Theorem 25. -/
theorem normalize_withinLimits (formula : Formula) (stack : Stack) :
    (normalize formula).withinLimits stack = formula.withinLimits stack := by
  simp only [normalize, sortGroups, Formula.withinLimits_eq]
  rw [all_sortByKey, List.all_map]
  exact all_congr_mem fun group _ => Group.normalize_withinLimits group (fun rule _ => rule.normalize_withinLimits) stack

/-! ## Normal forms -/

@[simp] theorem Group.rulesNormal_eq (group : Group) : Group.rulesNormal group = group.all Rule.normal := by
  induction group <;> simp [Group.rulesNormal, *]

theorem Rule.normal_loop (quantifier : Quantifier) (arrayPath : Path) (body : Group) :
    (Rule.loop quantifier arrayPath body).normal = Group.normal body :=
  rfl

theorem Group.normal_iff_parts {group : Group} :
    Group.normal group = true ↔ (∀ rule ∈ group, rule.normal = true) ∧ strictlySorted Rule.key group = true ∧
      Group.joinsApart group = true ∧ Group.noLonePair group = true ∧ Group.nothingHoisted group = true := by
  simp [Group.normal, Group.arranged, Bool.and_eq_true, List.all_eq_true, and_assoc]

theorem Subject.range_normal (subject : Subject) (length : Bool) (lower upper : Word) :
    (subject.range length lower upper).normal = true := by
  cases subject <;> cases length <;> rfl

theorem Rule.hoisted_of_isLoop {rule : Rule} (notLoop : rule.isLoop = false) : rule.hoisted = [] := by
  cases rule <;> simp_all [Rule.isLoop, Rule.hoisted]

theorem Rule.joinPath?_of_isLoop {rule : Rule} (notLoop : rule.isLoop = false) : rule.joinPath? = none := by
  simp [Rule.joinPath?, Rule.joinable?_of_isLoop notLoop]

theorem Rule.joinsOn_iff_joinPath? {rule : Rule} {arrayPath : Path} :
    rule.joinsOn arrayPath ↔ rule.joinPath? = some arrayPath := by
  rw [Rule.joinsOn_iff]
  rcases joinable : rule.joinable? with _ | ⟨path, group⟩ <;> simp [Rule.joinPath?, joinable, eq_comm]

theorem joinsApart_iff {group : Group} :
    group.joinsApart = true ↔ group.Pairwise fun first second => ∀ arrayPath,
      ¬(first.joinsOn arrayPath = true ∧ second.joinsOn arrayPath = true) := by
  simp only [Group.joinsApart, decide_eq_true_eq, Rule.joinsOn_iff_joinPath?]
  refine List.pairwise_iff_forall_sublist.trans (List.pairwise_iff_forall_sublist.trans ?_).symm |>.symm
  refine forall_congr' fun first => forall_congr' fun second => imp_congr_right fun _ => ?_
  rcases first.joinPath? with _ | path <;> rcases second.joinPath? with _ | otherPath <;> simp [eq_comm]

theorem joinsApart_of_loopFree {group : Group} (loopFree : ∀ rule ∈ group, rule.isLoop = false) :
    Group.joinsApart group = true := by
  simp only [Group.joinsApart, decide_eq_true_eq]
  exact List.pairwise_of_forall_mem_list fun first firstIsMember _ _ =>
    .inl (Rule.joinPath?_of_isLoop (loopFree first firstIsMember))

theorem nothingHoisted_of_loopFree {group : Group} (loopFree : ∀ rule ∈ group, rule.isLoop = false) :
    Group.nothingHoisted group = true := by
  simp only [Group.nothingHoisted, List.all_eq_true]
  intro rule isMember
  simp [Rule.hoisted_of_isLoop (loopFree rule isMember)]

/-- A group of canonical rules whose joinable loops are over distinct arrays has nothing left to join. -/
theorem joined_of_normal {group : Group} (normal : ∀ rule ∈ group, rule.normal = true)
    (apart : group.joinsApart = true) : Joined group := by
  refine ⟨fun rule isMember arrayPath body joinable => ?_, joinsApart_iff.mp apart⟩
  have ruleNormal := normal rule isMember
  rw [Rule.eq_of_joinable? joinable, Rule.normal_loop] at ruleNormal
  obtain ⟨_, sorted, _, noLone, _⟩ := Group.normal_iff_parts.mp ruleNormal
  exact finishRules_of_arranged sorted noLone

/-- An `ALL` loop over the finished body of loop-free, canonical rules is canonical. -/
theorem normal_finished_loop {arrayPath : Path} {rules : List Rule} (loopFree : ∀ rule ∈ rules, rule.isLoop = false)
    (normal : ∀ rule ∈ rules, rule.normal = true) : (Rule.loop .all arrayPath (finishRules rules)).normal = true := by
  rw [Rule.normal_loop, Group.normal_iff_parts]
  have finishedLoopFree := loopFree_finishRules loopFree
  refine ⟨fun rule isMember => ?_, strictlySorted_finishRules _, joinsApart_of_loopFree finishedLoopFree,
    noLonePair_finishRules _, nothingHoisted_of_loopFree finishedLoopFree⟩
  rcases mem_finishRules isMember with inRules | ⟨subject, length, lower, upper, rfl⟩
  · exact normal rule inRules
  · exact Subject.range_normal _ _ _ _

/-- Joining canonical rules emits canonical rules. -/
theorem normal_of_mem_joinLoops {rules : List Rule} (normal : ∀ rule ∈ rules, rule.normal = true) :
    ∀ rule ∈ joinLoops rules, rule.normal = true := by
  induction rules using joinLoops.induct with
  | case1 => simp [joinLoops]
  | case2 rule rules arrayPath group joinable restNormal =>
    simp only [List.unattach_filter, List.unattach_attach] at restNormal
    rw [joinLoops, joinable]
    dsimp only
    intro emitted isMember
    rcases List.mem_cons.mp isMember with rfl | inRest
    · refine normal_finished_loop (fun member memberIsMember => ?_) (fun member memberIsMember => ?_)
      · obtain ⟨other, _, body, otherJoinable, inBody⟩ := mem_joinedBody joinable memberIsMember
        exact Rule.loopFree_of_joinable? otherJoinable member inBody
      · obtain ⟨other, otherIsMember, body, otherJoinable, inBody⟩ := mem_joinedBody joinable memberIsMember
        have otherNormal := normal other otherIsMember
        rw [Rule.eq_of_joinable? otherJoinable, Rule.normal_loop] at otherNormal
        exact (Group.normal_iff_parts.mp otherNormal).1 member inBody
    · exact restNormal (fun other otherIsMember => normal other (by simp [(List.mem_filter.mp otherIsMember).1]))
        emitted inRest
  | case3 rule rules notJoinable restNormal =>
    rw [joinLoops, notJoinable]
    dsimp only
    intro emitted isMember
    rcases List.mem_cons.mp isMember with rfl | inRest
    · exact normal emitted (by simp)
    · exact restNormal (fun other otherIsMember => normal other (by simp [otherIsMember])) emitted inRest

theorem Rule.normal_withoutHoisted {rule : Rule} (normal : rule.normal = true) : rule.withoutHoisted.normal = true := by
  rcases rule with _ | _ | ⟨_ | _, arrayPath, body⟩ <;> simp only [Rule.withoutHoisted] <;> try exact normal
  split
  · rw [Rule.normal_loop] at normal ⊢
    obtain ⟨rulesNormal, sorted, apart, noLone, nothing⟩ := Group.normal_iff_parts.mp normal
    have sublist : (body.filter (!·.isContextTest)).Sublist body := List.filter_sublist
    refine Group.normal_iff_parts.mpr ⟨fun member isMember => rulesNormal member (sublist.subset isMember),
      strictlySorted_sublist sorted sublist, ?_, Group.noLonePair_filter_contextTests noLone, ?_⟩
    · simp only [Group.joinsApart, decide_eq_true_eq] at apart ⊢
      exact apart.sublist sublist
    · simp only [Group.nothingHoisted, List.all_eq_true] at nothing ⊢
      exact fun member isMember => nothing member (sublist.subset isMember)
  · exact normal

theorem normal_of_mem_hoisted {rule member : Rule} (normal : rule.normal = true) (isMember : member ∈ rule.hoisted) :
    member.normal = true := by
  obtain ⟨_, arrayPath, body, rfl, inBody⟩ := mem_hoisted isMember
  rw [Rule.normal_loop] at normal
  exact (Group.normal_iff_parts.mp normal).1 member inBody

/-- Normalizing a canonical group changes nothing. -/
theorem Group.normalize_of_normal {group : Group} (fixed : ∀ rule ∈ group, rule.normalize = rule)
    (normal : Group.normal group = true) : Group.normalize group = group := by
  obtain ⟨rulesNormal, sorted, apart, noLone, nothing⟩ := Group.normal_iff_parts.mp normal
  simp only [Group.normalize, Group.normalizeEach_eq]
  rw [List.map_congr_left fixed, List.map_id', joinLoops_of_joined (joined_of_normal rulesNormal apart),
    hoistContext_of_nothingHoisted nothing, finishRules_of_arranged sorted noLone]

/-- Normalizing a group whose rules normalize to canonical rules emits a canonical group. -/
theorem Group.normal_normalize_of {group : Group} (normal : ∀ rule ∈ group, rule.normalize.normal = true) :
    Group.normal (Group.normalize group) = true := by
  simp only [Group.normalize, Group.normalizeEach_eq]
  have joinedNormal := normal_of_mem_joinLoops (rules := group.map Rule.normalize) (by simpa using normal)
  have hoistedNormal : ∀ rule ∈ hoistContext (joinLoops (group.map Rule.normalize)), rule.normal = true := by
    intro rule isMember
    rcases mem_hoistContext.mp isMember with ⟨original, originalIsMember, rfl⟩ |
        ⟨original, originalIsMember, inHoisted⟩
    · exact Rule.normal_withoutHoisted (joinedNormal original originalIsMember)
    · exact normal_of_mem_hoisted (joinedNormal original originalIsMember) inHoisted
  have joined := (joined_joinLoops (group.map Rule.normalize)).hoistContext.finishRules
  refine Group.normal_iff_parts.mpr ⟨fun rule isMember => ?_, strictlySorted_finishRules _,
    joinsApart_iff.mpr joined.2, noLonePair_finishRules _, ?_⟩
  · rcases mem_finishRules isMember with inHoisted | ⟨subject, length, lower, upper, rfl⟩
    · exact hoistedNormal rule inHoisted
    · exact Subject.range_normal _ _ _ _
  · simp only [Group.nothingHoisted, List.all_eq_true, List.isEmpty_iff]
    intro rule isMember
    rcases mem_finishRules isMember with inHoisted | ⟨subject, length, lower, upper, rfl⟩
    · rcases mem_hoistContext.mp inHoisted with ⟨original, _, rfl⟩ | ⟨original, _, inHoistedRules⟩
      · exact Rule.hoisted_withoutHoisted original
      · exact Rule.hoisted_of_isLoop (Rule.isLoop_of_isContextTest (mem_hoisted inHoistedRules).1)
    · exact Rule.hoisted_of_isLoop (Subject.range_isLoop _ _ _ _)

/-- Normalizing emits a canonical rule. -/
theorem Rule.normal_normalize (rule : Rule) : rule.normalize.normal = true := by
  induction rule with
  | test path operator => exact Operator.normal_normalize operator
  | contextTest property operator => exact Rule.normal_contextTestBySubject (Operator.normal_normalize operator)
  | loop quantifier arrayPath body bodyNormal =>
    rw [Rule.normalize_loop, Rule.normal_loop]
    exact Group.normal_normalize_of bodyNormal

/-- Normalizing a canonical rule changes nothing. -/
theorem Rule.normalize_of_normal (rule : Rule) : rule.normal = true → rule.normalize = rule := by
  induction rule with
  | test path operator =>
    intro normal
    simp only [Rule.normalize, Operator.normalize_of_normal (by simpa [Rule.normal] using normal)]
  | contextTest property operator =>
    intro normal
    simp only [Rule.normal, Bool.and_eq_true] at normal
    simp only [Rule.normalize, Operator.normalize_of_normal normal.1,
      Rule.contextTestBySubject_of_subjectNormal normal.2]
  | loop quantifier arrayPath body bodyFixed =>
    intro normal
    rw [Rule.normal_loop] at normal
    rw [Rule.normalize_loop, Group.normalize_of_normal (fun rule isMember =>
      bodyFixed rule isMember ((Group.normal_iff_parts.mp normal).1 rule isMember)) normal]

theorem Rule.normalize_idem (rule : Rule) : rule.normalize.normalize = rule.normalize :=
  Rule.normalize_of_normal _ (Rule.normal_normalize rule)

theorem Group.normal_normalize (group : Group) : Group.normal (Group.normalize group) = true :=
  Group.normal_normalize_of fun rule _ => rule.normal_normalize

theorem Group.normalize_idem (group : Group) : Group.normalize (Group.normalize group) = Group.normalize group :=
  Group.normalize_of_normal (fun rule isMember => Rule.normalize_of_normal rule
    ((Group.normal_iff_parts.mp (Group.normal_normalize group)).1 rule isMember)) (Group.normal_normalize group)

/-! ## Theorem 23: normalizing twice changes nothing -/

/-- Theorem 23. -/
theorem normalize_idem (formula : Formula) : normalize (normalize formula) = normalize formula := by
  have fixed : ∀ group ∈ normalize formula, Group.normalize group = group := by
    intro group isMember
    obtain ⟨original, _, rfl⟩ := List.mem_map.mp ((mem_sortByKey _ _ _).mp isMember)
    exact Group.normalize_idem original
  rw [normalize, List.map_congr_left fixed, List.map_id', normalize]
  exact sortByKey_idem _ _

/-! ## Theorem 32: the author's order and repetitions do not reach the canonical form -/

theorem Group.keyOf_injective : ∀ {group other : Group}, Group.keyOf group = Group.keyOf other → group = other
  | [], [], _ => rfl
  | [], rule :: _, same => by cases rule <;> simp [Group.keyOf, Rule.key] at same
  | rule :: _, [], same => by cases rule <;> simp [Group.keyOf, Rule.key] at same
  | rule :: _, other :: _, same => by
    simp only [Group.keyOf] at same
    obtain ⟨rfl, rest⟩ := Rule.key_append_inj rule other _ _ same
    rw [Group.keyOf_injective rest]

/-- The rules of the bodies of the loops joinable over `arrayPath`. -/
def bodiesOn (arrayPath : Path) (rules : List Rule) : List Rule :=
  rules.flatMap fun rule => if rule.joinsOn arrayPath then (rule.joinable?.map (·.2)).getD [] else []

theorem bodiesOn_eq (arrayPath : Path) (rules : List Rule) :
    bodiesOn arrayPath rules = (rules.filter (·.joinsOn arrayPath)).flatMap
      fun rule => (rule.joinable?.map (·.2)).getD [] := by
  induction rules with
  | nil => rfl
  | cons rule rules restEqual => cases joins : rule.joinsOn arrayPath <;> simp_all [bodiesOn]

theorem Rule.joinsOn_unique {rule : Rule} {arrayPath other : Path} (joins : rule.joinsOn arrayPath)
    (otherJoins : rule.joinsOn other) : arrayPath = other := by
  obtain ⟨_, joinable⟩ := Rule.joinable?_of_joinsOn joins
  obtain ⟨_, otherJoinable⟩ := Rule.joinable?_of_joinsOn otherJoins
  rw [joinable] at otherJoinable
  cases otherJoinable
  rfl

/-- Removing the loops joinable over one array leaves the bodies over every other array. -/
theorem bodiesOn_filter {arrayPath other : Path} (different : other ≠ arrayPath) (rules : List Rule) :
    bodiesOn other (rules.filter (!·.joinsOn arrayPath)) = bodiesOn other rules := by
  induction rules with
  | nil => rfl
  | cons rule rules restEqual =>
    cases joins : rule.joinsOn arrayPath
    · simp_all [bodiesOn]
    · have : rule.joinsOn other = false := by
        cases otherJoins : rule.joinsOn other
        · rfl
        · exact absurd (Rule.joinsOn_unique otherJoins joins) different
      simp_all [bodiesOn]

/-- `joinLoops` emits every rule that is not a joinable loop, and one loop per joinable array. That loop's body is the
canonical union of the bodies over it. -/
theorem mem_joinLoops {rules : List Rule} {rule : Rule} :
    rule ∈ joinLoops rules ↔ (rule ∈ rules ∧ rule.joinable? = none) ∨
      ∃ arrayPath, (∃ other ∈ rules, other.joinsOn arrayPath) ∧
        rule = .loop .all arrayPath (finishRules (bodiesOn arrayPath rules)) := by
  induction rules using joinLoops.induct generalizing rule with
  | case1 => simp [joinLoops]
  | case2 first rules arrayPath group joinable restMembers =>
    simp only [List.unattach_filter, List.unattach_attach] at restMembers
    have firstJoins : first.joinsOn arrayPath := Rule.joinsOn_iff.mpr ⟨group, joinable⟩
    have merged : bodiesOn arrayPath (first :: rules) =
        group ++ (rules.filter (·.joinsOn arrayPath)).flatMap fun rule => (rule.joinable?.map (·.2)).getD [] := by
      rw [← bodiesOn_eq]
      simp [bodiesOn, firstJoins, joinable]
    have otherBodies : ∀ other, other ≠ arrayPath →
        bodiesOn other (first :: rules) = bodiesOn other (rules.filter (!·.joinsOn arrayPath)) := by
      intro other different
      have : first.joinsOn other = false := by
        cases otherJoins : first.joinsOn other
        · rfl
        · exact absurd (Rule.joinsOn_unique otherJoins firstJoins) different
      rw [bodiesOn_filter different]
      simp [bodiesOn, this]
    rw [joinLoops, joinable]
    dsimp only
    rw [List.mem_cons, restMembers]
    constructor
    · rintro (rfl | (⟨isMember, none⟩ | ⟨other, ⟨witness, witnessMember, witnessJoins⟩, rfl⟩))
      · exact .inr ⟨arrayPath, ⟨first, by simp, firstJoins⟩, by rw [merged]⟩
      · exact .inl ⟨by simp [(List.mem_filter.mp isMember).1], none⟩
      · have different : other ≠ arrayPath := fun equal => by
          subst equal
          simp_all [List.mem_filter]
        exact .inr ⟨other, ⟨witness, by simp [(List.mem_filter.mp witnessMember).1], witnessJoins⟩,
          by rw [otherBodies other different]⟩
    · rintro (⟨isMember, none⟩ | ⟨other, ⟨witness, witnessMember, witnessJoins⟩, rfl⟩)
      · rcases List.mem_cons.mp isMember with rfl | inRules
        · simp_all
        · refine .inr (.inl ⟨List.mem_filter.mpr ⟨inRules, ?_⟩, none⟩)
          simp [Rule.joinsOn, none]
      · by_cases same : other = arrayPath
        · subst same
          exact .inl (by rw [merged])
        · refine .inr (.inr ⟨other, ⟨witness, ?_, witnessJoins⟩, by rw [otherBodies other same]⟩)
          rcases List.mem_cons.mp witnessMember with rfl | inRules
          · exact absurd (Rule.joinsOn_unique witnessJoins firstJoins) same
          · refine List.mem_filter.mpr ⟨inRules, ?_⟩
            cases joins : witness.joinsOn arrayPath
            · rfl
            · exact absurd (Rule.joinsOn_unique witnessJoins joins) same
  | case3 first rules notJoinable restMembers =>
    have notJoins : ∀ arrayPath, first.joinsOn arrayPath = false := by simp [Rule.joinsOn, notJoinable]
    have sameBodies : ∀ arrayPath, bodiesOn arrayPath (first :: rules) = bodiesOn arrayPath rules := by
      simp [bodiesOn, notJoins]
    rw [joinLoops, notJoinable]
    dsimp only
    rw [List.mem_cons, restMembers]
    simp only [sameBodies, List.mem_cons]
    constructor
    · rintro (rfl | (⟨isMember, none⟩ | ⟨other, ⟨witness, witnessMember, witnessJoins⟩, equal⟩))
      · exact .inl ⟨.inl rfl, notJoinable⟩
      · exact .inl ⟨.inr isMember, none⟩
      · exact .inr ⟨other, ⟨witness, .inr witnessMember, witnessJoins⟩, equal⟩
    · rintro (⟨rfl | isMember, none⟩ | ⟨other, ⟨witness, rfl | witnessMember, witnessJoins⟩, equal⟩)
      · exact .inl rfl
      · exact .inr (.inl ⟨isMember, none⟩)
      · simp [notJoins] at witnessJoins
      · exact .inr (.inr ⟨other, ⟨witness, witnessMember, witnessJoins⟩, equal⟩)

/-- `joinLoops` emits the same members for inputs with the same members. -/
theorem joinLoops_members {rules other : List Rule} (same : ∀ rule, rule ∈ rules ↔ rule ∈ other) (rule : Rule) :
    rule ∈ joinLoops rules ↔ rule ∈ joinLoops other := by
  have bodies : ∀ arrayPath, finishRules (bodiesOn arrayPath rules) = finishRules (bodiesOn arrayPath other) :=
    fun arrayPath => finishRules_eq_of_members fun member => by simp [bodiesOn, same]
  simp only [mem_joinLoops, same, bodies]

theorem Group.normalize_eq_of_members {group other : Group}
    (same : ∀ rule, rule ∈ group.map Rule.normalize ↔ rule ∈ other.map Rule.normalize) :
    Group.normalize group = Group.normalize other := by
  simp only [Group.normalize, Group.normalizeEach_eq]
  refine finishRules_eq_of_members fun rule => ?_
  simp only [mem_hoistContext, joinLoops_members same]

theorem sortGroups_eq_of_members {formula other : Formula} (same : ∀ group, group ∈ formula ↔ group ∈ other) :
    sortGroups formula = sortGroups other :=
  sortByKey_eq_of_members Group.keyOf_injective same

mutual
  /-- Two rules equal up to the order and repetition of the rules in their loop bodies. -/
  inductive Rule.SameMembers : Rule → Rule → Prop
    | refl (rule : Rule) : Rule.SameMembers rule rule
    | loop (quantifier : Quantifier) (arrayPath : Path) {body other : Group} :
      Group.SameMembers body other → Rule.SameMembers (.loop quantifier arrayPath body) (.loop quantifier arrayPath other)

  /-- Two groups with the same members at every level: equal up to order and repetition. -/
  inductive Group.SameMembers : Group → Group → Prop
    | nil : Group.SameMembers [] []
    | cons {rule other : Rule} {rules others : Group} :
      Rule.SameMembers rule other → Group.SameMembers rules others → Group.SameMembers (rule :: rules) (other :: others)
    | swap (first second : Rule) (rules : Group) : Group.SameMembers (first :: second :: rules) (second :: first :: rules)
    | dup (rule : Rule) (rules : Group) : Group.SameMembers (rule :: rules) (rule :: rule :: rules)
    | symm {first second : Group} : Group.SameMembers first second → Group.SameMembers second first
    | trans {first second third : Group} :
      Group.SameMembers first second → Group.SameMembers second third → Group.SameMembers first third
end

/-- Two formulas with the same members at every level: equal up to order and repetition. -/
inductive Formula.SameMembers : Formula → Formula → Prop
  | nil : Formula.SameMembers [] []
  | cons {group other : Group} {groups others : Formula} :
    Group.SameMembers group other → Formula.SameMembers groups others →
      Formula.SameMembers (group :: groups) (other :: others)
  | swap (first second : Group) (groups : Formula) :
    Formula.SameMembers (first :: second :: groups) (second :: first :: groups)
  | dup (group : Group) (groups : Formula) : Formula.SameMembers (group :: groups) (group :: group :: groups)
  | symm {first second : Formula} : Formula.SameMembers first second → Formula.SameMembers second first
  | trans {first second third : Formula} :
    Formula.SameMembers first second → Formula.SameMembers second third → Formula.SameMembers first third

mutual
  theorem Rule.SameMembers.normalize_eq {rule other : Rule} :
      Rule.SameMembers rule other → rule.normalize = other.normalize
    | .refl _ => rfl
    | .loop _ _ same => by
      rw [Rule.normalize_loop, Rule.normalize_loop, Group.normalize_eq_of_members same.members]

  theorem Group.SameMembers.members {group other : Group} :
      Group.SameMembers group other → ∀ rule, rule ∈ group.map Rule.normalize ↔ rule ∈ other.map Rule.normalize
    | .nil => fun _ => Iff.rfl
    | .cons first rest => fun rule => by
      simp only [List.map_cons, List.mem_cons, first.normalize_eq, rest.members rule]
    | .swap _ _ _ => fun _ => by simp only [List.map_cons, List.mem_cons, or_left_comm]
    | .dup _ _ => fun _ => by simp only [List.map_cons, List.mem_cons, ← or_assoc, or_self]
    | .symm same => fun rule => (same.members rule).symm
    | .trans first second => fun rule => (first.members rule).trans (second.members rule)
end

theorem Formula.SameMembers.members {formula other : Formula} :
    Formula.SameMembers formula other →
      ∀ group, group ∈ formula.map Group.normalize ↔ group ∈ other.map Group.normalize
  | .nil => fun _ => Iff.rfl
  | .cons first rest => fun group => by
    simp only [List.map_cons, List.mem_cons, Group.normalize_eq_of_members first.members, rest.members group]
  | .swap _ _ _ => fun _ => by simp only [List.map_cons, List.mem_cons, or_left_comm]
  | .dup _ _ => fun _ => by simp only [List.map_cons, List.mem_cons, ← or_assoc, or_self]
  | .symm same => fun group => (same.members group).symm
  | .trans first second => fun group => (first.members group).trans (second.members group)

/-- Theorem 32. -/
theorem normalize_of_sameMembers {formula other : Formula} (same : Formula.SameMembers formula other) :
    normalize formula = normalize other :=
  sortGroups_eq_of_members same.members

/-! ## Theorem 33: normal forms are exactly the fixed points of `normalize` -/

/-- Theorem 33. -/
theorem normal_iff_fixed (formula : Formula) : formula.normal = true ↔ normalize formula = formula := by
  constructor
  · intro normal
    simp only [Formula.normal, Bool.and_eq_true, List.all_eq_true] at normal
    obtain ⟨groupsNormal, sorted⟩ := normal
    rw [normalize, List.map_congr_left fun group isMember => Group.normalize_of_normal
      (fun rule ruleIsMember => Rule.normalize_of_normal rule
        ((Group.normal_iff_parts.mp (groupsNormal group isMember)).1 rule ruleIsMember)) (groupsNormal group isMember),
      List.map_id']
    exact (sortByKey_eq_self_iff Group.keyOf_injective).mpr sorted
  · intro fixed
    rw [← fixed]
    simp only [Formula.normal, Bool.and_eq_true, List.all_eq_true]
    refine ⟨fun group isMember => ?_, strictlySorted_sortByKey Group.keyOf_injective _⟩
    obtain ⟨original, _, rfl⟩ := List.mem_map.mp ((mem_sortByKey _ _ _).mp isMember)
    exact Group.normal_normalize original

/-- Every normalized formula is in canonical form. -/
theorem normal_normalize (formula : Formula) : (normalize formula).normal = true :=
  (normal_iff_fixed _).mpr (normalize_idem formula)

end Callcium
