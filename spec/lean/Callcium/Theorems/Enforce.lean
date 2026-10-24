import Callcium.Enforce
import Callcium.Theorems.Evaluate
import Callcium.Theorems.Hint
import Callcium.Theorems.ByteOrder
import Callcium.Theorems.Load

/-!
# Enforcement

Theorem 19: whenever the enforcer does not abort on a well-formed formula's blob, its verdict is the value-level
evaluator's on the normal form. The arguments are the values that `decodeSolc` reads. Theorem 35: that verdict is the
denotation's. Theorem 1: a pass means the policy holds. Theorem 8: on canonical calldata within limits the enforcer
never aborts. Theorem 2: there a policy that holds passes. Theorem 5: on every blob storage accepts, the enforcer reads
the policy the format defines and takes at most `workBound` steps.
-/

namespace Callcium

/-! ## Outcomes -/

@[simp] theorem Outcome.verdict_ofBool (holds : Bool) : (Outcome.ofBool holds).verdict = .ofBool holds := by
  cases holds <;> rfl

@[simp] theorem Outcome.verdict_pass : Outcome.pass.verdict = .pass := rfl

@[simp] theorem Outcome.verdict_fail : Outcome.fail.verdict = .fail := rfl

@[simp] theorem Outcome.verdict_abort (reason : Abort) : (Outcome.abort reason).verdict = .abort := rfl

theorem Outcome.verdict_eq_abort {outcome : Outcome} :
    outcome.verdict = .abort ↔ ∃ reason, outcome = .abort reason := by
  cases outcome <;> simp [Outcome.verdict]

theorem Fault.outcome_ne_abort {fault : Fault} (noAbort : fault.outcome.verdict ≠ .abort) :
    fault = .arrayIndexOutOfBounds := by
  cases fault
  · exact absurd rfl noAbort
  · rfl

theorem Quantifier.run_verdict {Item : Type} (run : Item → Trace) (quantifier : Quantifier) :
    ∀ items : List Item,
      (quantifier.run run items).outcome.verdict = quantifier.evaluate (fun item => (run item).outcome.verdict) items
  | [] => by cases quantifier <;> rfl
  | item :: items => by
    have rest := run_verdict run quantifier items
    cases quantifier <;> simp only [Quantifier.run, Quantifier.evaluate] <;>
      rcases first : (run item).outcome with _ | _ | reason <;> simp [rest]

/-- Two evaluations over lists that agree item by item wherever the first does not abort agree wherever the first
evaluation does not abort. -/
theorem Quantifier.evaluate_agree {Item Other : Type} {evaluate : Item → Verdict} {other : Other → Verdict}
    (quantifier : Quantifier) :
    ∀ {items : List Item} {others : List Other}, items.length = others.length →
      (∀ index (inItems : index < items.length) (inOthers : index < others.length),
        evaluate items[index] ≠ .abort → evaluate items[index] = other others[index]) →
      quantifier.evaluate evaluate items ≠ .abort →
        quantifier.evaluate evaluate items = quantifier.evaluate other others
  | [], [], _, _, _ => by cases quantifier <;> rfl
  | [], _ :: _, same, _, _ => by simp at same
  | _ :: _, [], same, _, _ => by simp at same
  | item :: items, first :: others, same, agree, noAbort => by
    have head := agree 0 (by simp) (by simp)
    simp only [List.getElem_cons_zero] at head
    have rest := evaluate_agree quantifier (items := items) (others := others) (by simpa using same)
      (fun index inItems inOthers => agree (index + 1) (by simp; omega) (by simp; omega))
    cases quantifier <;> simp only [Quantifier.evaluate] at noAbort ⊢ <;>
      rcases verdict : evaluate item with _ | _ | _ <;> simp only [verdict] at noAbort head ⊢ <;>
      simp only [ne_eq, not_true_eq_false, not_false_eq_true, forall_const, reduceCtorEq] at head noAbort <;>
      rw [← head] <;> simp_all

theorem mapM_getElem {Item Result : Type} {function : Item → Option Result} :
    ∀ {items : List Item} {results : List Result}, items.mapM function = some results →
      ∀ index (inItems : index < items.length) (inResults : index < results.length),
        function items[index] = some results[index]
  | [], _, _, _, inItems, _ => by simp at inItems
  | item :: items, results, mapped, index, inItems, inResults => by
    obtain ⟨first, rest, mapsFirst, mapsRest, rfl⟩ := mapM_cons_eq_some.mp mapped
    cases index with
    | zero => simpa using mapsFirst
    | succ index => simpa using mapM_getElem mapsRest index (by simpa using inItems) (by simpa using inResults)

/-! ## Wire hints resolve as compiled hints -/

theorem Hint.wire_resolve (hint : Hint) : hint.wire.resolve = hint.resolve := rfl

theorem LoopHint.frame_resolveArray (hint : LoopHint) : hint.frame.resolveArray = hint.resolveArray := rfl

theorem LoopHint.frame_resolveElement (hint : LoopHint) : hint.frame.resolveElement = hint.resolveElement := rfl

/-! ## Comparisons on lengths -/

theorem Comparison.apply_of_length {subject : Value} {length : Nat} (has : subject.length? = some length)
    (comparison : Comparison) (values : List Word) :
    comparison.apply subject values = comparison.applyLength length values := by
  cases subject with
  | word => simp [Value.length?] at has
  | bytes data =>
    simp only [Value.length?, Option.some.injEq] at has
    subst has
    cases comparison <;> rcases values with _ | ⟨first, _ | ⟨second, _ | ⟨third, rest⟩⟩⟩ <;> rfl
  | list items =>
    simp only [Value.length?, Option.some.injEq] at has
    subst has
    cases comparison <;> rcases values with _ | ⟨first, _ | ⟨second, _ | ⟨third, rest⟩⟩⟩ <;> rfl

theorem Operator.holds_of_length {subject : Value} {length : Nat} (has : subject.length? = some length)
    (operator : Operator) (ctx : Context) : operator.holds ctx (some subject) = operator.holdsLength ctx length := by
  unfold Operator.holds Operator.holdsLength
  rcases operator.operand.values ctx with _ | values
  · rfl
  · simp only [Comparison.apply_of_length has]
    cases operator.comparison.applyLength length values <;> rfl

/-! ## Reading a target -/

theorem readBytes_length (data : Bytes) (position count : Nat) : (readBytes data position count).length = count := by
  simp only [readBytes, List.length_append, List.length_take, List.length_drop, List.length_replicate]
  omega

theorem WordType.hasCalldataLength_code (wordType : WordType) : hasCalldataLength wordType.code = false := by
  have known := wordType.ofCode?_code
  simp only [hasCalldataLength, decide_eq_false_iff_not, not_or]
  refine ⟨fun same => ?_, fun same => ?_, fun same => ?_⟩ <;> simp [same] at known

