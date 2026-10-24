import Callcium.Enforce
import Callcium.Theorems.Wire

/-!
# The enforcer's view of stored blobs

On every blob storage validation accepts, the enforcer's reader `Policy.load` reads the policy `Policy.parse` does.
Every field it reads lies within the blob and reads as the format defines it. This is the blob half of theorem 5.
-/

namespace Callcium

open Reader

/-! ## Readers -/

theorem Reader.bind_eq_some {Item Other : Type} {reader : Reader Item} {next : Item → Reader Other} {bytes : Bytes}
    {result : Other} {rest : Bytes} :
    (reader >>= next) bytes = some (result, rest) ↔
      ∃ item middle, reader bytes = some (item, middle) ∧ next item middle = some (result, rest) := by
  simp only [bind, StateT.bind]
  cases reader bytes with
  | none => simp
  | some pair =>
    obtain ⟨item, middle⟩ := pair
    simp only [Option.some.injEq, Prod.mk.injEq]
    exact ⟨fun reads => ⟨item, middle, ⟨rfl, rfl⟩, reads⟩, fun ⟨_, _, ⟨same, sameMiddle⟩, reads⟩ => by
      rw [same, sameMiddle]; exact reads⟩

theorem Reader.map_eq_some {Item Other : Type} {reader : Reader Item} {function : Item → Other} {bytes : Bytes}
    {result : Other} {rest : Bytes} :
    (function <$> reader) bytes = some (result, rest) ↔
      ∃ item, reader bytes = some (item, rest) ∧ function item = result := by
  simp only [Functor.map, StateT.map]
  cases reader bytes with
  | none => simp
  | some pair => obtain ⟨item, after⟩ := pair; simp only [Option.some.injEq, Prod.mk.injEq]; grind

theorem Reader.pure_eq_some {Item : Type} {item result : Item} {bytes rest : Bytes} :
    (pure item : Reader Item) bytes = some (result, rest) ↔ item = result ∧ bytes = rest := by
  simp [pure, StateT.pure]

theorem Reader.require_eq_some {condition : Bool} {bytes rest : Bytes} {done : Unit} :
    require condition bytes = some (done, rest) ↔ condition = true ∧ bytes = rest := by
  unfold require
  cases condition <;> simp [pure, StateT.pure, failure, StateT.failure]

theorem Reader.some?_eq_some {Item : Type} {option : Option Item} {bytes rest : Bytes} {item : Item} :
    some? option bytes = some (item, rest) ↔ option = some item ∧ bytes = rest := by
  unfold some?
  cases option <;> simp [pure, StateT.pure, failure, StateT.failure, eq_comm]

/-! ## Hints -/

theorem ArrayMeta.ofWordMasked_of_ofWord? {word : Nat} {array : ArrayMeta}
    (decoded : ArrayMeta.ofWord? word = some array) :
    ArrayMeta.ofWordMasked word = array := by
  unfold ArrayMeta.ofWord? at decoded
  split at decoded <;> simp_all

theorem Hop.load_of_read {bytes rest : Bytes} {hop : Hop} (reads : Hop.read bytes = some (hop, rest)) :
    Hop.load bytes = some (hop, rest) := by
  simp only [Hop.read, bind_eq_some] at reads
  obtain ⟨delta, afterDelta, readsDelta, index, afterIndex, readsIndex, metaWord, afterMeta, readsMeta, decided⟩ :=
    reads
  simp only [Hop.load, bind_of readsDelta, bind_of readsIndex, bind_of readsMeta, pure_eq_some]
  split at decided
  · rename_i plain
    simp only [bind_eq_some, require_eq_some, pure_eq_some] at decided
    obtain ⟨_, _, ⟨-, rfl⟩, rfl, rfl⟩ := decided
    simp [plain]
  · rename_i element
    simp only [bind_eq_some, require_eq_some, some?_eq_some, pure_eq_some] at decided
    obtain ⟨_, _, ⟨-, rfl⟩, array, _, ⟨decodedMeta, rfl⟩, rfl, rfl⟩ := decided
    simp [element, ArrayMeta.ofWordMasked_of_ofWord? decodedMeta]

