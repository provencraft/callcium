import Callcium.Formula

/-!
# Value-level evaluation

`evaluateValues` runs the enforcement algorithm over decoded values: groups and rules in list order, short-circuits,
and loops in index order. Its only abort is a loop over more than `MAX_QUANTIFIED_ARRAY_LENGTH` elements, checked
before the loop reads an element. A path that leaves its value fails the test, as the denotation reads it.
-/

namespace Callcium

/-- The outcome of an evaluation. -/
inductive Verdict where
  | pass
  | fail
  /-- Evaluation stopped without a verdict. -/
  | abort
  deriving Repr, DecidableEq

/-- Evaluates `items` in order. `ALL` returns the first verdict other than pass, and pass when there is none. `ANY`
returns the first verdict other than fail, and fail when there is none. -/
def Quantifier.evaluate {Item : Type} (evaluate : Item → Verdict) : Quantifier → List Item → Verdict
  | .all, [] => .pass
  | .any, [] => .fail
  | .all, item :: items =>
    match evaluate item with
    | .pass => Quantifier.evaluate evaluate .all items
    | verdict => verdict
  | .any, item :: items =>
    match evaluate item with
    | .fail => Quantifier.evaluate evaluate .any items
    | verdict => verdict

/-- The verdict of a test's result. -/
def Verdict.ofBool : Bool → Verdict
  | true => .pass
  | false => .fail

mutual
  /-- The verdict of `rule` with `stack` as the starting points. A loop over a value that is not an array fails. -/
  def Rule.evaluateValues (ctx : Context) (stack : Stack) : Rule → Verdict
    | .test path operator => .ofBool (operator.holds ctx (stack.at path))
    | .contextTest property operator => .ofBool (operator.holds ctx ((ctx property).map (.word · false)))
    | .loop quantifier arrayPath body =>
      match stack.at arrayPath with
      | some (.list elements) =>
        if MAX_QUANTIFIED_ARRAY_LENGTH < elements.length then .abort
        else quantifier.evaluate (fun (element, position) =>
          Group.evaluateValues ctx (⟨element, some position⟩ :: stack) body) elements.zipIdx
      | _ => .fail

  /-- The first verdict other than pass, in rule order. Pass when every rule passes. -/
  def Group.evaluateValues (ctx : Context) (stack : Stack) : Group → Verdict
    | [] => .pass
    | rule :: rules =>
      match rule.evaluateValues ctx stack with
      | .pass => Group.evaluateValues ctx stack rules
      | verdict => verdict
end

/-- The first verdict other than fail, in group order. Fail when every group fails. -/
def Formula.evaluateValues (ctx : Context) (stack : Stack) : Formula → Verdict
  | [] => .fail
  | group :: groups =>
    match Group.evaluateValues ctx stack group with
    | .fail => Formula.evaluateValues ctx stack groups
    | verdict => verdict

end Callcium