@[simp] theorem hasCalldataLength_bytes : hasCalldataLength TypeCode.BYTES = true := by decide
@[simp] theorem hasCalldataLength_string : hasCalldataLength TypeCode.STRING = true := by decide
@[simp] theorem hasCalldataLength_dynamicArray : hasCalldataLength TypeCode.DYNAMIC_ARRAY = true := by decide
@[simp] theorem hasCalldataLength_staticArray : hasCalldataLength TypeCode.STATIC_ARRAY = false := by decide
@[simp] theorem hasCalldataLength_tuple : hasCalldataLength TypeCode.TUPLE = false := by decide

theorem loadWord_ne_arrayIndex {data : Bytes} {position : Nat} :
    loadWord data position ≠ .error .arrayIndexOutOfBounds := by
  unfold loadWord
  split <;> simp

theorem extent_of_ne_abort {within : Prop} [Decidable within] {outcome : Outcome} {reason : Abort}
    (noAbort : (if within then outcome else .abort reason).verdict ≠ .abort) : within ∧ outcome.verdict ≠ .abort := by
  by_cases holds : within <;> simp_all

/-- Wherever the enforcer reaches a verdict on a compiled hint's target, it is the operator's on the value that
`decodeSolc` reads at that path. -/
theorem Hint.wire_compare (hint : Hint) (operator : Operator) (ctx : Context) (data : Bytes) (target : Nat)
    (noAbort : (hint.wire.compare operator ctx data target).verdict ≠ .abort) :
    (hint.wire.compare operator ctx data target).verdict =
      .ofBool (operator.holds ctx (some (hint.target.decodeSolc data target))) := by
  unfold TestHint.compare at noAbort ⊢
  cases loaded : loadWord data target with
  | error fault =>
    simp only [loaded] at noAbort
    rw [Fault.outcome_ne_abort noAbort] at loaded
    exact absurd loaded loadWord_ne_arrayIndex
  | ok word =>
    obtain ⟨-, rfl⟩ := loadWord_eq_ok.mp loaded
    simp only [loaded] at noAbort ⊢
    rcases hint with ⟨hops, targetDelta, targetType⟩
    cases targetType with
    | word wordType =>
      simp only [Hint.wire, AbiType.code, WordType.hasCalldataLength_code, WordType.ofCode?_code,
        Bool.false_eq_true, ↓reduceIte] at noAbort ⊢
      split at noAbort
      · rename_i canonical
        simp [canonical, AbiType.decodeSolc]
      · exact absurd rfl noAbort
    | bytes | string =>
      simp only [Hint.wire, AbiType.code, hasCalldataLength_bytes, hasCalldataLength_string, TestHint.payloadStride,
        ↓reduceIte] at noAbort ⊢
      obtain ⟨within, -⟩ := extent_of_ne_abort noAbort
      simp only [within, ↓reduceIte, Outcome.verdict_ofBool]
      rw [Operator.holds_of_length (length := (readWord data target).toNat)
        (by simp [AbiType.decodeSolc, Value.length?, readBytes_length])]
    | dynamicArray element =>
      simp only [Hint.wire, AbiType.code, hasCalldataLength_dynamicArray, TestHint.payloadStride, ↓reduceIte]
        at noAbort ⊢
      obtain ⟨within, -⟩ := extent_of_ne_abort noAbort
      simp only [within, ↓reduceIte, Outcome.verdict_ofBool]
      rw [Operator.holds_of_length (length := (readWord data target).toNat)
        (by simp [AbiType.decodeSolc, Value.length?, decodeElements_length])]
    | staticArray element length => simp [Hint.wire, AbiType.code] at noAbort
    | tuple fields => simp [Hint.wire, AbiType.code] at noAbort


/-! ## Theorem 19 over compiled policies -/

theorem ArrayMeta.elementAt_lt {array : ArrayMeta} {data : Bytes} {elements index next : Nat}
    (resolved : array.elementAt data elements index = .ok next) : next < 2 ^ 256 := by
  unfold ArrayMeta.elementAt at resolved
  split at resolved
  · exact follow_lt resolved
  · simp only [pure, Except.pure, Except.ok.injEq] at resolved
    rw [← resolved]
    exact advance_lt _ _

theorem Policy.argumentsStart_lt (selector : Option UInt32) : Policy.argumentsStart selector < 2 ^ 256 := by
  unfold Policy.argumentsStart Policy.SELECTOR_SIZE
  split <;> omega

/-- A compiled test the enforcer reaches a verdict on decides as its rule does. It decides over the value that
`decodeSolc` reads from the starting point of the walk. -/
theorem Rule.compileTest_refines {root : AbiType} {rule : Rule} {test : CompiledTest}
    (compiled : rule.compileTest root = some test) {data : Bytes} {start : Nat} (inRange : start < 2 ^ 256)
    (ctx : Context) (position : Option Nat) (outer : Stack)
    (noAbort : (test.outcome data ctx start).verdict ≠ .abort) :
    (test.outcome data ctx start).verdict =
      rule.evaluateValues ctx (⟨root.decodeSolc data start, position⟩ :: outer) := by
  cases rule with
  | contextTest property operator =>
    simp only [Rule.compileTest] at compiled
    split at compiled
    · cases compiled
      simp [CompiledTest.outcome, Rule.evaluateValues]
    · contradiction
  | test path operator =>
    simp only [Rule.compileTest, Option.bind_eq_some_iff] at compiled
    obtain ⟨hint, compiledPath, compiled⟩ := compiled
    split at compiled
    · cases compiled
      simp only [CompiledTest.outcome, Hint.wire_resolve] at noAbort ⊢
      simp only [Rule.evaluateValues, Stack.at, List.head?_cons, Option.bind_some]
      cases resolved : hint.resolve data start with
      | error fault =>
        simp only [resolved] at noAbort ⊢
        rw [Fault.outcome_ne_abort noAbort] at resolved ⊢
        rw [AbiType.decodeSolc_at_compile?_fault compiledPath inRange resolved]
        rfl
      | ok target =>
        simp only [resolved] at noAbort ⊢
        rw [Hint.wire_compare hint operator ctx data target noAbort,
          AbiType.decodeSolc_at_compile? compiledPath inRange resolved]
    · contradiction
  | loop => simp [Rule.compileTest] at compiled

