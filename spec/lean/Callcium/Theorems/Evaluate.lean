import Callcium.Evaluate
import Callcium.Theorems.Normalize

/-!
# Value-level evaluation

Theorem 15: a pass means the policy holds. Theorem 34: a verdict other than abort is the denotation's. Theorem 16:
within limits the evaluator never aborts. Theorem 21: within limits, a policy that holds passes.
-/

namespace Callcium

/-! ## Equations -/

@[simp] theorem Verdict.ofBool_eq_pass (holds : Bool) : Verdict.ofBool holds = .pass ↔ holds = true := by
  cases holds <;> simp [Verdict.ofBool]

@[simp] theorem Verdict.ofBool_eq_fail (holds : Bool) : Verdict.ofBool holds = .fail ↔ holds = false := by
  cases holds <;> simp [Verdict.ofBool]

@[simp] theorem Verdict.ofBool_ne_abort (holds : Bool) : Verdict.ofBool holds ≠ .abort := by
  cases holds <;> simp [Verdict.ofBool]

theorem Formula.evaluateValues_eq (ctx : Context) (stack : Stack) (formula : Formula) :
    Formula.evaluateValues ctx stack formula = Quantifier.evaluate (Group.evaluateValues ctx stack) .any formula := by
  induction formula <;> simp only [Formula.evaluateValues, Quantifier.evaluate, *]

theorem Group.evaluateValues_eq (ctx : Context) (stack : Stack) (group : Group) :
    Group.evaluateValues ctx stack group = Quantifier.evaluate (Rule.evaluateValues ctx stack) .all group := by
  induction group <;> simp only [Group.evaluateValues, Quantifier.evaluate, *]

/-! ## Quantifiers -/

theorem Quantifier.evaluate_all_pass {Item : Type} {evaluate : Item → Verdict} :
    ∀ {items : List Item}, Quantifier.evaluate evaluate .all items = .pass → ∀ item ∈ items, evaluate item = .pass
  | [], _ => by simp
  | item :: items, passes => by
    simp only [Quantifier.evaluate] at passes
    split at passes
    · rename_i itemPasses
      simpa [itemPasses] using evaluate_all_pass passes
    · rename_i notPass
      exact absurd passes notPass

/-- An `ANY` pass has a passing item. Not a converse: an abort before the first passing item hides it. -/
theorem Quantifier.evaluate_any_pass {Item : Type} {evaluate : Item → Verdict} :
    ∀ {items : List Item}, Quantifier.evaluate evaluate .any items = .pass → ∃ item ∈ items, evaluate item = .pass
  | [], passes => by simp [Quantifier.evaluate] at passes
  | item :: items, passes => by
    simp only [Quantifier.evaluate] at passes
    split at passes
    · obtain ⟨other, isMember, otherPasses⟩ := evaluate_any_pass passes
      exact ⟨other, List.mem_cons_of_mem item isMember, otherPasses⟩
    · exact ⟨item, List.mem_cons_self, passes⟩

/-- An `ALL` failure has a failing item. -/
theorem Quantifier.evaluate_all_fail {Item : Type} {evaluate : Item → Verdict} :
    ∀ {items : List Item}, Quantifier.evaluate evaluate .all items = .fail → ∃ item ∈ items, evaluate item = .fail
  | [], fails => by simp [Quantifier.evaluate] at fails
  | item :: items, fails => by
    simp only [Quantifier.evaluate] at fails
    split at fails
    · obtain ⟨other, isMember, otherFails⟩ := evaluate_all_fail fails
      exact ⟨other, List.mem_cons_of_mem item isMember, otherFails⟩
    · exact ⟨item, List.mem_cons_self, fails⟩

theorem Quantifier.evaluate_any_fail {Item : Type} {evaluate : Item → Verdict} :
    ∀ {items : List Item}, Quantifier.evaluate evaluate .any items = .fail → ∀ item ∈ items, evaluate item = .fail
  | [], _ => by simp
  | item :: items, fails => by
    simp only [Quantifier.evaluate] at fails
    split at fails
    · rename_i itemFails
      simpa [itemFails] using evaluate_any_fail fails
    · rename_i notFail
      exact absurd fails notFail