theorem Reader.many_of_many {Item : Type} {checked unchecked : Reader Item}
    (refines : ∀ {bytes item rest}, checked bytes = some (item, rest) → unchecked bytes = some (item, rest)) :
    ∀ {count : Nat} {bytes : Bytes} {items : List Item} {rest : Bytes},
      many checked count bytes = some (items, rest) → many unchecked count bytes = some (items, rest)
  | 0, _, _, _, reads => by simpa [many] using reads
  | count + 1, _, _, _, reads => by
    simp only [many, bind_eq_some, pure_eq_some] at reads
    obtain ⟨item, middle, readsItem, others, after, readsOthers, rfl, rfl⟩ := reads
    simp only [many, bind_of (refines readsItem), bind_of (many_of_many refines readsOthers)]
    rfl

theorem Reader.within_of_framed {Item : Type} {checked unchecked : Reader Item}
    (refines : ∀ {bytes item rest}, checked bytes = some (item, rest) → unchecked bytes = some (item, rest))
    {size : Nat} {bytes : Bytes} {item : Item} {rest : Bytes} (reads : framed size checked bytes = some (item, rest)) :
    within size unchecked bytes = some (item, rest) := by
  simp only [framed, bind_eq_some] at reads
  obtain ⟨region, after, readsRegion, decided⟩ := reads
  simp only [within, bind_of readsRegion]
  cases readsInner : checked region with
  | none => simp [readsInner, failure, StateT.failure] at decided
  | some pair =>
    obtain ⟨inner, leftover⟩ := pair
    cases leftover with
    | nil =>
      simp only [readsInner, pure_eq_some] at decided
      obtain ⟨rfl, rfl⟩ := decided
      simp [refines readsInner, pure, StateT.pure]
    | cons => simp [readsInner, failure, StateT.failure] at decided

theorem loadHops_of_readHops {bytes rest : Bytes} {hops : List Hop} (reads : readHops bytes = some (hops, rest)) :
    loadHops bytes = some (hops, rest) := by
  simp only [readHops, bind_eq_some, require_eq_some] at reads
  obtain ⟨header, afterHeader, readsHeader, _, _, ⟨-, rfl⟩, readsHops⟩ := reads
  simp only [loadHops, bind_of readsHeader]
  exact many_of_many Hop.load_of_read readsHops

theorem TestHint.load_of_read {bytes rest : Bytes} {hint : TestHint} (reads : TestHint.read bytes = some (hint, rest)) :
    TestHint.load bytes = some (hint, rest) := by
  simp only [TestHint.read, bind_eq_some] at reads
  obtain ⟨hops, afterHops, readsHops, targetDelta, afterDelta, readsDelta, metaWord, afterMeta, readsMeta, typeCode,
    afterCode, readsCode, decided⟩ := reads
  simp only [TestHint.load, bind_of (loadHops_of_readHops readsHops), bind_of readsDelta, bind_of readsMeta,
    bind_of readsCode, pure_eq_some]
  split at decided
  · rename_i dynamic
    simp only [bind_eq_some, some?_eq_some, pure_eq_some] at decided
    obtain ⟨array, _, ⟨decodedMeta, rfl⟩, rfl, rfl⟩ := decided
    simp [dynamic, ArrayMeta.ofWordMasked_of_ofWord? decodedMeta]
  · rename_i other
    simp only [bind_eq_some, require_eq_some, pure_eq_some] at decided
    obtain ⟨_, _, ⟨-, rfl⟩, rfl, rfl⟩ := decided
    simp [other]

theorem FrameHint.load_of_read {bytes rest : Bytes} {hint : FrameHint}
    (reads : FrameHint.read bytes = some (hint, rest)) : FrameHint.load bytes = some (hint, rest) := by
  simp only [FrameHint.read, bind_eq_some, some?_eq_some, pure_eq_some] at reads
  obtain ⟨hops, afterHops, readsHops, arrayDelta, afterDelta, readsDelta, count, afterCount, readsCount, metaWord,
    afterMeta, readsMeta, array, _, ⟨decodedMeta, rfl⟩, rfl, rfl⟩ := reads
  simp [FrameHint.load, bind_of (loadHops_of_readHops readsHops), bind_of readsDelta, bind_of readsCount,
    map_of readsMeta, ArrayMeta.ofWordMasked_of_ofWord? decodedMeta]