/-- A compiled rule the enforcer reaches a verdict on decides as its rule does over the value `decodeSolc` reads from
the starting point. For a loop, the elements are those `decodeSolc` reads, and the body decides from each. -/
theorem Rule.compile_refines {root : AbiType} {rule : Rule} {compiled : CompiledRule}
    (compiledEq : rule.compile root = some compiled) {data : Bytes} {start : Nat} (inRange : start < 2 ^ 256)
    (ctx : Context) (position : Option Nat) (outer : Stack)
    (noAbort : (compiled.run data ctx start).outcome.verdict ≠ .abort) :
    (compiled.run data ctx start).outcome.verdict =
      rule.evaluateValues ctx (⟨root.decodeSolc data start, position⟩ :: outer) := by
  cases rule with
  | loop quantifier arrayPath body =>
    simp only [Rule.compile, Option.bind_eq_some_iff, Option.map_eq_some_iff] at compiledEq
    obtain ⟨loop, compiledLoop, tests, testsCompiled, rfl⟩ := compiledEq
    simp only [CompiledRule.run, LoopHint.frame_resolveArray] at noAbort ⊢
    simp only [Rule.evaluateValues, Stack.at, List.head?_cons, Option.bind_some]
    cases resolved : loop.resolveArray data start with
    | error fault =>
      simp only [resolved] at noAbort ⊢
      rw [Fault.outcome_ne_abort noAbort] at resolved ⊢
      rw [AbiType.decodeSolc_at_compileLoop?_fault compiledLoop inRange resolved]
      rfl
    | ok array =>
      obtain ⟨elements, count⟩ := array
      obtain ⟨items, located, counted, elementsAt⟩ :=
        AbiType.decodeSolc_at_compileLoop? compiledLoop inRange resolved
      subst counted
      simp only [resolved, located] at noAbort ⊢
      by_cases over : MAX_QUANTIFIED_ARRAY_LENGTH < items.length
      · simp [over] at noAbort
      simp only [over, ↓reduceIte, Quantifier.run_verdict] at noAbort ⊢
      refine Quantifier.evaluate_agree quantifier (by simp) ?_ noAbort
      intro index inRange' inItems elementNoAbort
      simp only [List.getElem_range, List.getElem_zipIdx, Nat.zero_add] at elementNoAbort ⊢
      cases elementResolved : loop.frame.resolveElement data elements index with
      | error fault =>
        simp only [elementResolved, Outcome.verdict] at elementNoAbort
        rw [Fault.outcome_ne_abort elementNoAbort] at elementResolved
        exact absurd elementResolved elementAt_ne_arrayIndex
      | ok elementStart =>
        simp only [elementResolved, Quantifier.run_verdict] at elementNoAbort ⊢
        have itemAt := elementsAt (by simpa using inRange') elementResolved
        rw [List.getElem?_eq_getElem (by simpa using inRange'), Option.some.injEq] at itemAt
        rw [itemAt, Group.evaluateValues_eq]
        refine Quantifier.evaluate_agree .all (mapM_length testsCompiled) ?_ elementNoAbort
        intro testIndex inTests inBody testNoAbort
        exact Rule.compileTest_refines (mapM_getElem testsCompiled testIndex inBody inTests)
          (ArrayMeta.elementAt_lt elementResolved) ctx _ _ testNoAbort
  | test path operator =>
    simp only [Rule.compile, Option.map_eq_some_iff] at compiledEq
    obtain ⟨test, compiledTest, rfl⟩ := compiledEq
    exact Rule.compileTest_refines compiledTest inRange ctx position outer noAbort
  | contextTest property operator =>
    simp only [Rule.compile, Option.map_eq_some_iff] at compiledEq
    obtain ⟨test, compiledTest, rfl⟩ := compiledEq
    exact Rule.compileTest_refines compiledTest inRange ctx position outer noAbort

/-- Theorem 19 over compiled policies: whenever the enforcer does not abort on a compiled formula, its verdict is the
value-level evaluator's. The arguments are those `decodeSolc` reads. -/
theorem CompiledPolicy.compile_refines {signature : Signature} {formula : Formula} {policy : CompiledPolicy}
    (compiled : CompiledPolicy.compile signature formula = some policy) (data : Bytes) (ctx : Context)
    (noAbort : (policy.run data ctx).outcome.verdict ≠ .abort) :
    (policy.run data ctx).outcome.verdict = formula.evaluateValues ctx [⟨signature.decodeSolc data, none⟩] := by
  simp only [CompiledPolicy.compile, Option.map_eq_some_iff] at compiled
  obtain ⟨groups, groupsCompiled, rfl⟩ := compiled
  simp only [CompiledPolicy.run, CompiledPolicy.runGroups] at noAbort ⊢
  have inRange := Policy.argumentsStart_lt signature.selector
  have decoded : signature.decodeSolc data =
      (AbiType.tuple signature.params).decodeSolc data (Policy.argumentsStart signature.selector) := rfl
  rw [decoded]
  generalize Policy.argumentsStart signature.selector = start at noAbort inRange ⊢
  have groupsAgree : (Quantifier.run (Quantifier.run (CompiledRule.run data ctx start) .all) .any
        groups).outcome.verdict ≠ .abort →
      (Quantifier.run (Quantifier.run (CompiledRule.run data ctx start) .all) .any groups).outcome.verdict =
        formula.evaluateValues ctx [⟨(AbiType.tuple signature.params).decodeSolc data start, none⟩] := by
    intro groupsNoAbort
    simp only [Quantifier.run_verdict] at groupsNoAbort ⊢
    rw [Formula.evaluateValues_eq]
    refine Quantifier.evaluate_agree .any (mapM_length groupsCompiled) ?_ groupsNoAbort
    intro groupIndex inGroups inFormula groupNoAbort
    rw [Group.evaluateValues_eq]
    have rulesCompiled := mapM_getElem groupsCompiled groupIndex inFormula inGroups
    refine Quantifier.evaluate_agree .all (mapM_length rulesCompiled) ?_ groupNoAbort
    intro ruleIndex inRules inGroup ruleNoAbort
    exact Rule.compile_refines (mapM_getElem rulesCompiled ruleIndex inGroup inRules) inRange ctx none [] ruleNoAbort
  cases selectorIs : signature.selector with
  | none =>
    simp only [selectorIs] at noAbort ⊢
    exact groupsAgree noAbort
  | some selector =>
    simp only [selectorIs] at noAbort ⊢
    by_cases short : data.length < Policy.SELECTOR_SIZE
    · simp [short] at noAbort
    by_cases same : beNat (data.take Policy.SELECTOR_SIZE) = selector.toNat
    · simp only [short, same, ↓reduceIte] at noAbort ⊢
      exact groupsAgree noAbort
    · simp [short, same] at noAbort

/-! ## Theorem 8 over compiled policies -/

/-- A compiled hint's target on canonical calldata never aborts: its word loads and is canonical, or its declared
length's payload lies within the calldata. -/
theorem Hint.wire_compare_ne_abort {hint : Hint} {operator : Operator}
    (compares : operator.compares hint.target.code = true) (ctx : Context) {data : Bytes} {target : Nat} {value : Value}
    (canonical : hint.target.decodeStrict data target = some value) :
    (hint.wire.compare operator ctx data target).verdict ≠ .abort := by
  have decoded := AbiType.decodeSolc_of_strict canonical
  obtain ⟨admitted, -, placed⟩ := (hint.target.decodeStrict_eq_some_iff data target value).mp canonical
  have inside := placed_end placed
  rcases hint with ⟨hops, targetDelta, targetType⟩
  simp only at compares admitted decoded inside ⊢
  unfold TestHint.compare
  cases targetType with
  | word wordType =>
    cases value with
    | word bits signed =>
      simp only [AbiType.decodeSolc, Value.word.injEq] at decoded
      obtain ⟨rfl, rfl⟩ := decoded
      simp only [AbiType.admits, Bool.and_eq_true] at admitted
      simp only [AbiType.encode, beBytes_length] at inside
      rw [loadWord_eq_ok.mpr ⟨inside, rfl⟩]
      simp [Hint.wire, AbiType.code, WordType.hasCalldataLength_code, WordType.ofCode?_code, admitted.1]
    | bytes | list => simp [AbiType.admits] at admitted
  | bytes | string =>
    cases value with
    | bytes content =>
      simp only [AbiType.decodeSolc, Value.bytes.injEq] at decoded
      have counted := congrArg List.length decoded
      rw [readBytes_length] at counted
      simp only [AbiType.encode, List.length_append, beBytes_length] at inside
      rw [loadWord_eq_ok.mpr ⟨by omega, rfl⟩]
      have within : target + WORD_SIZE + (readWord data target).toNat ≤ data.length := by omega
      simp [Hint.wire, AbiType.code, TestHint.payloadStride, within]
    | word | list => simp [AbiType.admits] at admitted
  | dynamicArray element =>
    cases value with
    | list items =>
      simp only [AbiType.decodeSolc, Value.list.injEq] at decoded
      have counted := congrArg List.length decoded
      rw [decodeElements_length] at counted
      simp only [AbiType.admits, Bool.and_eq_true] at admitted
      have heads := AbiType.map_headLength_encodeComponents (types := List.replicate items.length element)
        (fun abiType _ _ admits => abiType.headLength_encode admits) admitted.2
      simp only [AbiType.encode, joinComponents, List.length_append, beBytes_length,
        headsAndTails_heads_length, heads, List.map_replicate, List.sum_replicate_nat] at inside
      rw [loadWord_eq_ok.mpr ⟨by omega, rfl⟩]
      have within : target + WORD_SIZE + (readWord data target).toNat * element.headSize ≤ data.length := by
        rw [counted]
        omega
      simp [Hint.wire, AbiType.code, TestHint.payloadStride, WORD_SIZE_mul_strideWords, within]
    | word | bytes => simp [AbiType.admits] at admitted
  | staticArray element length => simp [Operator.compares, operandType, AbiType.code] at compares
  | tuple fields => simp [Operator.compares, operandType, AbiType.code] at compares

theorem Rule.compileTest_ne_abort {root : AbiType} {rule : Rule} {test : CompiledTest}
    (compiled : rule.compileTest root = some test) {data : Bytes} {start : Nat} {value : Value}
    (canonical : root.decodeStrict data start = some value) (ctx : Context) :
    (test.outcome data ctx start).verdict ≠ .abort := by
  cases rule with
  | contextTest property operator =>
    simp only [Rule.compileTest] at compiled
    split at compiled
    · cases compiled
      simp [CompiledTest.outcome]
    · contradiction
  | test path operator =>
    simp only [Rule.compileTest, Option.bind_eq_some_iff] at compiled
    obtain ⟨hint, compiledPath, compiled⟩ := compiled
    split at compiled
    · rename_i compares
      cases compiled
      simp only [CompiledTest.outcome, Hint.wire_resolve]
      cases present : value.at path with
      | none =>
        rw [AbiType.resolve_compile?_absent canonical present compiledPath]
        simp [Fault.outcome]
      | some targetValue =>
        obtain ⟨offset, resolved, targetCanonical⟩ := AbiType.resolve_compile?_ok canonical present compiledPath
        rw [resolved]
        exact Hint.wire_compare_ne_abort compares ctx targetCanonical
    · contradiction
  | loop => simp [Rule.compileTest] at compiled

/-- On canonical calldata, the value at a loop's array path, where there is one, is an array. -/
theorem AbiType.list_of_compileLoop? {abiType : AbiType} {data : Bytes} {start : Nat} {value : Value}
    (canonical : abiType.decodeStrict data start = some value) {arrayPath : Path} {loop : LoopHint}
    (compiled : abiType.compileLoop? arrayPath = some loop) {found : Value}
    (present : value.at arrayPath = some found) :
    ∃ items, found = .list items := by
  obtain ⟨admitted, fits, placed⟩ := (abiType.decodeStrict_eq_some_iff data start value).mp canonical
  have inside := placed_end placed
  cases walked : abiType.walk arrayPath 0 true with
  | none => simp [AbiType.compileLoop?, walked] at compiled
  | some walk =>
    obtain ⟨hops, delta, entered, arrayType⟩ := walk
    have walkedCanonical :=
      AbiType.resolveHops_walk (base := start) (position := start) fits walked (by omega) admitted placed (by simp)
    rw [present] at walkedCanonical
    obtain ⟨-, -, -, -, foundAdmits, -⟩ := walkedCanonical
    cases arrayType with
    | staticArray | dynamicArray =>
      cases found <;> first | exact ⟨_, rfl⟩ | simp [AbiType.admits] at foundAdmits
    | word | bytes | string | tuple => simp [AbiType.compileLoop?, walked] at compiled

theorem Rule.compile_ne_abort {root : AbiType} {rule : Rule} {compiled : CompiledRule}
    (compiledEq : rule.compile root = some compiled) {data : Bytes} {start : Nat} {value : Value}
    (canonical : root.decodeStrict data start = some value) {position : Option Nat} {outer : Stack}
    (within : rule.withinLimits (⟨value, position⟩ :: outer) = true) (ctx : Context) :
    (compiled.run data ctx start).outcome.verdict ≠ .abort := by
  cases rule with
  | loop quantifier arrayPath body =>
    simp only [Rule.compile, Option.bind_eq_some_iff, Option.map_eq_some_iff] at compiledEq
    obtain ⟨loop, compiledLoop, tests, testsCompiled, rfl⟩ := compiledEq
    simp only [CompiledRule.run, LoopHint.frame_resolveArray]
    cases present : value.at arrayPath with
    | none =>
      rw [AbiType.resolveArray_compileLoop?_absent canonical present compiledLoop]
      simp [Fault.outcome]
    | some found =>
      obtain ⟨items, rfl⟩ := AbiType.list_of_compileLoop? canonical compiledLoop present
      obtain ⟨elements, resolved, elementsCanonical⟩ :=
        AbiType.resolveArray_compileLoop?_ok canonical present compiledLoop
      simp only [Rule.withinLimits, Stack.at, List.head?_cons, Option.bind_some, present, Bool.and_eq_true,
        decide_eq_true_eq] at within
      simp only [resolved, Nat.not_lt.mpr within.1, ↓reduceIte, Quantifier.run_verdict]
      refine Quantifier.evaluate_ne_abort quantifier fun index isMember => ?_
      have inItems : index < items.length := List.mem_range.mp isMember
      obtain ⟨elementStart, elementResolved, elementCanonical⟩ :=
        elementsCanonical (List.getElem?_eq_getElem inItems)
      simp only [LoopHint.frame_resolveElement, elementResolved, Quantifier.run_verdict]
      refine Quantifier.evaluate_ne_abort .all fun test isTest => ?_
      obtain ⟨bodyRule, -, compiledTest⟩ := mapM_mem_results testsCompiled test isTest
      exact Rule.compileTest_ne_abort compiledTest elementCanonical ctx
  | test path operator =>
    simp only [Rule.compile, Option.map_eq_some_iff] at compiledEq
    obtain ⟨test, compiledTest, rfl⟩ := compiledEq
    exact Rule.compileTest_ne_abort compiledTest canonical ctx
  | contextTest property operator =>
    simp only [Rule.compile, Option.map_eq_some_iff] at compiledEq
    obtain ⟨test, compiledTest, rfl⟩ := compiledEq
    exact Rule.compileTest_ne_abort compiledTest canonical ctx

theorem beNat_take_selector {data : Bytes} {selector : UInt32}
    (opens : data.take Policy.SELECTOR_SIZE = beBytes Policy.SELECTOR_SIZE selector.toNat) :
    Policy.SELECTOR_SIZE ≤ data.length ∧ beNat (data.take Policy.SELECTOR_SIZE) = selector.toNat := by
  have taken := congrArg List.length opens
  simp only [List.length_take, beBytes_length] at taken
  refine ⟨by omega, ?_⟩
  rw [opens, beNat_beBytes, Nat.mod_eq_of_lt (by simpa [Policy.SELECTOR_SIZE] using selector.toNat_lt)]

/-- Theorem 8 over compiled policies: on canonical calldata within limits, the enforcer never aborts. -/
theorem CompiledPolicy.compile_ne_abort {signature : Signature} {formula : Formula} {policy : CompiledPolicy}
    (compiled : CompiledPolicy.compile signature formula = some policy) {data : Bytes} {args : Value}
    (canonical : signature.decodeStrict data = some args) (within : formula.withinLimits [⟨args, none⟩] = true)
    (ctx : Context) : (policy.run data ctx).outcome.verdict ≠ .abort := by
  simp only [CompiledPolicy.compile, Option.map_eq_some_iff] at compiled
  obtain ⟨groups, groupsCompiled, rfl⟩ := compiled
  simp only [Signature.decodeStrict] at canonical
  split at canonical
  · rename_i opens
    simp only [Formula.withinLimits_eq, List.all_eq_true] at within
    simp only [CompiledPolicy.run, CompiledPolicy.runGroups]
    generalize Policy.argumentsStart signature.selector = start at canonical ⊢
    have groupsNoAbort : (Quantifier.run (Quantifier.run (CompiledRule.run data ctx start) .all) .any
        groups).outcome.verdict ≠ .abort := by
      simp only [Quantifier.run_verdict]
      refine Quantifier.evaluate_ne_abort .any fun rules isRules => ?_
      obtain ⟨group, isGroup, rulesCompiled⟩ := mapM_mem_results groupsCompiled rules isRules
      have groupWithin := within group isGroup
      simp only [Group.withinLimits_eq, List.all_eq_true] at groupWithin
      refine Quantifier.evaluate_ne_abort .all fun compiledRule isRule => ?_
      obtain ⟨rule, isRule, ruleCompiled⟩ := mapM_mem_results rulesCompiled compiledRule isRule
      exact Rule.compile_ne_abort ruleCompiled canonical (groupWithin rule isRule) ctx
    cases selectorIs : signature.selector with
    | none => exact groupsNoAbort
    | some selector =>
      simp only [selectorIs, Option.all_some] at opens
      obtain ⟨long, same⟩ := beNat_take_selector (of_decide_eq_true opens)
      simp only [Nat.not_lt.mpr long, same, ↓reduceIte]
      exact groupsNoAbort
  · contradiction

/-! ## Theorems 19, 35, 1, 8 and 2 -/

theorem Signature.decodeSolc_of_strict {signature : Signature} {data : Bytes} {args : Value}
    (canonical : signature.decodeStrict data = some args) : signature.decodeSolc data = args := by
  simp only [Signature.decodeStrict] at canonical
  split at canonical
  · exact AbiType.decodeSolc_of_strict canonical
  · contradiction

namespace Policy

theorem supports_header (selectorless : Bool) : supports (header selectorless) = true := by
  cases selectorless <;> decide

/-- On a well-formed formula's blob, the enforcer runs the formula's compiled normal form. -/
theorem run_encode {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula)
    (data : Bytes) (ctx : Context) :
    ∃ policy, CompiledPolicy.compile signature (normalize formula) = some policy ∧
      run (encode signature formula) data ctx = policy.run data ctx := by
  obtain ⟨policy, compiled, -⟩ := compiled_of_wellFormed wellFormed
  have loaded := load_of_parse ((parse_encode wellFormed).trans compiled)
  have headed : (encode signature formula).head? = some (header policy.selector.isNone) := by
    simp [encode, compiled, CompiledPolicy.write]
  refine ⟨policy, compiled, ?_⟩
  simp [run, headed, loaded, Option.filter, supports_header]

/-- Theorem 19: whenever the enforcer does not abort on a well-formed formula's blob, its verdict is the value-level
evaluator's on the normal form. The arguments are those Solidity's decoder reads. -/
theorem enforce_refines {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula)
    {data : Bytes} {ctx : Context} (noAbort : enforce (encode signature formula) data ctx ≠ .abort) :
    enforce (encode signature formula) data ctx =
      (normalize formula).evaluateValues ctx [⟨signature.decodeSolc data, none⟩] := by
  obtain ⟨policy, compiled, runs⟩ := run_encode wellFormed data ctx
  simp only [enforce, outcome, runs] at noAbort ⊢
  exact CompiledPolicy.compile_refines compiled data ctx noAbort

/-- Theorem 35: whenever the enforcer does not abort on a well-formed formula's blob, its verdict is the
denotation's. No limits needed. -/
theorem enforce_exact {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula)
    {data : Bytes} {ctx : Context} (noAbort : enforce (encode signature formula) data ctx ≠ .abort) :
    enforce (encode signature formula) data ctx = .ofBool (formula.holds ctx [⟨signature.decodeSolc data, none⟩]) := by
  have refines := enforce_refines wellFormed noAbort
  rw [refines] at noAbort ⊢
  rw [evaluateValues_exact _ _ _ noAbort, normalize_holds]

/-- Theorem 1: a pass means the policy holds over the arguments Solidity's decoder reads. Therefore, no crafted calldata
can make the policy pass. -/
theorem enforce_sound {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula)
    {data : Bytes} {ctx : Context} (passes : enforce (encode signature formula) data ctx = .pass) :
    formula.holds ctx [⟨signature.decodeSolc data, none⟩] = true := by
  have exact := enforce_exact wellFormed (ctx := ctx) (data := data) (by rw [passes]; decide)
  rw [passes] at exact
  exact (Verdict.ofBool_eq_pass _).mp exact.symm

/-- Theorem 8: on canonical calldata within limits, the enforcer never aborts. -/
theorem enforce_no_abort {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula)
    {data : Bytes} {args : Value} (canonical : signature.decodeStrict data = some args)
    (within : formula.withinLimits [⟨args, none⟩] = true) (ctx : Context) :
    enforce (encode signature formula) data ctx ≠ .abort := by
  obtain ⟨policy, compiled, runs⟩ := run_encode wellFormed data ctx
  simp only [enforce, outcome, runs]
  exact CompiledPolicy.compile_ne_abort compiled canonical (by rw [normalize_withinLimits]; exact within) ctx

/-- Theorem 2: on canonical calldata within limits, a policy that holds passes. -/
theorem enforce_complete {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula)
    {data : Bytes} {args : Value} (canonical : signature.decodeStrict data = some args) {ctx : Context}
    (holds : formula.holds ctx [⟨args, none⟩] = true) (within : formula.withinLimits [⟨args, none⟩] = true) :
    enforce (encode signature formula) data ctx = .pass := by
  rw [enforce_exact wellFormed (enforce_no_abort wellFormed canonical within ctx),
    Signature.decodeSolc_of_strict canonical, holds]
  rfl

end Policy

/-! ## Theorem 5 -/

/-! ### Reads past the end of the calldata -/

theorem readWord_append {data : Bytes} (extra : Bytes) {position : Nat} (within : position + WORD_SIZE ≤ data.length) :
    readWord (data ++ extra) position = readWord data position := by
  unfold readWord readBytes
  rw [List.drop_append_of_le_length (by omega), List.take_append_of_le_length (by simp; omega)]
  simp only [List.length_append]
  rw [show WORD_SIZE - (data.length + extra.length - position) = 0 by omega,
    show WORD_SIZE - (data.length - position) = 0 by omega]

theorem loadWord_append {data : Bytes} (extra : Bytes) {position : Nat} {word : Word}
    (loaded : loadWord data position = .ok word) : loadWord (data ++ extra) position = .ok word := by
  obtain ⟨within, rfl⟩ := loadWord_eq_ok.mp loaded
  exact loadWord_eq_ok.mpr ⟨by simp; omega, (readWord_append extra within).symm⟩

theorem follow_append {data : Bytes} (extra : Bytes) {base head next : Nat}
    (followed : follow data base head = .ok next) : follow (data ++ extra) base head = .ok next := by
  obtain ⟨within, room, rfl⟩ := follow_eq_ok.mp followed
  exact follow_eq_ok.mpr ⟨by simp; omega, by rw [readWord_append extra within]; simp; omega,
    by rw [readWord_append extra within]⟩

theorem ArrayMeta.elementAt_append {array : ArrayMeta} {data : Bytes} (extra : Bytes) {elements index next : Nat}
    (resolved : array.elementAt data elements index = .ok next) :
    array.elementAt (data ++ extra) elements index = .ok next := by
  unfold ArrayMeta.elementAt at resolved ⊢
  split
  · rename_i dynamic
    simp only [dynamic, ↓reduceIte] at resolved
    exact follow_append extra resolved
  · rename_i static
    simpa [static] using resolved

theorem Except.ok_of_kept {Value : Type} {result : Except Fault Value}
    (only : result ≠ .error .arrayIndexOutOfBounds) (kept : result ≠ .error .calldataOutOfBounds) :
    ∃ value, result = .ok value := by
  cases result with
  | ok value => exact ⟨value, rfl⟩
  | error fault => cases fault <;> contradiction

theorem Hop.apply_append {hop : Hop} {data : Bytes} (extra : Bytes) {base : Nat}
    (kept : hop.apply data base ≠ .error .calldataOutOfBounds) :
    hop.apply (data ++ extra) base = hop.apply data base := by
  cases hop with
  | plain delta =>
    simp only [Hop.apply] at kept ⊢
    obtain ⟨next, followed⟩ := Except.ok_of_kept follow_ne_arrayIndex kept
    rw [followed, follow_append extra followed]
  | element index array =>
    simp only [Hop.apply] at kept ⊢
    cases dynamic : array.dynamicArray with
    | false =>
      simp only [dynamic, Bool.false_eq_true, ↓reduceIte] at kept ⊢
      obtain ⟨next, resolved⟩ := Except.ok_of_kept elementAt_ne_arrayIndex kept
      rw [resolved, ArrayMeta.elementAt_append extra resolved]
    | true =>
      simp only [dynamic, ↓reduceIte] at kept ⊢
      cases loaded : loadWord data base with
      | error fault =>
        obtain ⟨⟩ : fault = .calldataOutOfBounds := by cases fault <;> simp_all [loadWord_ne_arrayIndex]
        simp [loaded, bind, Except.bind] at kept
      | ok length =>
        rw [loadWord_append extra loaded]
        simp only [loaded, bind, Except.bind] at kept ⊢
        split
        · rename_i below
          simp only [below, ↓reduceIte] at kept
          obtain ⟨next, resolved⟩ := Except.ok_of_kept elementAt_ne_arrayIndex kept
          rw [resolved, ArrayMeta.elementAt_append extra resolved]
        · rfl

theorem resolveHops_append_kept {data : Bytes} (extra : Bytes) :
    ∀ {hops : List Hop} {start : Nat}, resolveHops data hops start ≠ .error .calldataOutOfBounds →
      resolveHops (data ++ extra) hops start = resolveHops data hops start
  | [], _, _ => rfl
  | hop :: hops, start, kept => by
    simp only [resolveHops, List.foldlM_cons] at kept ⊢
    cases applied : hop.apply data start with
    | error fault =>
      cases fault
      · simp [applied, bind, Except.bind] at kept
      · rw [Hop.apply_append extra (by rw [applied]; simp), applied]
        rfl
    | ok middle =>
      rw [Hop.apply_append extra (by rw [applied]; simp)]
      simp only [applied, bind, Except.bind] at kept ⊢
      exact resolveHops_append_kept extra kept

theorem TestHint.resolve_append {hint : TestHint} {data : Bytes} (extra : Bytes) {start : Nat}
    (kept : hint.resolve data start ≠ .error .calldataOutOfBounds) :
    hint.resolve (data ++ extra) start = hint.resolve data start := by
  unfold TestHint.resolve at kept ⊢
  rw [resolveHops_append_kept extra (fun same => kept (by rw [same]; rfl))]

theorem FrameHint.resolveArray_append {hint : FrameHint} {data : Bytes} (extra : Bytes) {start : Nat}
    (kept : hint.resolveArray data start ≠ .error .calldataOutOfBounds) :
    hint.resolveArray (data ++ extra) start = hint.resolveArray data start := by
  unfold FrameHint.resolveArray at kept ⊢
  cases chain : resolveHops data hint.hops start with
  | error fault =>
    cases fault
    · simp [chain, bind, Except.bind] at kept
    · rw [resolveHops_append_kept extra (by rw [chain]; simp), chain]
      rfl
  | ok base =>
    rw [resolveHops_append_kept extra (by rw [chain]; simp)]
    simp only [chain, bind, Except.bind] at kept ⊢
    by_cases dynamic : hint.count = 0
    · simp only [dynamic, ↓reduceIte] at kept ⊢
      cases loaded : loadWord data (advance base hint.arrayDelta) with
      | error fault =>
        obtain ⟨⟩ : fault = .calldataOutOfBounds := by cases fault <;> simp_all [loadWord_ne_arrayIndex]
        simp [loaded] at kept
      | ok count => rw [loadWord_append extra loaded]
    · simp only [dynamic, ↓reduceIte]

theorem TestHint.compare_append {hint : TestHint} {operator : Operator} {ctx : Context} {data : Bytes}
    (extra : Bytes) {target : Nat} (noAbort : (hint.compare operator ctx data target).verdict ≠ .abort) :
    hint.compare operator ctx (data ++ extra) target = hint.compare operator ctx data target := by
  unfold TestHint.compare at noAbort ⊢
  cases loaded : loadWord data target with
  | error fault =>
    obtain ⟨⟩ : fault = .calldataOutOfBounds := by cases fault <;> simp_all [loadWord_ne_arrayIndex]
    simp [loaded, Fault.outcome] at noAbort
  | ok word =>
    rw [loadWord_append extra loaded]
    simp only [loaded] at noAbort ⊢
    by_cases lengthy : hasCalldataLength hint.typeCode = true
    · simp only [lengthy, ↓reduceIte] at noAbort ⊢
      obtain ⟨within, -⟩ := extent_of_ne_abort noAbort
      have longer : target + WORD_SIZE + word.toNat * hint.payloadStride ≤ (data ++ extra).length := by
        simp only [List.length_append]
        omega
      simp only [within, longer, ↓reduceIte]
    · simp only [lengthy, Bool.false_eq_true, ↓reduceIte]

theorem CompiledTest.outcome_append {test : CompiledTest} {data : Bytes} (extra : Bytes) {ctx : Context}
    {start : Nat} (noAbort : (test.outcome data ctx start).verdict ≠ .abort) :
    test.outcome (data ++ extra) ctx start = test.outcome data ctx start := by
  cases test with
  | contextTest => rfl
  | test path hint operator =>
    simp only [CompiledTest.outcome] at noAbort ⊢
    cases resolved : hint.resolve data start with
    | error fault =>
      cases fault
      · simp [resolved, Fault.outcome] at noAbort
      · rw [TestHint.resolve_append extra (by rw [resolved]; simp), resolved]
    | ok target =>
      rw [TestHint.resolve_append extra (by rw [resolved]; simp)]
      simp only [resolved] at noAbort ⊢
      exact TestHint.compare_append extra noAbort

theorem Quantifier.run_congr {Item : Type} {run other : Item → Trace} (quantifier : Quantifier) :
    ∀ {items : List Item},
      (∀ item ∈ items, (run item).outcome.verdict ≠ .abort → (other item).outcome = (run item).outcome) →
      (quantifier.run run items).outcome.verdict ≠ .abort →
        (quantifier.run other items).outcome = (quantifier.run run items).outcome
  | [], _, _ => by cases quantifier <;> rfl
  | item :: items, same, noAbort => by
    have rest :=
      run_congr quantifier (items := items) fun inner isMember => same inner (List.mem_cons_of_mem item isMember)
    have head := same item List.mem_cons_self
    cases quantifier <;> simp only [Quantifier.run] at noAbort ⊢ <;>
      rcases first : (run item).outcome with _ | _ | reason <;> simp only [first] at noAbort head ⊢ <;>
      simp_all [Outcome.verdict]

theorem CompiledRule.run_append {rule : CompiledRule} {data : Bytes} (extra : Bytes) {ctx : Context} {start : Nat}
    (noAbort : (rule.run data ctx start).outcome.verdict ≠ .abort) :
    (rule.run (data ++ extra) ctx start).outcome = (rule.run data ctx start).outcome := by
  cases rule with
  | test test => exact CompiledTest.outcome_append extra noAbort
  | loop quantifier arrayPath hint body =>
    simp only [CompiledRule.run] at noAbort ⊢
    cases resolved : hint.resolveArray data start with
    | error fault =>
      cases fault
      · simp [resolved, Fault.outcome] at noAbort
      · rw [FrameHint.resolveArray_append extra (by rw [resolved]; simp), resolved]
    | ok array =>
      obtain ⟨elements, count⟩ := array
      rw [FrameHint.resolveArray_append extra (by rw [resolved]; simp)]
      simp only [resolved] at noAbort ⊢
      by_cases over : MAX_QUANTIFIED_ARRAY_LENGTH < count
      · simp [over] at noAbort
      simp only [over, ↓reduceIte] at noAbort ⊢
      refine Quantifier.run_congr quantifier (fun position _ elementNoAbort => ?_) noAbort
      cases elementResolved : hint.resolveElement data elements position with
      | error fault =>
        simp only [elementResolved] at elementNoAbort
        rw [Fault.outcome_ne_abort elementNoAbort] at elementResolved
        exact absurd elementResolved elementAt_ne_arrayIndex
      | ok element =>
        simp only [elementResolved] at elementNoAbort
        simp only [FrameHint.resolveElement] at elementResolved ⊢
        rw [ArrayMeta.elementAt_append extra elementResolved]
        exact Quantifier.run_congr .all (fun test _ testNoAbort => CompiledTest.outcome_append extra testNoAbort)
          elementNoAbort

theorem CompiledPolicy.run_append {policy : CompiledPolicy} {data : Bytes} (extra : Bytes) {ctx : Context}
    (noAbort : (policy.run data ctx).outcome.verdict ≠ .abort) :
    (policy.run (data ++ extra) ctx).outcome = (policy.run data ctx).outcome := by
  have groups : (policy.runGroups data ctx).outcome.verdict ≠ .abort →
      (policy.runGroups (data ++ extra) ctx).outcome = (policy.runGroups data ctx).outcome :=
    Quantifier.run_congr .any fun rules _ rulesNoAbort =>
      Quantifier.run_congr .all (fun rule _ ruleNoAbort => CompiledRule.run_append extra ruleNoAbort) rulesNoAbort
  simp only [CompiledPolicy.run] at noAbort ⊢
  cases selectorIs : policy.selector with
  | none =>
    simp only [selectorIs] at noAbort ⊢
    exact groups noAbort
  | some selector =>
    simp only [selectorIs] at noAbort ⊢
    by_cases short : data.length < Policy.SELECTOR_SIZE
    · simp [short] at noAbort
    have opens : (data ++ extra).take Policy.SELECTOR_SIZE = data.take Policy.SELECTOR_SIZE :=
      List.take_append_of_le_length (by omega)
    have longer : ¬(data ++ extra).length < Policy.SELECTOR_SIZE := by simp only [List.length_append]; omega
    simp only [short, longer, opens, ↓reduceIte] at noAbort ⊢
    split
    · rename_i same
      simp only [same, ↓reduceIte] at noAbort
      exact groups noAbort
    · rfl

/-- Whatever bytes follow the calldata, a verdict stands: every calldata read is checked against the end, and a read
past it aborts instead of happening. -/
theorem Policy.outcome_append {blob data : Bytes} (extra : Bytes) {ctx : Context}
    (noAbort : (Policy.outcome blob data ctx).verdict ≠ .abort) :
    Policy.outcome blob (data ++ extra) ctx = Policy.outcome blob data ctx := by
  simp only [Policy.outcome, Policy.run] at noAbort ⊢
  split
  · rename_i policy _ _
    split at noAbort
    · exact CompiledPolicy.run_append extra (by simp_all)
    · simp_all
  · rfl


/-! ### Work -/

theorem Quantifier.run_steps_le {Item : Type} {run : Item → Trace} (bound : Item → Nat) (quantifier : Quantifier) :
    ∀ {items : List Item}, (∀ item ∈ items, (run item).steps ≤ bound item) →
      (quantifier.run run items).steps ≤ (items.map bound).sum
  | [], _ => by cases quantifier <;> simp [Quantifier.run]
  | item :: items, bounded => by
    have first := bounded item List.mem_cons_self
    have rest := run_steps_le bound quantifier fun other isMember => bounded other (List.mem_cons_of_mem item isMember)
    cases quantifier <;> simp only [Quantifier.run, List.map_cons, List.sum_cons] <;> split <;> simp only <;> omega

theorem sum_map_const {Item : Type} (items : List Item) (value : Nat) :
    (items.map fun _ => value).sum = items.length * value := by
  induction items with
  | nil => simp
  | cons item items rest => simp [rest, Nat.succ_mul, Nat.add_comm]

theorem FrameHint.count_of_resolveArray {hint : FrameHint} {data : Bytes} {start elements count : Nat}
    (resolved : hint.resolveArray data start = .ok (elements, count)) (static : hint.count ≠ 0) :
    count = hint.count := by
  unfold FrameHint.resolveArray at resolved
  cases chain : resolveHops data hint.hops start with
  | error => simp [chain, bind, Except.bind] at resolved
  | ok base =>
    simp [chain, bind, Except.bind, static, pure, Except.pure] at resolved
    exact resolved.2.symm

theorem CompiledRule.run_steps_le (rule : CompiledRule) (data : Bytes) (ctx : Context) (start : Nat) :
    (rule.run data ctx start).steps ≤ rule.workBound := by
  cases rule with
  | test => simp [CompiledRule.run, CompiledTest.run, CompiledRule.workBound]
  | loop quantifier arrayPath hint body =>
    simp only [CompiledRule.run, CompiledRule.workBound]
    cases resolved : hint.resolveArray data start with
    | error => simp
    | ok array =>
      obtain ⟨elements, count⟩ := array
      by_cases over : MAX_QUANTIFIED_ARRAY_LENGTH < count
      · simp [over]
      simp only [over, ↓reduceIte]
      refine Nat.le_trans
        (Nat.add_le_add_right (Quantifier.run_steps_le (fun _ => body.length) quantifier ?_) 1) ?_
      · intro position _
        split
        next element _ =>
          have tests := Quantifier.run_steps_le (fun _ => 1) .all (items := body)
            (run := CompiledTest.run data ctx element) (fun _ _ => Nat.le_refl 1)
          simpa [sum_map_const] using tests
        next => simp
      simp only [sum_map_const, List.length_range]
      have counted : count ≤ if hint.count = 0 then MAX_QUANTIFIED_ARRAY_LENGTH
          else min hint.count MAX_QUANTIFIED_ARRAY_LENGTH := by
        split
        · omega
        · rename_i static
          rw [FrameHint.count_of_resolveArray resolved static] at over ⊢
          omega
      have scaled := Nat.mul_le_mul_right body.length counted
      omega

theorem CompiledPolicy.run_steps_le (policy : CompiledPolicy) (data : Bytes) (ctx : Context) :
    (policy.run data ctx).steps ≤ policy.workBound := by
  have groups : (policy.runGroups data ctx).steps ≤ policy.workBound := by
    unfold CompiledPolicy.runGroups CompiledPolicy.workBound
    exact Quantifier.run_steps_le (fun rules : List CompiledRule => (rules.map CompiledRule.workBound).sum) .any
      (fun rules _ => Quantifier.run_steps_le CompiledRule.workBound .all
        (fun rule _ => rule.run_steps_le data ctx (Policy.argumentsStart policy.selector)))
  simp only [CompiledPolicy.run]
  split
  · exact groups
  · split
    · simp
    · split
      · exact groups
      · simp

namespace Policy

theorem supports_of_parse {blob : Bytes} {policy : CompiledPolicy} (parsed : parse blob = some policy) :
    ∃ header, blob.head? = some header ∧ supports header = true := by
  unfold parse at parsed
  split at parsed
  · rename_i rest reads
    simp only [Policy.read] at reads
    obtain ⟨header, afterHeader, readsHeader, reads⟩ := Reader.bind_eq_some.mp reads
    obtain ⟨_, _, required, -⟩ := Reader.bind_eq_some.mp reads
    obtain ⟨supported, -⟩ := Reader.require_eq_some.mp required
    cases blob with
    | nil => simp [Reader.byte] at readsHeader
    | cons first rest =>
      simp only [Reader.byte, Option.some.injEq, Prod.mk.injEq] at readsHeader
      obtain ⟨rfl, rfl⟩ := readsHeader
      refine ⟨first, rfl, ?_⟩
      simp only [Bool.and_eq_true, decide_eq_true_eq] at supported
      simp [supports, supported.1, supported.2, MINOR]
  · contradiction

/-- Theorem 5: storage validation makes evaluation safe. On every blob it accepts, the enforcer reads the policy the
format defines, with every field within the blob (`load_of_parse`). It takes at most `workBound` steps on any calldata.
Each calldata read is bounded by the end, so bytes after the calldata never alter the verdict (`outcome_append`). -/
theorem enforce_safe {blob : Bytes} (validates : validate blob = true) :
    ∃ policy, parse blob = some policy ∧ load blob = some policy ∧
      ∀ data ctx, run blob data ctx = policy.run data ctx ∧ (run blob data ctx).steps ≤ policy.workBound ∧
        ∀ extra, (outcome blob data ctx).verdict ≠ .abort →
          outcome blob (data ++ extra) ctx = outcome blob data ctx := by
  obtain ⟨policy, parsed⟩ := Option.isSome_iff_exists.mp validates
  have loaded := load_of_parse parsed
  obtain ⟨header, headed, supported⟩ := supports_of_parse parsed
  have runs : ∀ data ctx, run blob data ctx = policy.run data ctx := fun data ctx => by
    simp [run, headed, loaded, Option.filter, supported]
  exact ⟨policy, parsed, loaded, fun data ctx =>
    ⟨runs data ctx, runs data ctx ▸ policy.run_steps_le data ctx, fun extra noAbort => outcome_append extra noAbort⟩⟩

end Policy

end Callcium