theorem Quantifier.evaluate_ne_abort {Item : Type} {evaluate : Item → Verdict} (quantifier : Quantifier) :
    ∀ {items : List Item}, (∀ item ∈ items, evaluate item ≠ .abort) → quantifier.evaluate evaluate items ≠ .abort
  | [], _ => by cases quantifier <;> simp [Quantifier.evaluate]
  | item :: items, noAbort => by
    have rest := evaluate_ne_abort quantifier fun other isMember => noAbort other (List.mem_cons_of_mem item isMember)
    have first := noAbort item List.mem_cons_self
    cases quantifier <;> simp only [Quantifier.evaluate] <;> split <;> simp_all

/-! ## Theorem 15: a pass means the policy holds -/

theorem Group.evaluateValues_sound (group : Group)
    (sound : ∀ rule ∈ group, ∀ ctx stack, rule.evaluateValues ctx stack = .pass → rule.holds ctx stack = true)
    (ctx : Context) (stack : Stack) :
    Group.evaluateValues ctx stack group = .pass → Group.holds ctx stack group = true := by
  rw [Group.evaluateValues_eq, Group.holds_eq, List.all_eq_true]
  exact fun passes rule isMember =>
    sound rule isMember ctx stack (Quantifier.evaluate_all_pass passes rule isMember)

theorem Rule.evaluateValues_sound (rule : Rule) :
    ∀ ctx stack, rule.evaluateValues ctx stack = .pass → rule.holds ctx stack = true := by
  induction rule with
  | test path operator => intro ctx stack; simp [Rule.evaluateValues, Rule.holds]
  | contextTest property operator => intro ctx stack; simp [Rule.evaluateValues, Rule.holds]
  | loop quantifier arrayPath body bodySound =>
    intro ctx stack passes
    simp only [Rule.evaluateValues, Rule.holds] at passes ⊢
    rcases found : stack.at arrayPath with _ | (_ | _ | elements) <;> simp only [found] at passes ⊢ <;>
      try contradiction
    split at passes
    · contradiction
    · cases quantifier
      · simp only [List.all_eq_true]
        exact fun element isMember => Group.evaluateValues_sound body bodySound ctx _
          (Quantifier.evaluate_all_pass passes element isMember)
      · simp only [List.any_eq_true]
        obtain ⟨element, isMember, elementPasses⟩ := Quantifier.evaluate_any_pass passes
        exact ⟨element, isMember, Group.evaluateValues_sound body bodySound ctx _ elementPasses⟩

/-- Theorem 15. No limits needed: past a limit the evaluator aborts, never passes. -/
theorem evaluateValues_sound (formula : Formula) (ctx : Context) (stack : Stack) :
    formula.evaluateValues ctx stack = .pass → formula.holds ctx stack = true := by
  rw [Formula.evaluateValues_eq, Formula.holds_eq, List.any_eq_true]
  intro passes
  obtain ⟨group, isMember, groupPasses⟩ := Quantifier.evaluate_any_pass passes
  exact ⟨group, isMember, Group.evaluateValues_sound group (fun rule _ => rule.evaluateValues_sound) ctx stack
    groupPasses⟩

/-! ## Theorem 34: a verdict other than abort is the denotation's -/

theorem Group.evaluateValues_fail (group : Group)
    (fails : ∀ rule ∈ group, ∀ ctx stack, rule.evaluateValues ctx stack = .fail → rule.holds ctx stack = false)
    (ctx : Context) (stack : Stack) :
    Group.evaluateValues ctx stack group = .fail → Group.holds ctx stack group = false := by
  rw [Group.evaluateValues_eq, Group.holds_eq, List.all_eq_false]
  intro groupFails
  obtain ⟨rule, isMember, ruleFails⟩ := Quantifier.evaluate_all_fail groupFails
  exact ⟨rule, isMember, by simp [fails rule isMember ctx stack ruleFails]⟩