theorem loadPath_of_readPath {bytes rest : Bytes} {path : Path} (reads : readPath bytes = some (path, rest)) :
    loadPath bytes = some (path, rest) := by
  simp only [readPath, bind_eq_some, require_eq_some, pure_eq_some] at reads
  obtain ⟨depth, afterDepth, readsDepth, steps, afterSteps, readsSteps, _, _, ⟨-, rfl⟩, rfl, rfl⟩ := reads
  simp only [loadPath, bind_of readsDepth]
  exact readsSteps

/-! ## Operators and rules -/

theorem Operator.load_of_read {code : UInt8} {bytes rest : Bytes} {operator : Operator}
    (reads : Operator.read code bytes = some (operator, rest)) : Operator.load code bytes = some (operator, rest) := by
  simp only [Operator.read, bind_eq_some, some?_eq_some] at reads
  obtain ⟨opByte, afterOp, readsOp, comparison, _, ⟨decodedComparison, rfl⟩, wordType, _, ⟨typed, rfl⟩, dataLength,
    afterLength, readsLength, decided⟩ := reads
  simp only [Operator.load, bind_of readsOp, decodedComparison]
  rw [bind_of (some?_some _ _)]
  simp only [typed]
  rw [bind_of (some?_some _ _), bind_of readsLength]
  by_cases constant : opByte.toNat % NOT_FLAG / 2 ^ SOURCE_SHIFT = SOURCE_CONSTANT
  · simp only [constant, ↓reduceIte] at decided ⊢
    obtain ⟨_, _, counted, decided⟩ := bind_eq_some.mp decided
    obtain ⟨countFits, rfl⟩ := require_eq_some.mp counted
    obtain ⟨raw, after, readsValues, decided⟩ := bind_eq_some.mp decided
    obtain ⟨_, _, ordered, decided⟩ := bind_eq_some.mp decided
    obtain ⟨-, rfl⟩ := require_eq_some.mp ordered
    have sameCount : comparison.arity.getD (dataLength / wordType.width) = dataLength / wordType.width := by
      cases arity : comparison.arity with
      | none => rfl
      | some count =>
        simp only [arity, Option.map_some, Option.getD_some, Bool.and_eq_true, beq_iff_eq] at countFits
        exact countFits.2
    rw [sameCount, bind_of readsValues]
    exact decided
  · by_cases context : opByte.toNat % NOT_FLAG / 2 ^ SOURCE_SHIFT = SOURCE_CONTEXT
    · simp only [constant, ↓reduceIte] at decided ⊢
      simp only [context, ↓reduceIte] at decided ⊢
      obtain ⟨_, _, sized, decided⟩ := bind_eq_some.mp decided
      obtain ⟨-, rfl⟩ := require_eq_some.mp sized
      obtain ⟨property, after, readsProperty, decided⟩ := bind_eq_some.mp decided
      obtain ⟨_, _, defined, decided⟩ := bind_eq_some.mp decided
      obtain ⟨-, rfl⟩ := require_eq_some.mp defined
      rw [bind_of readsProperty]
      exact decided
    · simp [constant, context, failure, StateT.failure] at decided