theorem Rule.evaluateValues_fail (rule : Rule) :
    ∀ ctx stack, rule.evaluateValues ctx stack = .fail → rule.holds ctx stack = false := by
  induction rule with
  | test path operator => intro ctx stack; simp [Rule.evaluateValues, Rule.holds]
  | contextTest property operator => intro ctx stack; simp [Rule.evaluateValues, Rule.holds]
  | loop quantifier arrayPath body bodyFails =>
    intro ctx stack fails
    simp only [Rule.evaluateValues, Rule.holds] at fails ⊢
    rcases found : stack.at arrayPath with _ | (_ | _ | elements) <;> simp only [found] at fails ⊢
    split at fails
    · contradiction
    · cases quantifier
      · simp only [List.all_eq_false]
        obtain ⟨element, isMember, elementFails⟩ := Quantifier.evaluate_all_fail fails
        exact ⟨element, isMember, by
          simp only [Group.evaluateValues_fail body bodyFails ctx _ elementFails, Bool.false_eq_true,
            not_false_eq_true]⟩
      · simp only [List.any_eq_false]
        exact fun element isMember => by
          simp only [Group.evaluateValues_fail body bodyFails ctx _
            (Quantifier.evaluate_any_fail fails element isMember), Bool.false_eq_true, not_false_eq_true]

/-- Theorem 34. No limits needed: whenever evaluation does not abort, it decides the policy. -/
theorem evaluateValues_exact (formula : Formula) (ctx : Context) (stack : Stack) :
    formula.evaluateValues ctx stack ≠ .abort →
      formula.evaluateValues ctx stack = .ofBool (formula.holds ctx stack) := by
  intro noAbort
  rcases verdict : formula.evaluateValues ctx stack
  · rw [evaluateValues_sound formula ctx stack verdict]
    rfl
  · rw [Formula.evaluateValues_eq] at verdict
    have holds : formula.holds ctx stack = false := by
      rw [Formula.holds_eq, List.any_eq_false]
      exact fun group isMember => by
        simp only [Group.evaluateValues_fail group (fun rule _ => rule.evaluateValues_fail) ctx stack
          (Quantifier.evaluate_any_fail verdict group isMember), Bool.false_eq_true, not_false_eq_true]
    rw [holds]
    rfl
  · exact absurd verdict noAbort

/-! ## Theorems 16 and 21: within limits -/

theorem Group.evaluateValues_ne_abort (group : Group)
    (noAbort : ∀ rule ∈ group, ∀ ctx stack, rule.withinLimits stack = true → rule.evaluateValues ctx stack ≠ .abort)
    (ctx : Context) (stack : Stack) :
    Group.withinLimits stack group = true → Group.evaluateValues ctx stack group ≠ .abort := by
  rw [Group.withinLimits_eq, List.all_eq_true, Group.evaluateValues_eq]
  exact fun within => Quantifier.evaluate_ne_abort .all fun rule isMember =>
    noAbort rule isMember ctx stack (within rule isMember)

theorem Rule.evaluateValues_ne_abort (rule : Rule) :
    ∀ ctx stack, rule.withinLimits stack = true → rule.evaluateValues ctx stack ≠ .abort := by
  induction rule with
  | test path operator => intro ctx stack _; simp [Rule.evaluateValues]
  | contextTest property operator => intro ctx stack _; simp [Rule.evaluateValues]
  | loop quantifier arrayPath body bodyNoAbort =>
    intro ctx stack within
    simp only [Rule.withinLimits, Rule.evaluateValues] at within ⊢
    rcases found : stack.at arrayPath with _ | (_ | _ | elements) <;> simp only [found] at within ⊢ <;>
      try (intro abort; contradiction)
    simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at within
    obtain ⟨short, elementsWithin⟩ := within
    rw [ite_eq_right (Nat.not_lt.mpr short)]
    exact Quantifier.evaluate_ne_abort quantifier fun element isMember =>
      Group.evaluateValues_ne_abort body bodyNoAbort ctx _ (elementsWithin element isMember)

/-- Theorem 16. -/
theorem evaluateValues_no_abort (formula : Formula) (ctx : Context) (stack : Stack) :
    formula.withinLimits stack = true → formula.evaluateValues ctx stack ≠ .abort := by
  rw [Formula.withinLimits_eq, List.all_eq_true, Formula.evaluateValues_eq]
  exact fun within => Quantifier.evaluate_ne_abort .any fun group isMember =>
    Group.evaluateValues_ne_abort group (fun rule _ => rule.evaluateValues_ne_abort) ctx stack (within group isMember)

/-- Theorem 21. -/
theorem evaluateValues_complete (formula : Formula) (ctx : Context) (stack : Stack) :
    formula.withinLimits stack = true → formula.holds ctx stack = true → formula.evaluateValues ctx stack = .pass := by
  intro within holds
  rw [evaluateValues_exact formula ctx stack (evaluateValues_no_abort formula ctx stack within), holds]
  rfl

end Callcium