theorem CompiledTest.loadScoped_of_readScoped {root : Bool} {outerDepth : Nat} {scope : UInt8} {bytes rest : Bytes}
    {test : CompiledTest} (reads : CompiledTest.readScoped root outerDepth scope bytes = some (test, rest)) :
    CompiledTest.loadScoped scope bytes = some (test, rest) := by
  by_cases context : scope = SCOPE_CONTEXT
  · simp only [CompiledTest.readScoped, context, ↓reduceIte] at reads
    simp only [CompiledTest.loadScoped, context, ↓reduceIte]
    obtain ⟨depthByte, afterDepth, readsDepth, reads⟩ := bind_eq_some.mp reads
    obtain ⟨_, _, isOne, reads⟩ := bind_eq_some.mp reads
    obtain ⟨-, rfl⟩ := require_eq_some.mp isOne
    obtain ⟨property, afterProperty, readsProperty, reads⟩ := bind_eq_some.mp reads
    obtain ⟨_, _, defined, reads⟩ := bind_eq_some.mp reads
    obtain ⟨-, rfl⟩ := require_eq_some.mp defined
    obtain ⟨operator, afterOperator, readsOperator, reads⟩ := bind_eq_some.mp reads
    rw [bind_of readsDepth, bind_of readsProperty, bind_of (Operator.load_of_read readsOperator)]
    exact reads
  · by_cases calldata : scope = SCOPE_CALLDATA
    · simp only [CompiledTest.readScoped, context, ↓reduceIte] at reads
      simp only [calldata, ↓reduceIte] at reads
      simp only [CompiledTest.loadScoped, context, ↓reduceIte]
      simp only [calldata, ↓reduceIte]
      obtain ⟨path, afterPath, readsPath, reads⟩ := bind_eq_some.mp reads
      obtain ⟨_, _, pathFits, reads⟩ := bind_eq_some.mp reads
      obtain ⟨-, rfl⟩ := require_eq_some.mp pathFits
      obtain ⟨hint, afterHint, readsHint, reads⟩ := bind_eq_some.mp reads
      obtain ⟨operator, afterOperator, readsOperator, reads⟩ := bind_eq_some.mp reads
      rw [bind_of (loadPath_of_readPath readsPath), bind_of (TestHint.load_of_read readsHint),
        bind_of (Operator.load_of_read readsOperator)]
      exact reads
    · simp [CompiledTest.readScoped, context, calldata, failure, StateT.failure] at reads

theorem loadFramed_of_readFramed {Item : Type} {checked unchecked : Reader Item}
    (refines : ∀ {bytes item rest}, checked bytes = some (item, rest) → unchecked bytes = some (item, rest))
    {bytes : Bytes} {item : Item} {rest : Bytes} (reads : readFramed checked bytes = some (item, rest)) :
    loadFramed unchecked bytes = some (item, rest) := by
  simp only [readFramed] at reads
  obtain ⟨ruleSize, afterSize, readsSize, reads⟩ := bind_eq_some.mp reads
  rw [loadFramed, bind_of readsSize]
  exact within_of_framed refines reads

theorem CompiledTest.load_of_read {outerDepth : Nat} {bytes rest : Bytes} {test : CompiledTest}
    (reads : CompiledTest.read outerDepth bytes = some (test, rest)) : CompiledTest.load bytes = some (test, rest) :=
  loadFramed_of_readFramed (fun reads => by
    obtain ⟨scope, afterScope, readsScope, reads⟩ := bind_eq_some.mp reads
    rw [bind_of readsScope]
    exact CompiledTest.loadScoped_of_readScoped reads) reads

theorem CompiledRule.load_of_read {bytes rest : Bytes} {rule : CompiledRule}
    (reads : CompiledRule.read bytes = some (rule, rest)) : CompiledRule.load bytes = some (rule, rest) :=
  loadFramed_of_readFramed (fun reads => by
    obtain ⟨scope, afterScope, readsScope, reads⟩ := bind_eq_some.mp reads
    rw [bind_of readsScope]
    by_cases loop : scope = SCOPE_LOOP
    · simp only [loop, ↓reduceIte] at reads ⊢
      obtain ⟨quantifierByte, afterQuantifier, readsQuantifier, reads⟩ := bind_eq_some.mp reads
      obtain ⟨quantifier, _, decoded, reads⟩ := bind_eq_some.mp reads
      obtain ⟨decodedQuantifier, rfl⟩ := some?_eq_some.mp decoded
      obtain ⟨arrayPath, afterPath, readsPath, reads⟩ := bind_eq_some.mp reads
      obtain ⟨_, _, pathFits, reads⟩ := bind_eq_some.mp reads
      obtain ⟨-, rfl⟩ := require_eq_some.mp pathFits
      obtain ⟨hint, afterHint, readsHint, reads⟩ := bind_eq_some.mp reads
      obtain ⟨ruleCount, afterCount, readsCount, reads⟩ := bind_eq_some.mp reads
      obtain ⟨_, _, nonempty, reads⟩ := bind_eq_some.mp reads
      obtain ⟨-, rfl⟩ := require_eq_some.mp nonempty
      obtain ⟨body, afterBody, readsBody, reads⟩ := bind_eq_some.mp reads
      rw [bind_of readsQuantifier, decodedQuantifier, bind_of (some?_some _ _),
        bind_of (loadPath_of_readPath readsPath),
        bind_of (FrameHint.load_of_read readsHint), bind_of readsCount,
        bind_of (many_of_many CompiledTest.load_of_read readsBody)]
      exact reads
    · simp only [loop, ↓reduceIte] at reads ⊢
      obtain ⟨test, readsTest, rfl⟩ := map_eq_some.mp reads
      exact map_of (CompiledTest.loadScoped_of_readScoped readsTest)) reads

theorem loadGroup_of_readGroup {bytes rest : Bytes} {rules : List CompiledRule}
    (reads : readGroup bytes = some (rules, rest)) : loadGroup bytes = some (rules, rest) := by
  simp only [readGroup] at reads
  obtain ⟨ruleCount, afterCount, readsCount, reads⟩ := bind_eq_some.mp reads
  obtain ⟨groupSize, afterSize, readsSize, reads⟩ := bind_eq_some.mp reads
  obtain ⟨_, _, nonempty, reads⟩ := bind_eq_some.mp reads
  obtain ⟨-, rfl⟩ := require_eq_some.mp nonempty
  rw [loadGroup, bind_of readsCount, bind_of readsSize]
  exact within_of_framed (many_of_many CompiledRule.load_of_read) reads

theorem Policy.loadPolicy_of_read {bytes rest : Bytes} {policy : CompiledPolicy}
    (reads : Policy.read bytes = some (policy, rest)) : Policy.loadPolicy bytes = some (policy, rest) := by
  simp only [Policy.read] at reads
  obtain ⟨header, afterHeader, readsHeader, reads⟩ := bind_eq_some.mp reads
  obtain ⟨_, _, supported, reads⟩ := bind_eq_some.mp reads
  obtain ⟨-, rfl⟩ := require_eq_some.mp supported
  obtain ⟨selector, afterSelector, readsSelector, reads⟩ := bind_eq_some.mp reads
  obtain ⟨_, _, slot, reads⟩ := bind_eq_some.mp reads
  obtain ⟨-, rfl⟩ := require_eq_some.mp slot
  obtain ⟨descLength, afterLength, readsLength, reads⟩ := bind_eq_some.mp reads
  obtain ⟨desc, afterDesc, readsDesc, reads⟩ := bind_eq_some.mp reads
  obtain ⟨_, _, wellFormed, reads⟩ := bind_eq_some.mp reads
  obtain ⟨-, rfl⟩ := require_eq_some.mp wellFormed
  obtain ⟨groupCount, afterCount, readsCount, reads⟩ := bind_eq_some.mp reads
  obtain ⟨_, _, nonempty, reads⟩ := bind_eq_some.mp reads
  obtain ⟨-, rfl⟩ := require_eq_some.mp nonempty
  obtain ⟨groups, afterGroups, readsGroups, reads⟩ := bind_eq_some.mp reads
  rw [Policy.loadPolicy, bind_of readsHeader, bind_of readsSelector, bind_of readsLength, bind_of readsDesc,
    bind_of readsCount, bind_of (many_of_many loadGroup_of_readGroup readsGroups)]
  exact reads

/-- The blob half of theorem 5: on a blob storage validation accepts, the enforcer reads the policy the format
defines, every field within the blob. -/
theorem Policy.load_of_parse {blob : Bytes} {policy : CompiledPolicy} (parsed : Policy.parse blob = some policy) :
    Policy.load blob = some policy := by
  unfold Policy.parse at parsed
  split at parsed
  · rename_i rest reads
    cases parsed
    simp [Policy.load, Policy.loadPolicy_of_read reads]
  · contradiction

end Callcium
