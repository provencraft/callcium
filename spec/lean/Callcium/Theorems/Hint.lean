import Callcium.Hint
import Callcium.Theorems.Abi
import Callcium.Theorems.Descriptor

/-!
# Hints

Theorem 3: wherever a compiled hint resolves, on any calldata, it ends where `decodeSolc` places the value at the path
(`AbiType.locate`), so what the enforcer reads there is what the decoder decodes; wherever it stops at a fixed index
past a dynamic array's length, `decodeSolc` places no value there. A loop's hint yields the array's elements as
`decodeSolc` reads them, so the body's hints resolve from each element by the same theorem. Theorem 24: on canonical
calldata, the hint of a path the value holds resolves to that value's canonical encoding, the hint of a path it does not
hold stops at the index past the array's length, and a loop's hint yields every element at its canonical encoding.
Theorem 14 at path level: on a valid descriptor, repeated `skipNode` finds a parameter or a tuple's field where the
structural walk does.
-/

namespace Callcium

/-! ## Resolution steps -/

theorem Except.bind_eq_ok {Error Value Result : Type} {first : Except Error Value}
    {next : Value → Except Error Result} {result : Result} :
    first >>= next = .ok result ↔ ∃ value, first = .ok value ∧ next value = .ok result := by
  cases first <;> simp [bind, Except.bind]

theorem Except.map_eq_ok {Error Value Result : Type} {first : Except Error Value} {next : Value → Result}
    {result : Result} : first.map next = .ok result ↔ ∃ value, first = .ok value ∧ next value = result := by
  cases first <;> simp [Except.map]

theorem Except.map_eq_error {Error Value Result : Type} {first : Except Error Value} {next : Value → Result}
    {error : Error} : first.map next = .error error ↔ first = .error error := by
  cases first <;> simp [Except.map]

theorem loadWord_eq_ok {data : Bytes} {position : Nat} {word : Word} :
    loadWord data position = .ok word ↔ position + WORD_SIZE ≤ data.length ∧ word = readWord data position := by
  unfold loadWord
  by_cases within : position + WORD_SIZE ≤ data.length <;> simp [within, eq_comm]

theorem follow_eq_ok {data : Bytes} {base head next : Nat} :
    follow data base head = .ok next ↔
      head + WORD_SIZE ≤ data.length ∧ base + (readWord data head).toNat ≤ data.length ∧
        next = advance base (readWord data head).toNat := by
  unfold follow loadWord
  by_cases within : head + WORD_SIZE ≤ data.length <;>
    by_cases room : base + (readWord data head).toNat ≤ data.length <;>
    simp [within, room, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, eq_comm]

theorem resolveHops_nil {data : Bytes} {start next : Nat} : resolveHops data [] start = .ok next ↔ next = start := by
  simp [resolveHops, pure, Except.pure, eq_comm]

theorem resolveHops_cons {data : Bytes} {hop : Hop} {hops : List Hop} {start next : Nat} :
    resolveHops data (hop :: hops) start = .ok next ↔
      ∃ middle, hop.apply data start = .ok middle ∧ resolveHops data hops middle = .ok next := by
  simp only [resolveHops, List.foldlM_cons]
  exact Except.bind_eq_ok

theorem resolveHops_append {data : Bytes} {hops others : List Hop} {start next : Nat} :
    resolveHops data (hops ++ others) start = .ok next ↔
      ∃ middle, resolveHops data hops start = .ok middle ∧ resolveHops data others middle = .ok next := by
  simp only [resolveHops, List.foldlM_append]
  exact Except.bind_eq_ok

theorem resolveHops_enter {data : Bytes} {needed : Bool} {delta base next : Nat} :
    resolveHops data (enter needed delta).1 base = .ok next ↔
      if needed then follow data base (advance base delta) = .ok next else next = base := by
  cases needed <;> simp [enter, resolveHops_cons, resolveHops_nil, Hop.apply]

theorem ArrayMeta.of_dynamicArray (element : AbiType) (dynamicArray : Bool) :
    (ArrayMeta.of element dynamicArray).dynamicArray = dynamicArray := rfl

theorem WORD_SIZE_mul_strideWords (element : AbiType) (dynamicArray : Bool) :
    WORD_SIZE * (ArrayMeta.of element dynamicArray).strideWords = element.headSize := by
  unfold ArrayMeta.of AbiType.headSize
  split <;> simp

theorem elementAt_eq_ok {element : AbiType} {dynamicArray : Bool} {data : Bytes} {elements index next : Nat} :
    (ArrayMeta.of element dynamicArray).elementAt data elements index = .ok next ↔
      if element.isDynamic then follow data elements (advance elements (index * element.headSize)) = .ok next
      else next = advance elements (index * element.headSize) := by
  unfold ArrayMeta.elementAt
  rw [WORD_SIZE_mul_strideWords]
  cases dynamic : element.isDynamic <;> simp [ArrayMeta.of, dynamic, pure, Except.pure, eq_comm]

/-- An element a hop or a loop reaches starts where `decodeSolc` places it. -/
theorem elementAt_componentStart {element : AbiType} {dynamicArray : Bool} {data : Bytes} {elements index next : Nat}
    (resolved : (ArrayMeta.of element dynamicArray).elementAt data elements index = .ok next) :
    next = element.componentStart data elements (advance elements (index * element.headSize)) := by
  rw [elementAt_eq_ok] at resolved
  unfold AbiType.componentStart
  split at resolved
  · rename_i dynamic
    simpa [dynamic] using (follow_eq_ok.mp resolved).2.2
  · rename_i static
    simpa [static] using resolved

theorem follow_lt {data : Bytes} {base head next : Nat} (followed : follow data base head = .ok next) :
    next < 2 ^ 256 := by
  rw [(follow_eq_ok.mp followed).2.2]
  exact advance_lt _ _

/-- A followed offset never leaves the calldata: an offset word that would carry its base past the end faults. -/
theorem follow_le_length {data : Bytes} {base head next : Nat} (followed : follow data base head = .ok next) :
    next ≤ data.length := by
  obtain ⟨-, room, rfl⟩ := follow_eq_ok.mp followed
  exact Nat.le_trans (Nat.mod_le _ _) room

theorem elementAt_lt {element : AbiType} {dynamicArray : Bool} {data : Bytes} {elements index next : Nat}
    (resolved : (ArrayMeta.of element dynamicArray).elementAt data elements index = .ok next) : next < 2 ^ 256 := by
  rw [elementAt_componentStart resolved]
  exact AbiType.componentStart_lt _ _ _ _ _

theorem resolveHops_append_of_ok {data : Bytes} {hops others : List Hop} {start middle : Nat}
    (first : resolveHops data hops start = .ok middle) :
    resolveHops data (hops ++ others) start = resolveHops data others middle := by
  simp only [resolveHops, List.foldlM_append] at first ⊢
  rw [first]
  rfl

theorem resolveHops_append_of_error {data : Bytes} {hops others : List Hop} {start : Nat} {fault : Fault}
    (first : resolveHops data hops start = .error fault) :
    resolveHops data (hops ++ others) start = .error fault := by
  simp only [resolveHops, List.foldlM_append] at first ⊢
  rw [first]
  rfl

theorem resolveHops_cons_of_ok {data : Bytes} {hop : Hop} {hops : List Hop} {start middle : Nat}
    (first : hop.apply data start = .ok middle) :
    resolveHops data (hop :: hops) start = resolveHops data hops middle := by
  simp only [resolveHops, List.foldlM_cons, first]
  rfl

theorem resolveHops_cons_of_error {data : Bytes} {hop : Hop} {hops : List Hop} {start : Nat} {fault : Fault}
    (first : hop.apply data start = .error fault) : resolveHops data (hop :: hops) start = .error fault := by
  simp only [resolveHops, List.foldlM_cons, first]
  rfl

theorem resolveHops_singleton (data : Bytes) (hop : Hop) (start : Nat) :
    resolveHops data [hop] start = hop.apply data start := by
  simp [resolveHops]

theorem follow_ne_arrayIndex {data : Bytes} {base head : Nat} :
    follow data base head ≠ .error .arrayIndexOutOfBounds := by
  unfold follow loadWord
  by_cases within : head + WORD_SIZE ≤ data.length <;>
    by_cases room : base + (readWord data head).toNat ≤ data.length <;>
    simp [within, room, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

theorem elementAt_ne_arrayIndex {array : ArrayMeta} {data : Bytes} {elements index : Nat} :
    array.elementAt data elements index ≠ .error .arrayIndexOutOfBounds := by
  unfold ArrayMeta.elementAt
  split
  · exact follow_ne_arrayIndex
  · simp [pure, Except.pure]

theorem resolveHops_enter_ne_arrayIndex {data : Bytes} {needed : Bool} {delta base : Nat} :
    resolveHops data (enter needed delta).1 base ≠ .error .arrayIndexOutOfBounds := by
  cases needed
  · simp [enter, resolveHops, pure, Except.pure]
  · simpa [enter, resolveHops_singleton, Hop.apply] using follow_ne_arrayIndex

/-! ## Theorem 3 -/

theorem Hop.apply_element_eq_ok {data : Bytes} {base index next : Nat} {array : ArrayMeta} :
    Hop.apply data base (.element index array) = .ok next ↔
      if array.dynamicArray then
        base + WORD_SIZE ≤ data.length ∧ index < (readWord data base).toNat ∧
          array.elementAt data (advance base WORD_SIZE) index = .ok next
      else array.elementAt data base index = .ok next := by
  unfold Hop.apply
  cases dynamic : array.dynamicArray with
  | false => simp [dynamic]
  | true =>
    simp only [dynamic, ↓reduceIte, Except.bind_eq_ok, loadWord_eq_ok]
    constructor
    · rintro ⟨word, ⟨within, rfl⟩, resolved⟩
      split at resolved
      · exact ⟨within, by assumption, resolved⟩
      · simp [throw, throwThe, MonadExceptOf.throw] at resolved
    · rintro ⟨within, below, resolved⟩
      exact ⟨_, ⟨within, rfl⟩, by simp [below, resolved]⟩

theorem Hop.apply_element_eq_arrayIndex {data : Bytes} {base index : Nat} {array : ArrayMeta} :
    Hop.apply data base (.element index array) = .error .arrayIndexOutOfBounds ↔
      array.dynamicArray = true ∧ base + WORD_SIZE ≤ data.length ∧ ¬index < (readWord data base).toNat := by
  unfold Hop.apply
  cases dynamic : array.dynamicArray with
  | false => simp [dynamic, elementAt_ne_arrayIndex]
  | true =>
    unfold loadWord
    by_cases within : base + WORD_SIZE ≤ data.length <;>
      by_cases below : index < (readWord data base).toNat <;>
      simp [dynamic, within, below, bind, Except.bind, throw, throwThe, MonadExceptOf.throw, elementAt_ne_arrayIndex]

theorem AbiType.componentStart_of_static {abiType : AbiType} (static : abiType.isDynamic = false) (data : Bytes)
    (base head : Nat) : abiType.componentStart data base head = head := by
  simp [AbiType.componentStart, static]

/-- A static tuple's fields are static. -/
theorem AbiType.isDynamic_of_field {fields : List AbiType} {step : Nat} {field : AbiType}
    (fieldAt : fields[step]? = some field) (static : (AbiType.tuple fields).isDynamic = false) :
    field.isDynamic = false := by
  simp only [AbiType.isDynamic, AbiType.anyDynamic_eq_false_iff] at static
  exact static field (List.mem_of_getElem? fieldAt)

/-- Entering a node when it is dynamic and not yet entered leaves it `delta` past the new base, with no delta left
for a dynamic node. -/
theorem AbiType.locate_enter {abiType : AbiType} {data : Bytes} {entered : Bool} {delta base middle position : Nat}
    (inRange : base < 2 ^ 256)
    (stands : if entered then delta = 0 ∧ position = base
      else position = abiType.componentStart data base (advance base delta))
    (resolved : resolveHops data (enter (abiType.isDynamic && !entered) delta).1 base = .ok middle) :
    middle < 2 ^ 256 ∧ position = advance middle (enter (abiType.isDynamic && !entered) delta).2 ∧
      (abiType.isDynamic = true → (enter (abiType.isDynamic && !entered) delta).2 = 0) := by
  rw [resolveHops_enter] at resolved
  cases entered with
  | true =>
    simp only [↓reduceIte] at stands
    obtain ⟨rfl, rfl⟩ := stands
    simp only [Bool.not_true, Bool.and_false, Bool.false_eq_true, ↓reduceIte] at resolved
    subst resolved
    simp [enter, advance_zero inRange, inRange]
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte] at stands
    cases dynamic : abiType.isDynamic with
    | true =>
      simp only [dynamic, Bool.not_false, Bool.and_self, ↓reduceIte] at resolved
      have followed := follow_eq_ok.mp resolved
      have below := follow_lt resolved
      simp only [AbiType.componentStart, dynamic, ↓reduceIte] at stands
      simp only [Bool.not_false, Bool.and_self, enter, ↓reduceIte]
      rw [followed.2.2] at below ⊢
      exact ⟨below, by rw [stands, advance_zero below], fun _ => trivial⟩
    | false =>
      simp only [dynamic, Bool.false_and, Bool.false_eq_true, ↓reduceIte] at resolved
      subst resolved
      simp [enter, inRange, stands, AbiType.componentStart_of_static dynamic]

/-- A field of a tuple that starts `delta` past `middle`, with no delta left when the tuple is dynamic, starts where
`decodeSolc` places a component whose head lies past the heads before it. -/
theorem AbiType.componentStart_field {fields : List AbiType} {step : Nat} {field : AbiType}
    (fieldAt : fields[step]? = some field) {data : Bytes} {middle delta position : Nat}
    (middleInRange : middle < 2 ^ 256) (positionIs : position = advance middle delta)
    (settled : (AbiType.tuple fields).isDynamic = true → delta = 0) :
    field.componentStart data position (advance position ((fields.take step).map AbiType.headSize).sum) =
      field.componentStart data middle (advance middle (delta + ((fields.take step).map AbiType.headSize).sum)) := by
  cases fieldDynamic : field.isDynamic with
  | true =>
    have tupleDynamic : (AbiType.tuple fields).isDynamic = true := by
      cases tupleIs : (AbiType.tuple fields).isDynamic with
      | true => rfl
      | false => simp [AbiType.isDynamic_of_field fieldAt tupleIs] at fieldDynamic
    rw [settled tupleDynamic, advance_zero middleInRange] at positionIs
    rw [positionIs, settled tupleDynamic, Nat.zero_add]
  | false =>
    rw [AbiType.componentStart_of_static fieldDynamic, AbiType.componentStart_of_static fieldDynamic, positionIs,
      advance_advance]

/-- Each step of the walk keeps the chain where `locate` is: entered, the node's encoding starts at the base and no
delta is pending; otherwise the node starts where `decodeSolc` places a component whose head lies `delta` past the
base. -/
theorem AbiType.locate_walk {data : Bytes} {path : Path} :
    ∀ {abiType : AbiType} {delta : Nat} {entered : Bool} {hops : List Hop} {finalDelta : Nat} {finalEntered : Bool}
      {found : AbiType} {base finalBase position : Nat},
    abiType.walk path delta entered = some (hops, finalDelta, finalEntered, found) → base < 2 ^ 256 →
    (if entered then delta = 0 ∧ position = base
      else position = abiType.componentStart data base (advance base delta)) →
    resolveHops data hops base = .ok finalBase →
    ∃ finalPosition, abiType.locate data position path = some (found, finalPosition) ∧ finalBase < 2 ^ 256 ∧
      (if finalEntered then finalDelta = 0 ∧ finalPosition = finalBase
        else finalPosition = found.componentStart data finalBase (advance finalBase finalDelta)) := by
  induction path with
  | nil =>
    intro abiType delta entered hops finalDelta finalEntered found base finalBase position walked inRange stands
      resolved
    simp only [AbiType.walk, Option.some.injEq, Prod.mk.injEq] at walked
    obtain ⟨rfl, rfl, rfl, rfl⟩ := walked
    rw [resolveHops_nil] at resolved
    subst resolved
    exact ⟨position, by simp [AbiType.locate], inRange, stands⟩
  | cons step steps rest =>
    intro abiType delta entered hops finalDelta finalEntered found base finalBase position walked inRange stands
      resolved
    cases abiType with
    | word | bytes | string => simp [AbiType.walk] at walked
    | tuple fields =>
      simp only [AbiType.walk] at walked
      cases fieldAt : fields[step]? with
      | none => simp [fieldAt] at walked
      | some field =>
        simp only [fieldAt, Option.map_eq_some_iff, Prod.exists] at walked
        obtain ⟨restHops, restDelta, restEntered, restFound, fieldWalked, same⟩ := walked
        simp only [Prod.mk.injEq] at same
        obtain ⟨rfl, rfl, rfl, rfl⟩ := same
        obtain ⟨middle, entry, resolvedRest⟩ := resolveHops_append.mp resolved
        obtain ⟨middleInRange, positionIs, settled⟩ := AbiType.locate_enter inRange stands entry
        simp only [AbiType.locate, fieldAt]
        apply rest fieldWalked middleInRange _ resolvedRest
        simpa using AbiType.componentStart_field fieldAt middleInRange positionIs settled
    | staticArray element length =>
      simp only [AbiType.walk] at walked
      split at walked
      · rename_i below
        simp only [AbiType.locate, below, ↓reduceIte]
        cases arrayDynamic : (AbiType.staticArray element length).isDynamic with
        | true =>
          have elementDynamic : element.isDynamic = true := by simpa [AbiType.isDynamic] using arrayDynamic
          simp only [arrayDynamic, ↓reduceIte, Option.map_eq_some_iff, Prod.exists] at walked
          obtain ⟨restHops, restDelta, restEntered, restFound, elementWalked, same⟩ := walked
          simp only [Prod.mk.injEq] at same
          obtain ⟨rfl, rfl, rfl, rfl⟩ := same
          obtain ⟨middle, entry, resolvedRest⟩ := resolveHops_append.mp resolved
          obtain ⟨middleInRange, positionIs, settled⟩ :=
            AbiType.locate_enter inRange stands (by simpa [arrayDynamic] using entry)
          rw [settled arrayDynamic, advance_zero middleInRange] at positionIs
          obtain ⟨next, hopped, resolvedRest⟩ := resolveHops_cons.mp resolvedRest
          rw [Hop.apply_element_eq_ok, ArrayMeta.of_dynamicArray] at hopped
          simp only [Bool.false_eq_true, ↓reduceIte] at hopped
          apply rest elementWalked (elementAt_lt hopped) _ resolvedRest
          simp only [elementDynamic, ↓reduceIte]
          exact ⟨by trivial, by rw [elementAt_componentStart hopped, positionIs]⟩
        | false =>
          have elementStatic : element.isDynamic = false := by simpa [AbiType.isDynamic] using arrayDynamic
          simp only [arrayDynamic, Bool.false_eq_true, ↓reduceIte] at walked
          obtain ⟨-, positionIs, -⟩ := AbiType.locate_enter (middle := base) inRange stands
            (by simp [arrayDynamic, resolveHops_enter])
          simp only [arrayDynamic, Bool.false_and, enter, Bool.false_eq_true, ↓reduceIte] at positionIs
          apply rest walked inRange _ resolved
          simp only [Bool.false_eq_true, ↓reduceIte]
          rw [AbiType.componentStart_of_static elementStatic, AbiType.componentStart_of_static elementStatic,
            positionIs, advance_advance]
      · simp at walked
    | dynamicArray element =>
      simp only [AbiType.walk, Option.map_eq_some_iff, Prod.exists] at walked
      obtain ⟨restHops, restDelta, restEntered, restFound, elementWalked, same⟩ := walked
      simp only [Prod.mk.injEq] at same
      obtain ⟨rfl, rfl, rfl, rfl⟩ := same
      obtain ⟨middle, entry, resolvedRest⟩ := resolveHops_append.mp resolved
      have arrayDynamic : (AbiType.dynamicArray element).isDynamic = true := rfl
      obtain ⟨middleInRange, positionIs, settled⟩ :=
        AbiType.locate_enter inRange stands (by simpa [arrayDynamic] using entry)
      rw [settled arrayDynamic, advance_zero middleInRange] at positionIs
      obtain ⟨next, hopped, chainRest⟩ := resolveHops_cons.mp resolvedRest
      rw [Hop.apply_element_eq_ok, ArrayMeta.of_dynamicArray] at hopped
      simp only [↓reduceIte] at hopped
      obtain ⟨-, below, hopped⟩ := hopped
      subst positionIs
      simp only [AbiType.locate, below, ↓reduceIte]
      apply rest elementWalked (elementAt_lt hopped) _ chainRest
      cases elementDynamic : element.isDynamic with
      | true => exact ⟨by trivial, (elementAt_componentStart hopped).symm⟩
      | false =>
        simp only [Bool.false_eq_true, ↓reduceIte]
        rw [AbiType.componentStart_of_static elementDynamic, AbiType.componentStart_of_static elementDynamic,
          advance_zero (elementAt_lt hopped), elementAt_componentStart hopped,
          AbiType.componentStart_of_static elementDynamic]

/-- A walk whose hops stop at a fixed index past a dynamic array's length leaves the value: `locate` finds nothing
at the path. -/
theorem AbiType.locate_walk_fault {data : Bytes} {path : Path} :
    ∀ {abiType : AbiType} {delta : Nat} {entered : Bool} {hops : List Hop} {finalDelta : Nat} {finalEntered : Bool}
      {found : AbiType} {base position : Nat},
    abiType.walk path delta entered = some (hops, finalDelta, finalEntered, found) → base < 2 ^ 256 →
    (if entered then delta = 0 ∧ position = base
      else position = abiType.componentStart data base (advance base delta)) →
    resolveHops data hops base = .error .arrayIndexOutOfBounds →
    abiType.locate data position path = none := by
  induction path with
  | nil =>
    intro abiType delta entered hops finalDelta finalEntered found base position walked inRange stands faulted
    simp only [AbiType.walk, Option.some.injEq, Prod.mk.injEq] at walked
    obtain ⟨rfl, -, -, -⟩ := walked
    simp [resolveHops, pure, Except.pure] at faulted
  | cons step steps rest =>
    intro abiType delta entered hops finalDelta finalEntered found base position walked inRange stands faulted
    cases abiType with
    | word | bytes | string => simp [AbiType.walk] at walked
    | tuple fields =>
      simp only [AbiType.walk] at walked
      cases fieldAt : fields[step]? with
      | none => simp [fieldAt] at walked
      | some field =>
        simp only [fieldAt, Option.map_eq_some_iff, Prod.exists] at walked
        obtain ⟨restHops, restDelta, restEntered, restFound, fieldWalked, same⟩ := walked
        simp only [Prod.mk.injEq] at same
        obtain ⟨rfl, rfl, rfl, rfl⟩ := same
        cases entry : resolveHops data (enter ((AbiType.tuple fields).isDynamic && !entered) delta).1 base with
        | error fault =>
          rw [resolveHops_append_of_error entry] at faulted
          cases faulted
          exact absurd entry resolveHops_enter_ne_arrayIndex
        | ok middle =>
          rw [resolveHops_append_of_ok entry] at faulted
          obtain ⟨middleInRange, positionIs, settled⟩ := AbiType.locate_enter inRange stands entry
          simp only [AbiType.locate, fieldAt]
          apply rest fieldWalked middleInRange _ faulted
          simpa using AbiType.componentStart_field fieldAt middleInRange positionIs settled
    | staticArray element length =>
      simp only [AbiType.walk] at walked
      split at walked
      · rename_i below
        simp only [AbiType.locate, below, ↓reduceIte]
        cases arrayDynamic : (AbiType.staticArray element length).isDynamic with
        | true =>
          have elementDynamic : element.isDynamic = true := by simpa [AbiType.isDynamic] using arrayDynamic
          simp only [arrayDynamic, ↓reduceIte, Option.map_eq_some_iff, Prod.exists] at walked
          obtain ⟨restHops, restDelta, restEntered, restFound, elementWalked, same⟩ := walked
          simp only [Prod.mk.injEq] at same
          obtain ⟨rfl, rfl, rfl, rfl⟩ := same
          cases entry : resolveHops data (enter (!entered) delta).1 base with
          | error fault =>
            rw [resolveHops_append_of_error entry] at faulted
            cases faulted
            exact absurd entry resolveHops_enter_ne_arrayIndex
          | ok middle =>
            rw [resolveHops_append_of_ok entry] at faulted
            obtain ⟨middleInRange, positionIs, settled⟩ :=
              AbiType.locate_enter inRange stands (by simpa [arrayDynamic] using entry)
            rw [settled arrayDynamic, advance_zero middleInRange] at positionIs
            cases hopped : Hop.apply data middle (.element step (.of element false)) with
            | error fault =>
              rw [resolveHops_cons_of_error hopped] at faulted
              cases faulted
              simp [Hop.apply_element_eq_arrayIndex, ArrayMeta.of_dynamicArray] at hopped
            | ok next =>
              rw [resolveHops_cons_of_ok hopped] at faulted
              rw [Hop.apply_element_eq_ok, ArrayMeta.of_dynamicArray] at hopped
              simp only [Bool.false_eq_true, ↓reduceIte] at hopped
              apply rest elementWalked (elementAt_lt hopped) _ faulted
              simp only [elementDynamic, ↓reduceIte]
              exact ⟨by trivial, by rw [elementAt_componentStart hopped, positionIs]⟩
        | false =>
          have elementStatic : element.isDynamic = false := by simpa [AbiType.isDynamic] using arrayDynamic
          simp only [arrayDynamic, Bool.false_eq_true, ↓reduceIte] at walked
          obtain ⟨-, positionIs, -⟩ := AbiType.locate_enter (middle := base) inRange stands
            (by simp [arrayDynamic, resolveHops_enter])
          simp only [arrayDynamic, Bool.false_and, enter, Bool.false_eq_true, ↓reduceIte] at positionIs
          apply rest walked inRange _ faulted
          simp only [Bool.false_eq_true, ↓reduceIte]
          rw [AbiType.componentStart_of_static elementStatic, AbiType.componentStart_of_static elementStatic,
            positionIs, advance_advance]
      · simp at walked
    | dynamicArray element =>
      simp only [AbiType.walk, Option.map_eq_some_iff, Prod.exists] at walked
      obtain ⟨restHops, restDelta, restEntered, restFound, elementWalked, same⟩ := walked
      simp only [Prod.mk.injEq] at same
      obtain ⟨rfl, rfl, rfl, rfl⟩ := same
      have arrayDynamic : (AbiType.dynamicArray element).isDynamic = true := rfl
      cases entry : resolveHops data (enter (!entered) delta).1 base with
      | error fault =>
        rw [resolveHops_append_of_error entry] at faulted
        cases faulted
        exact absurd entry resolveHops_enter_ne_arrayIndex
      | ok middle =>
        rw [resolveHops_append_of_ok entry] at faulted
        obtain ⟨middleInRange, positionIs, settled⟩ :=
          AbiType.locate_enter inRange stands (by simpa [arrayDynamic] using entry)
        rw [settled arrayDynamic, advance_zero middleInRange] at positionIs
        subst positionIs
        cases hopped : Hop.apply data position (.element step (.of element true)) with
        | error fault =>
          rw [resolveHops_cons_of_error hopped] at faulted
          cases faulted
          obtain ⟨-, -, beyond⟩ := Hop.apply_element_eq_arrayIndex.mp hopped
          simp [AbiType.locate, beyond]
        | ok next =>
          rw [resolveHops_cons_of_ok hopped] at faulted
          rw [Hop.apply_element_eq_ok, ArrayMeta.of_dynamicArray] at hopped
          simp only [↓reduceIte] at hopped
          obtain ⟨-, below, hopped⟩ := hopped
          simp only [AbiType.locate, below, ↓reduceIte]
          apply rest elementWalked (elementAt_lt hopped) _ faulted
          cases elementDynamic : element.isDynamic with
          | true => exact ⟨by trivial, (elementAt_componentStart hopped).symm⟩
          | false =>
            simp only [Bool.false_eq_true, ↓reduceIte]
            rw [AbiType.componentStart_of_static elementDynamic, AbiType.componentStart_of_static elementDynamic,
              advance_zero (elementAt_lt hopped), elementAt_componentStart hopped,
              AbiType.componentStart_of_static elementDynamic]

/-- Theorem 3: wherever a compiled hint resolves, on any calldata, it ends where `decodeSolc` places the value at the
path. -/
theorem AbiType.locate_compile? {abiType : AbiType} {path : Path} {hint : Hint}
    (compiled : abiType.compile? path = some hint) {data : Bytes} {start offset : Nat} (inRange : start < 2 ^ 256)
    (resolved : hint.resolve data start = .ok offset) :
    abiType.locate data start path = some (hint.target, offset) := by
  simp only [AbiType.compile?, Option.map_eq_some_iff, Prod.exists] at compiled
  obtain ⟨hops, delta, entered, target, walked, rfl⟩ := compiled
  obtain ⟨base, chain, rfl⟩ := Except.map_eq_ok.mp resolved
  obtain ⟨middle, walkedChain, entry⟩ := resolveHops_append.mp chain
  obtain ⟨position, located, middleInRange, stands⟩ :=
    AbiType.locate_walk (position := start) walked inRange (by simp) walkedChain
  obtain ⟨-, positionIs, -⟩ := AbiType.locate_enter middleInRange stands entry
  rw [located, positionIs]

/-- Theorem 3 as values: what the enforcer reads at the resolved target is what `decodeSolc` decodes at the path. -/
theorem AbiType.decodeSolc_at_compile? {abiType : AbiType} {path : Path} {hint : Hint}
    (compiled : abiType.compile? path = some hint) {data : Bytes} {start offset : Nat} (inRange : start < 2 ^ 256)
    (resolved : hint.resolve data start = .ok offset) :
    (abiType.decodeSolc data start).at path = some (hint.target.decodeSolc data offset) := by
  rw [AbiType.decodeSolc_at abiType data inRange, AbiType.locate_compile? compiled inRange resolved]
  rfl

/-- Theorem 3, a fault: wherever a compiled hint stops at a fixed index past a dynamic array's length, on any
calldata, `decodeSolc` places no value at the path. -/
theorem AbiType.locate_compile?_fault {abiType : AbiType} {path : Path} {hint : Hint}
    (compiled : abiType.compile? path = some hint) {data : Bytes} {start : Nat} (inRange : start < 2 ^ 256)
    (faulted : hint.resolve data start = .error .arrayIndexOutOfBounds) : abiType.locate data start path = none := by
  simp only [AbiType.compile?, Option.map_eq_some_iff, Prod.exists] at compiled
  obtain ⟨hops, delta, entered, target, walked, rfl⟩ := compiled
  have chain := Except.map_eq_error.mp faulted
  cases walkedChain : resolveHops data hops start with
  | error fault =>
    rw [resolveHops_append_of_error walkedChain] at chain
    cases chain
    exact AbiType.locate_walk_fault (position := start) walked inRange (by simp) walkedChain
  | ok middle =>
    rw [resolveHops_append_of_ok walkedChain] at chain
    exact absurd chain resolveHops_enter_ne_arrayIndex

/-- Theorem 3 as values, a fault: a test whose hint stops at a fixed index past a dynamic array's length reads no
value. -/
theorem AbiType.decodeSolc_at_compile?_fault {abiType : AbiType} {path : Path} {hint : Hint}
    (compiled : abiType.compile? path = some hint) {data : Bytes} {start : Nat} (inRange : start < 2 ^ 256)
    (faulted : hint.resolve data start = .error .arrayIndexOutOfBounds) :
    (abiType.decodeSolc data start).at path = none := by
  rw [AbiType.decodeSolc_at abiType data inRange, AbiType.locate_compile?_fault compiled inRange faulted]
  rfl

theorem decodeElements_length (decodeElement : Nat → Value) (element : AbiType) (data : Bytes) (base head count : Nat) :
    (decodeElements decodeElement element data base head count).length = count := by
  induction count generalizing head with
  | zero => rfl
  | succ count rest => simp [decodeElements, rest]

theorem LoopHint.resolveArray_eq_ok {loop : LoopHint} {data : Bytes} {start elements count : Nat} :
    loop.resolveArray data start = .ok (elements, count) ↔
      ∃ base, resolveHops data loop.hops start = .ok base ∧
        if loop.count = 0 then
          advance base loop.arrayDelta + WORD_SIZE ≤ data.length ∧
            count = (readWord data (advance base loop.arrayDelta)).toNat ∧
            elements = advance (advance base loop.arrayDelta) WORD_SIZE
        else elements = advance base loop.arrayDelta ∧ count = loop.count := by
  unfold LoopHint.resolveArray
  rw [Except.bind_eq_ok]
  apply exists_congr
  intro base
  apply and_congr_right
  intro _
  split
  · rw [Except.bind_eq_ok]
    simp only [loadWord_eq_ok, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq]
    constructor
    · rintro ⟨word, ⟨within, rfl⟩, rfl, rfl⟩
      exact ⟨within, rfl, rfl⟩
    · rintro ⟨within, rfl, rfl⟩
      exact ⟨_, ⟨within, rfl⟩, rfl, rfl⟩
  · simp [pure, Except.pure, eq_comm]

/-- A loop's hint yields the array's elements as `decodeSolc` reads them: as many as the array at the path holds,
each starting where `decodeSolc` reads it. Theorem 3 from each element follows. -/
theorem AbiType.decodeSolc_at_compileLoop? {abiType : AbiType} {arrayPath : Path} {loop : LoopHint}
    (compiled : abiType.compileLoop? arrayPath = some loop) {data : Bytes} {start elements count : Nat}
    (inRange : start < 2 ^ 256) (resolved : loop.resolveArray data start = .ok (elements, count)) :
    ∃ items, (abiType.decodeSolc data start).at arrayPath = some (.list items) ∧ items.length = count ∧
      ∀ {position elementStart : Nat}, position < count →
        loop.resolveElement data elements position = .ok elementStart →
        items[position]? = some (loop.element.decodeSolc data elementStart) := by
  cases walked : abiType.walk arrayPath 0 true with
  | none => simp [AbiType.compileLoop?, walked] at compiled
  | some walk =>
    obtain ⟨hops, delta, entered, array⟩ := walk
    cases array with
    | staticArray element length =>
      simp only [AbiType.compileLoop?, walked] at compiled
      split at compiled
      · rename_i nonempty
        simp only [Option.some.injEq] at compiled
        subst compiled
        obtain ⟨base, chain, frame⟩ := LoopHint.resolveArray_eq_ok.mp resolved
        simp only [Nat.pos_iff_ne_zero.mp nonempty, ↓reduceIte] at frame
        obtain ⟨rfl, rfl⟩ := frame
        obtain ⟨middle, walkedChain, entry⟩ := resolveHops_append.mp chain
        obtain ⟨position, located, middleInRange, stands⟩ :=
          AbiType.locate_walk (position := start) walked inRange (by simp) walkedChain
        obtain ⟨-, positionIs, -⟩ := AbiType.locate_enter middleInRange stands entry
        rw [AbiType.decodeSolc_at abiType data inRange, located, positionIs]
        refine ⟨_, rfl, decodeElements_length _ _ _ _ _ _, ?_⟩
        intro elementIndex elementStart below elementResolved
        rw [decodeElements_getElem? _ _ _ _ (advance_lt _ _), elementAt_componentStart elementResolved]
        simp [below]
      · simp at compiled
    | dynamicArray element =>
      simp only [AbiType.compileLoop?, walked, Option.some.injEq] at compiled
      subst compiled
      obtain ⟨base, chain, frame⟩ := LoopHint.resolveArray_eq_ok.mp resolved
      simp only [↓reduceIte] at frame
      obtain ⟨-, rfl, rfl⟩ := frame
      obtain ⟨middle, walkedChain, entry⟩ := resolveHops_append.mp chain
      obtain ⟨position, located, middleInRange, stands⟩ :=
        AbiType.locate_walk (position := start) walked inRange (by simp) walkedChain
      obtain ⟨-, positionIs, -⟩ :=
        AbiType.locate_enter (abiType := .dynamicArray element) middleInRange stands
          (by simpa [AbiType.isDynamic] using entry)
      simp only [AbiType.isDynamic, Bool.true_and] at positionIs
      rw [AbiType.decodeSolc_at abiType data inRange, located, positionIs]
      refine ⟨_, rfl, decodeElements_length _ _ _ _ _ _, ?_⟩
      intro elementIndex elementStart below elementResolved
      rw [decodeElements_getElem? _ _ _ _ (advance_lt _ _), elementAt_componentStart elementResolved]
      simp [below]
    | word | bytes | string | tuple => simp [AbiType.compileLoop?, walked] at compiled

/-- A loop's hint stops at a fixed index past a dynamic array's length only within its hops: the frame reads no index.
-/
theorem LoopHint.resolveHops_of_resolveArray {loop : LoopHint} {data : Bytes} {start : Nat}
    (faulted : loop.resolveArray data start = .error .arrayIndexOutOfBounds) :
    resolveHops data loop.hops start = .error .arrayIndexOutOfBounds := by
  unfold LoopHint.resolveArray at faulted
  cases chain : resolveHops data loop.hops start with
  | error fault => simpa [chain, bind, Except.bind] using faulted
  | ok base =>
    simp only [chain, bind, Except.bind] at faulted
    split at faulted
    · by_cases within : advance base loop.arrayDelta + WORD_SIZE ≤ data.length
      · simp [loadWord, within, pure, Except.pure] at faulted
      · simp [loadWord, within] at faulted
    · simp [pure, Except.pure] at faulted

/-- Theorem 3 from a loop, a fault: wherever a loop's hint stops at a fixed index past a dynamic array's length, on
any calldata, `decodeSolc` places no value at the array path. -/
theorem AbiType.decodeSolc_at_compileLoop?_fault {abiType : AbiType} {arrayPath : Path} {loop : LoopHint}
    (compiled : abiType.compileLoop? arrayPath = some loop) {data : Bytes} {start : Nat} (inRange : start < 2 ^ 256)
    (faulted : loop.resolveArray data start = .error .arrayIndexOutOfBounds) :
    (abiType.decodeSolc data start).at arrayPath = none := by
  have chain := LoopHint.resolveHops_of_resolveArray faulted
  rw [AbiType.decodeSolc_at abiType data inRange]
  cases walked : abiType.walk arrayPath 0 true with
  | none => simp [AbiType.compileLoop?, walked] at compiled
  | some walk =>
    obtain ⟨hops, delta, entered, arrayType⟩ := walk
    have located : abiType.locate data start arrayPath = none := by
      cases walkedChain : resolveHops data hops start with
      | error fault =>
        cases arrayType with
        | staticArray element length =>
          simp only [AbiType.compileLoop?, walked] at compiled
          split at compiled
          · simp only [Option.some.injEq] at compiled
            subst compiled
            rw [resolveHops_append_of_error walkedChain] at chain
            cases chain
            exact AbiType.locate_walk_fault (position := start) walked inRange (by simp) walkedChain
          · simp at compiled
        | dynamicArray element =>
          simp only [AbiType.compileLoop?, walked, Option.some.injEq] at compiled
          subst compiled
          rw [resolveHops_append_of_error walkedChain] at chain
          cases chain
          exact AbiType.locate_walk_fault (position := start) walked inRange (by simp) walkedChain
        | word | bytes | string | tuple => simp [AbiType.compileLoop?, walked] at compiled
      | ok middle =>
        cases arrayType with
        | staticArray element length =>
          simp only [AbiType.compileLoop?, walked] at compiled
          split at compiled
          · simp only [Option.some.injEq] at compiled
            subst compiled
            rw [resolveHops_append_of_ok walkedChain] at chain
            exact absurd chain resolveHops_enter_ne_arrayIndex
          · simp at compiled
        | dynamicArray element =>
          simp only [AbiType.compileLoop?, walked, Option.some.injEq] at compiled
          subst compiled
          rw [resolveHops_append_of_ok walkedChain] at chain
          exact absurd chain resolveHops_enter_ne_arrayIndex
        | word | bytes | string | tuple => simp [AbiType.compileLoop?, walked] at compiled
    rw [located]
    rfl

/-! ## Canonical layout -/

/-- Component `index` among the heads and tails: a static one's encoding among the heads, past the heads before it; a
dynamic one's offset word there, pointing `tail` bytes into the tails, where its encoding lies. -/
theorem headsAndTails_component {components : List (Bool × Bytes)} {index : Nat} {dynamic : Bool} {encoding : Bytes}
    (componentAt : components[index]? = some (dynamic, encoding)) (tailOffset : Nat) :
    if dynamic then ∃ tail,
      (∃ before after,
        (headsAndTails components tailOffset).1 = before ++ beBytes WORD_SIZE (tailOffset + tail) ++ after ∧
          before.length = ((components.take index).map headLength).sum) ∧
      ∃ before after, (headsAndTails components tailOffset).2 = before ++ encoding ++ after ∧ before.length = tail
    else ∃ before after, (headsAndTails components tailOffset).1 = before ++ encoding ++ after ∧
      before.length = ((components.take index).map headLength).sum := by
  induction components generalizing index tailOffset with
  | nil => simp at componentAt
  | cons component components rest =>
    obtain ⟨firstDynamic, firstEncoding⟩ := component
    cases index with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq, Prod.mk.injEq] at componentAt
      obtain ⟨rfl, rfl⟩ := componentAt
      cases firstDynamic
      · exact ⟨[], (headsAndTails components tailOffset).1, by simp [headsAndTails], rfl⟩
      · exact ⟨0, ⟨[], (headsAndTails components (tailOffset + firstEncoding.length)).1, by simp [headsAndTails], rfl⟩,
          [], (headsAndTails components (tailOffset + firstEncoding.length)).2, by simp [headsAndTails], rfl⟩
    | succ index =>
      simp only [List.getElem?_cons_succ] at componentAt
      have shifted := rest componentAt
      simp only [List.take_succ_cons, List.map_cons, List.sum_cons]
      cases firstDynamic
      · have firstLength : headLength (false, firstEncoding) = firstEncoding.length := rfl
        simp only [headsAndTails, Bool.false_eq_true, ↓reduceIte, firstLength]
        cases dynamic
        · obtain ⟨before, after, heads, position⟩ := shifted tailOffset
          exact ⟨firstEncoding ++ before, after, by simp [heads], by simp [position]⟩
        · obtain ⟨tail, ⟨before, after, heads, position⟩, tails⟩ := shifted tailOffset
          exact ⟨tail, ⟨firstEncoding ++ before, after, by simp [heads], by simp [position]⟩, tails⟩
      · have firstLength : headLength (true, firstEncoding) = WORD_SIZE := rfl
        simp only [headsAndTails, ↓reduceIte, firstLength]
        cases dynamic
        · obtain ⟨before, after, heads, position⟩ := shifted (tailOffset + firstEncoding.length)
          exact ⟨beBytes WORD_SIZE tailOffset ++ before, after, by simp [heads],
            by simp [position, beBytes_length]⟩
        · obtain ⟨tail, ⟨before, after, heads, position⟩, tailBefore, tailAfter, tails, tailPosition⟩ :=
            shifted (tailOffset + firstEncoding.length)
          refine ⟨firstEncoding.length + tail, ⟨beBytes WORD_SIZE tailOffset ++ before, after, ?_, ?_⟩,
            firstEncoding ++ tailBefore, tailAfter, by simp [tails], by simp [tailPosition]⟩
          · simp [heads, Nat.add_assoc]
          · simp [position, beBytes_length]

theorem AbiType.encodeComponents_getElem? {types : List AbiType} {values : List Value} {index : Nat}
    {abiType : AbiType} {value : Value} (typeAt : types[index]? = some abiType)
    (valueAt : values[index]? = some value) :
    (AbiType.encodeComponents types values)[index]? = some (abiType.isDynamic, abiType.encode value) := by
  induction types generalizing values index with
  | nil => simp at typeAt
  | cons first types rest =>
    cases values with
    | nil => simp at valueAt
    | cons firstValue values =>
      cases index with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at typeAt valueAt
        subst typeAt valueAt
        simp [AbiType.encodeComponents]
      | succ index =>
        simp only [List.getElem?_cons_succ] at typeAt valueAt
        simp [AbiType.encodeComponents, rest typeAt valueAt]

theorem AbiType.admits_of_admitsAll {types : List AbiType} {values : List Value}
    (admitted : AbiType.admitsAll types values = true) {index : Nat} {abiType : AbiType} {value : Value}
    (typeAt : types[index]? = some abiType) (valueAt : values[index]? = some value) : abiType.admits value = true := by
  induction types generalizing values index with
  | nil => simp at typeAt
  | cons first types rest =>
    cases values with
    | nil => simp at valueAt
    | cons firstValue values =>
      simp only [AbiType.admitsAll, Bool.and_eq_true] at admitted
      cases index with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at typeAt valueAt
        subst typeAt valueAt
        exact admitted.1
      | succ index => exact rest admitted.2 typeAt valueAt

theorem AbiType.exists_value_of_admitsAll {types : List AbiType} {values : List Value}
    (admitted : AbiType.admitsAll types values = true) {index : Nat} {abiType : AbiType}
    (typeAt : types[index]? = some abiType) : ∃ value, values[index]? = some value := by
  induction types generalizing values index with
  | nil => simp at typeAt
  | cons first types rest =>
    cases values with
    | nil => simp [AbiType.admitsAll] at admitted
    | cons firstValue values =>
      simp only [AbiType.admitsAll, Bool.and_eq_true] at admitted
      cases index with
      | zero => exact ⟨firstValue, rfl⟩
      | succ index => exact rest admitted.2 typeAt

theorem AbiType.length_eq_of_admitsAll {types : List AbiType} {values : List Value}
    (admitted : AbiType.admitsAll types values = true) : types.length = values.length := by
  induction types generalizing values with
  | nil => cases values <;> simp_all [AbiType.admitsAll]
  | cons first types rest =>
    cases values with
    | nil => simp [AbiType.admitsAll] at admitted
    | cons firstValue values =>
      simp only [AbiType.admitsAll, Bool.and_eq_true] at admitted
      simp [rest admitted.2]

/-- In the encoding of admitted components, component `index`: a static one's encoding past the heads before it; a
dynamic one's offset word there, holding where its encoding lies. -/
theorem AbiType.joinComponents_component {types : List AbiType} {values : List Value}
    (admitted : AbiType.admitsAll types values = true) {index : Nat} {abiType : AbiType} {value : Value}
    (typeAt : types[index]? = some abiType) (valueAt : values[index]? = some value) :
    if abiType.isDynamic then ∃ tail,
      (∃ before after, joinComponents (AbiType.encodeComponents types values) =
          before ++ beBytes WORD_SIZE tail ++ after ∧ before.length = ((types.take index).map AbiType.headSize).sum) ∧
      ∃ before after, joinComponents (AbiType.encodeComponents types values) =
          before ++ abiType.encode value ++ after ∧ before.length = tail
    else ∃ before after, joinComponents (AbiType.encodeComponents types values) =
        before ++ abiType.encode value ++ after ∧ before.length = ((types.take index).map AbiType.headSize).sum := by
  have heads : ((AbiType.encodeComponents types values).take index).map headLength =
      (types.take index).map AbiType.headSize := by
    rw [List.map_take, List.map_take, AbiType.map_headLength_encodeComponents
      (fun abiType _ _ admitted => abiType.headLength_encode admitted) admitted]
  have placed := headsAndTails_component (AbiType.encodeComponents_getElem? typeAt valueAt)
    ((AbiType.encodeComponents types values).map headLength).sum
  rw [heads] at placed
  unfold joinComponents
  split
  · rename_i dynamic
    simp only [dynamic, ↓reduceIte] at placed
    obtain ⟨tail, ⟨before, after, headsAre, position⟩, tailBefore, tailAfter, tailsAre, tailPosition⟩ := placed
    refine ⟨((AbiType.encodeComponents types values).map headLength).sum + tail,
      ⟨before, after ++ (headsAndTails (AbiType.encodeComponents types values)
        ((AbiType.encodeComponents types values).map headLength).sum).2, by simp [headsAre], position⟩,
      (headsAndTails (AbiType.encodeComponents types values)
        ((AbiType.encodeComponents types values).map headLength).sum).1 ++ tailBefore, tailAfter,
      by simp [tailsAre], by simp [tailPosition, headsAndTails_heads_length]⟩
  · rename_i static
    simp only [static, Bool.false_eq_true, ↓reduceIte] at placed
    obtain ⟨before, after, headsAre, position⟩ := placed
    exact ⟨before, after ++ (headsAndTails (AbiType.encodeComponents types values)
      ((AbiType.encodeComponents types values).map headLength).sum).2, by simp [headsAre], position⟩

/-- A piece placed within an encoding that is placed within the data is placed within the data. -/
theorem placed_trans {data encoding piece : Bytes} {position offset : Nat}
    (outer : ∃ before after, data = before ++ encoding ++ after ∧ before.length = position)
    (inner : ∃ before after, encoding = before ++ piece ++ after ∧ before.length = offset) :
    ∃ before after, data = before ++ piece ++ after ∧ before.length = position + offset := by
  obtain ⟨outerBefore, outerAfter, rfl, rfl⟩ := outer
  obtain ⟨innerBefore, innerAfter, rfl, rfl⟩ := inner
  exact ⟨outerBefore ++ innerBefore, innerAfter ++ outerAfter, by simp, by simp⟩

theorem placed_end {data piece : Bytes} {position : Nat}
    (placed : ∃ before after, data = before ++ piece ++ after ∧ before.length = position) :
    position + piece.length ≤ data.length := by
  obtain ⟨before, after, rfl, rfl⟩ := placed
  simp

/-- The word a placed offset word holds. -/
theorem readWord_placed {data : Bytes} (fits : data.length < 2 ^ 256) {position value : Nat}
    (placed : ∃ before after, data = before ++ beBytes WORD_SIZE value ++ after ∧ before.length = position)
    (valueFits : value < 2 ^ 256) : (readWord data position).toNat = value := by
  obtain ⟨before, after, rfl, rfl⟩ := placed
  exact toNat_readWord_beBytes before after valueFits

theorem sum_take_replicate (element : AbiType) {count index : Nat} (below : index ≤ count) :
    (((List.replicate count element).take index).map AbiType.headSize).sum = index * element.headSize := by
  simp [Nat.min_eq_left below]

/-- On canonical data, element `index` of an array resolves to where its encoding lies. -/
theorem elementAt_placed {element : AbiType} (dynamicArray : Bool) {items : List Value}
    (admitted : AbiType.admitsAll (List.replicate items.length element) items = true) {data : Bytes}
    (fits : data.length < 2 ^ 256) {elements : Nat}
    (placed : ∃ before after, data =
      before ++ joinComponents (AbiType.encodeComponents (List.replicate items.length element) items) ++ after ∧
        before.length = elements)
    {index : Nat} {item : Value} (itemAt : items[index]? = some item) :
    ∃ elementStart, (ArrayMeta.of element dynamicArray).elementAt data elements index = .ok elementStart ∧
      element.admits item = true ∧
      ∃ before after, data = before ++ element.encode item ++ after ∧ before.length = elementStart := by
  have below : index < items.length := (List.getElem?_eq_some_iff.mp itemAt).1
  have typeAt : (List.replicate items.length element)[index]? = some element := by simp [below]
  have elementAdmits := AbiType.admits_of_admitsAll admitted typeAt itemAt
  have layout := AbiType.joinComponents_component admitted typeAt itemAt
  rw [sum_take_replicate element (Nat.le_of_lt below)] at layout
  cases dynamic : element.isDynamic with
  | true =>
    simp only [dynamic, ↓reduceIte] at layout
    obtain ⟨tail, heads, tails⟩ := layout
    have headPlaced := placed_trans placed heads
    have elementPlaced := placed_trans placed tails
    have headEnd := placed_end headPlaced
    have elementEnd := placed_end elementPlaced
    simp only [beBytes_length] at headEnd
    have offset := readWord_placed fits headPlaced (by omega)
    refine ⟨elements + tail, ?_, elementAdmits, elementPlaced⟩
    rw [elementAt_eq_ok]
    simp only [dynamic, ↓reduceIte]
    rw [advance_of_lt (by omega), follow_eq_ok, offset, advance_of_lt (by omega)]
    exact ⟨headEnd, by omega, rfl⟩
  | false =>
    simp only [dynamic, Bool.false_eq_true, ↓reduceIte] at layout
    have elementPlaced := placed_trans placed layout
    have elementEnd := placed_end elementPlaced
    refine ⟨elements + index * element.headSize, ?_, elementAdmits, elementPlaced⟩
    rw [elementAt_eq_ok]
    simp only [dynamic, Bool.false_eq_true, ↓reduceIte]
    rw [advance_of_lt (by omega)]

/-- On canonical data, entering a node when needed resolves, and leaves the node `delta` past the new base with no
delta left for a dynamic node. -/
theorem AbiType.resolveHops_enter_placed {abiType : AbiType} {data : Bytes} (fits : data.length < 2 ^ 256)
    {entered : Bool} {delta base position : Nat} (inRange : base < 2 ^ 256) (inside : position ≤ data.length)
    (stands : if entered then delta = 0 ∧ position = base
      else if abiType.isDynamic then
        advance base delta + WORD_SIZE ≤ data.length ∧ base + (readWord data (advance base delta)).toNat = position
      else advance base delta = position) :
    ∃ middle, resolveHops data (enter (abiType.isDynamic && !entered) delta).1 base = .ok middle ∧
      middle < 2 ^ 256 ∧ position = advance middle (enter (abiType.isDynamic && !entered) delta).2 ∧
      (abiType.isDynamic = true → (enter (abiType.isDynamic && !entered) delta).2 = 0) := by
  cases entered with
  | true =>
    simp only [↓reduceIte] at stands
    obtain ⟨rfl, rfl⟩ := stands
    exact ⟨position, by simp [resolveHops_enter], inRange, by simp [enter, advance_zero inRange], by simp [enter]⟩
  | false =>
    cases dynamic : abiType.isDynamic with
    | true =>
      simp only [dynamic, Bool.false_eq_true, ↓reduceIte] at stands
      obtain ⟨headEnd, rfl⟩ := stands
      have positionInRange : base + (readWord data (advance base delta)).toNat < 2 ^ 256 := by omega
      refine ⟨base + (readWord data (advance base delta)).toNat, ?_, positionInRange, ?_, by simp [enter]⟩
      · simp only [resolveHops_enter, Bool.not_false, Bool.and_self, ↓reduceIte, follow_eq_ok]
        exact ⟨headEnd, inside, (advance_of_lt positionInRange).symm⟩
      · simp [enter, advance_zero positionInRange]
    | false =>
      simp only [dynamic, Bool.false_eq_true, ↓reduceIte] at stands
      exact ⟨base, by simp [resolveHops_enter], inRange, by simp [enter, stands], by simp⟩

/-- On canonical data, each step of the walk resolves, and keeps the chain where the component's encoding lies:
entered, at the base; otherwise its head `delta` past the base, holding for a dynamic component the offset from the base
to its encoding. Along a path the value does not hold, the hops stop at a fixed index past a dynamic array's length. -/
theorem AbiType.resolveHops_walk {data : Bytes} (fits : data.length < 2 ^ 256) {path : Path} :
    ∀ {abiType : AbiType} {delta : Nat} {entered : Bool} {hops : List Hop} {finalDelta : Nat} {finalEntered : Bool}
      {found : AbiType} {base position : Nat} {value : Value},
    abiType.walk path delta entered = some (hops, finalDelta, finalEntered, found) → base < 2 ^ 256 →
    abiType.admits value = true →
    (∃ before after, data = before ++ abiType.encode value ++ after ∧ before.length = position) →
    (if entered then delta = 0 ∧ position = base
      else if abiType.isDynamic then
        advance base delta + WORD_SIZE ≤ data.length ∧ base + (readWord data (advance base delta)).toNat = position
      else advance base delta = position) →
    match value.at path with
    | some targetValue =>
      ∃ finalBase finalPosition, resolveHops data hops base = .ok finalBase ∧ finalBase < 2 ^ 256 ∧
        found.admits targetValue = true ∧
        (∃ before after, data = before ++ found.encode targetValue ++ after ∧ before.length = finalPosition) ∧
        (if finalEntered then finalDelta = 0 ∧ finalPosition = finalBase
          else if found.isDynamic then
            advance finalBase finalDelta + WORD_SIZE ≤ data.length ∧
              finalBase + (readWord data (advance finalBase finalDelta)).toNat = finalPosition
          else advance finalBase finalDelta = finalPosition)
    | none => resolveHops data hops base = .error .arrayIndexOutOfBounds := by
  induction path with
  | nil =>
    intro abiType delta entered hops finalDelta finalEntered found base position value walked inRange admitted placed
      stands
    simp only [AbiType.walk, Option.some.injEq, Prod.mk.injEq] at walked
    obtain ⟨rfl, rfl, rfl, rfl⟩ := walked
    simp only [Value.at]
    exact ⟨base, position, by simp [resolveHops_nil], inRange, admitted, placed, stands⟩
  | cons step steps rest =>
    intro abiType delta entered hops finalDelta finalEntered found base position value walked inRange admitted placed
      stands
    have inside := placed_end placed
    cases abiType with
    | word | bytes | string => simp [AbiType.walk] at walked
    | tuple fields =>
      cases value with
      | word | bytes => simp [AbiType.admits] at admitted
      | list items =>
      simp only [AbiType.admits] at admitted
      simp only [AbiType.walk] at walked
      cases fieldAt : fields[step]? with
      | none => simp [fieldAt] at walked
      | some field =>
        simp only [fieldAt, Option.map_eq_some_iff, Prod.exists] at walked
        obtain ⟨restHops, restDelta, restEntered, restFound, fieldWalked, same⟩ := walked
        simp only [Prod.mk.injEq] at same
        obtain ⟨rfl, rfl, rfl, rfl⟩ := same
        obtain ⟨item, itemAt⟩ := AbiType.exists_value_of_admitsAll admitted fieldAt
        simp only [Value.at, itemAt, Option.bind_some]
        obtain ⟨middle, entry, middleInRange, positionIs, settled⟩ :=
          AbiType.resolveHops_enter_placed fits inRange (by omega) stands
        rw [resolveHops_append_of_ok entry]
        have layout := AbiType.joinComponents_component admitted fieldAt itemAt
        simp only [AbiType.encode] at placed
        have fieldAdmits := AbiType.admits_of_admitsAll admitted fieldAt itemAt
        cases fieldDynamic : field.isDynamic with
        | true =>
          have tupleDynamic : (AbiType.tuple fields).isDynamic = true := by
            cases tupleIs : (AbiType.tuple fields).isDynamic with
            | true => rfl
            | false => simp [AbiType.isDynamic_of_field fieldAt tupleIs] at fieldDynamic
          rw [settled tupleDynamic, advance_zero middleInRange] at positionIs
          subst positionIs
          simp only [fieldDynamic, ↓reduceIte] at layout
          obtain ⟨tail, heads, tails⟩ := layout
          have headPlaced := placed_trans placed heads
          have fieldPlaced := placed_trans placed tails
          have headEnd := placed_end headPlaced
          have fieldEnd := placed_end fieldPlaced
          simp only [beBytes_length] at headEnd
          exact rest fieldWalked middleInRange fieldAdmits fieldPlaced
            (by
              simp only [Bool.false_eq_true, ↓reduceIte, fieldDynamic, settled tupleDynamic, Nat.zero_add]
              rw [advance_of_lt (by omega), readWord_placed fits headPlaced (by omega)]
              exact ⟨headEnd, rfl⟩)
        | false =>
          simp only [fieldDynamic, Bool.false_eq_true, ↓reduceIte] at layout
          have fieldPlaced := placed_trans placed layout
          have fieldEnd := placed_end fieldPlaced
          exact rest fieldWalked middleInRange fieldAdmits fieldPlaced
            (by
              simp only [Bool.false_eq_true, ↓reduceIte, fieldDynamic]
              rw [← advance_advance, ← positionIs, advance_of_lt (by omega)])
    | staticArray element length =>
      cases value with
      | word | bytes => simp [AbiType.admits] at admitted
      | list items =>
      simp only [AbiType.admits] at admitted
      have lengthIs := AbiType.length_eq_of_admitsAll admitted
      rw [List.length_replicate] at lengthIs
      subst lengthIs
      simp only [AbiType.encode] at placed
      simp only [AbiType.walk] at walked
      split at walked
      · rename_i below
        have itemAt : items[step]? = some items[step] := List.getElem?_eq_getElem below
        simp only [Value.at, itemAt, Option.bind_some]
        cases arrayDynamic : (AbiType.staticArray element items.length).isDynamic with
        | true =>
          have elementDynamic : element.isDynamic = true := by simpa [AbiType.isDynamic] using arrayDynamic
          simp only [arrayDynamic, ↓reduceIte, Option.map_eq_some_iff, Prod.exists] at walked
          obtain ⟨restHops, restDelta, restEntered, restFound, elementWalked, same⟩ := walked
          simp only [Prod.mk.injEq] at same
          obtain ⟨rfl, rfl, rfl, rfl⟩ := same
          obtain ⟨middle, entry, middleInRange, positionIs, settled⟩ :=
            AbiType.resolveHops_enter_placed fits inRange (by omega) stands
          rw [settled arrayDynamic, advance_zero middleInRange] at positionIs
          subst positionIs
          obtain ⟨elementStart, resolvedElement, elementAdmits, elementPlaced⟩ :=
            elementAt_placed false admitted fits placed itemAt
          have hopped : Hop.apply data position (.element step (.of element false)) = .ok elementStart := by
            simpa [Hop.apply_element_eq_ok, ArrayMeta.of_dynamicArray] using resolvedElement
          rw [resolveHops_append_of_ok (by simpa [arrayDynamic] using entry), resolveHops_cons_of_ok hopped]
          exact rest elementWalked (elementAt_lt resolvedElement) elementAdmits elementPlaced (by simp [elementDynamic])
        | false =>
          have elementStatic : element.isDynamic = false := by simpa [AbiType.isDynamic] using arrayDynamic
          simp only [arrayDynamic, Bool.false_eq_true, ↓reduceIte] at walked
          obtain ⟨middle, entry, -, positionIs, -⟩ :=
            AbiType.resolveHops_enter_placed fits inRange (by omega) stands
          simp only [AbiType.isDynamic, elementStatic, Bool.false_and, enter, Bool.false_eq_true, ↓reduceIte,
            resolveHops_nil] at entry positionIs
          subst entry
          have typeAt : (List.replicate items.length element)[step]? = some element := by simp [below]
          have layout := AbiType.joinComponents_component admitted typeAt itemAt
          simp only [elementStatic, Bool.false_eq_true, ↓reduceIte] at layout
          rw [sum_take_replicate element (Nat.le_of_lt below)] at layout
          have elementPlaced := placed_trans placed layout
          have elementEnd := placed_end elementPlaced
          exact rest walked inRange (AbiType.admits_of_admitsAll admitted typeAt itemAt) elementPlaced
            (by
              simp only [Bool.false_eq_true, ↓reduceIte, elementStatic]
              rw [← advance_advance, ← positionIs, advance_of_lt (by omega)])
      · simp at walked
    | dynamicArray element =>
      cases value with
      | word | bytes => simp [AbiType.admits] at admitted
      | list items =>
      simp only [AbiType.admits, Bool.and_eq_true, decide_eq_true_eq] at admitted
      simp only [AbiType.walk, Option.map_eq_some_iff, Prod.exists] at walked
      obtain ⟨restHops, restDelta, restEntered, restFound, elementWalked, same⟩ := walked
      simp only [Prod.mk.injEq] at same
      obtain ⟨rfl, rfl, rfl, rfl⟩ := same
      have arrayDynamic : (AbiType.dynamicArray element).isDynamic = true := rfl
      obtain ⟨middle, entry, middleInRange, positionIs, settled⟩ :=
        AbiType.resolveHops_enter_placed fits inRange (by omega) stands
      rw [settled arrayDynamic, advance_zero middleInRange] at positionIs
      subst positionIs
      rw [resolveHops_append_of_ok (by simpa [arrayDynamic] using entry)]
      simp only [AbiType.encode] at placed
      have lengthPlaced := placed_trans placed (piece := beBytes WORD_SIZE items.length) (offset := 0)
        ⟨[], joinComponents (AbiType.encodeComponents (List.replicate items.length element) items), by simp, rfl⟩
      have elementsPlaced := placed_trans placed
        (piece := joinComponents (AbiType.encodeComponents (List.replicate items.length element) items))
        ⟨beBytes WORD_SIZE items.length, [], by simp, rfl⟩
      have lengthEnd := placed_end lengthPlaced
      simp only [beBytes_length, Nat.add_zero] at lengthEnd lengthPlaced elementsPlaced
      have lengthRead := readWord_placed fits lengthPlaced admitted.1
      cases itemAt : items[step]? with
      | none =>
        simp only [Value.at, itemAt, Option.bind_none]
        have beyond : items.length ≤ step := List.getElem?_eq_none_iff.mp itemAt
        rw [resolveHops_cons_of_error (Hop.apply_element_eq_arrayIndex.mpr ⟨rfl, lengthEnd, by omega⟩)]
      | some item =>
        simp only [Value.at, itemAt, Option.bind_some]
        have below : step < items.length := (List.getElem?_eq_some_iff.mp itemAt).1
        obtain ⟨elementStart, resolvedElement, elementAdmits, elementPlaced⟩ :=
          elementAt_placed true admitted.2 fits elementsPlaced itemAt
        have hopped : Hop.apply data position (.element step (.of element true)) = .ok elementStart := by
          rw [Hop.apply_element_eq_ok, ArrayMeta.of_dynamicArray]
          simp only [↓reduceIte]
          rw [lengthRead, advance_of_lt (by unfold WORD_SIZE at *; omega)]
          exact ⟨lengthEnd, below, resolvedElement⟩
        rw [resolveHops_cons_of_ok hopped]
        exact rest elementWalked (elementAt_lt resolvedElement) elementAdmits elementPlaced
          (by
            cases elementDynamic : element.isDynamic
            · simp [advance_zero (elementAt_lt resolvedElement)]
            · simp)

/-! ## Theorem 24 -/

/-- Theorem 24: on canonical calldata, the compiled hint of a path the value holds resolves to where that value's
canonical encoding lies. -/
theorem AbiType.resolve_compile?_ok {abiType : AbiType} {data : Bytes} {start : Nat} {value : Value}
    (canonical : abiType.decodeStrict data start = some value) {path : Path} {targetValue : Value}
    (present : value.at path = some targetValue) {hint : Hint} (compiled : abiType.compile? path = some hint) :
    ∃ offset, hint.resolve data start = .ok offset ∧ hint.target.decodeStrict data offset = some targetValue := by
  obtain ⟨admitted, fits, placed⟩ := (abiType.decodeStrict_eq_some_iff data start value).mp canonical
  simp only [AbiType.compile?, Option.map_eq_some_iff, Prod.exists] at compiled
  obtain ⟨hops, delta, entered, target, walked, rfl⟩ := compiled
  have inside := placed_end placed
  have walkedCanonical :=
    AbiType.resolveHops_walk (base := start) (position := start) fits walked (by omega) admitted placed (by simp)
  rw [present] at walkedCanonical
  obtain ⟨base, position, chain, baseInRange, targetAdmits, targetPlaced, stands⟩ := walkedCanonical
  have targetInside := placed_end targetPlaced
  obtain ⟨final, entry, -, positionIs, -⟩ := AbiType.resolveHops_enter_placed fits baseInRange (by omega) stands
  refine ⟨position, ?_, (target.decodeStrict_eq_some_iff data position targetValue).mpr
    ⟨targetAdmits, fits, targetPlaced⟩⟩
  exact Except.map_eq_ok.mpr ⟨final, resolveHops_append.mpr ⟨base, chain, entry⟩, positionIs.symm⟩

/-- Theorem 24, a path the value does not hold: on canonical calldata, its compiled hint stops at a fixed index past a
dynamic array's length, never at a read past the end of the calldata. -/
theorem AbiType.resolve_compile?_absent {abiType : AbiType} {data : Bytes} {start : Nat} {value : Value}
    (canonical : abiType.decodeStrict data start = some value) {path : Path} (absent : value.at path = none)
    {hint : Hint} (compiled : abiType.compile? path = some hint) :
    hint.resolve data start = .error .arrayIndexOutOfBounds := by
  obtain ⟨admitted, fits, placed⟩ := (abiType.decodeStrict_eq_some_iff data start value).mp canonical
  simp only [AbiType.compile?, Option.map_eq_some_iff, Prod.exists] at compiled
  obtain ⟨hops, delta, entered, target, walked, rfl⟩ := compiled
  have inside := placed_end placed
  have walkedCanonical :=
    AbiType.resolveHops_walk (base := start) (position := start) fits walked (by omega) admitted placed (by simp)
  rw [absent] at walkedCanonical
  simp only [Hint.resolve, resolveHops_append_of_error walkedCanonical]
  rfl

theorem LoopHint.resolveArray_of_error {loop : LoopHint} {data : Bytes} {start : Nat} {fault : Fault}
    (chain : resolveHops data loop.hops start = .error fault) : loop.resolveArray data start = .error fault := by
  simp [LoopHint.resolveArray, chain, bind, Except.bind]

/-- Theorem 24 for loops: on canonical calldata, the hint of a loop over an array the value holds yields as many
elements as the array holds, each starting where its canonical encoding lies, so the body's hints resolve from each by
theorem 24. -/
theorem AbiType.resolveArray_compileLoop?_ok {abiType : AbiType} {data : Bytes} {start : Nat} {value : Value}
    (canonical : abiType.decodeStrict data start = some value) {arrayPath : Path} {items : List Value}
    (array : value.at arrayPath = some (.list items)) {loop : LoopHint}
    (compiled : abiType.compileLoop? arrayPath = some loop) :
    ∃ elements, loop.resolveArray data start = .ok (elements, items.length) ∧
      ∀ {position : Nat} {item : Value}, items[position]? = some item →
        ∃ elementStart, loop.resolveElement data elements position = .ok elementStart ∧
          loop.element.decodeStrict data elementStart = some item := by
  obtain ⟨admitted, fits, placed⟩ := (abiType.decodeStrict_eq_some_iff data start value).mp canonical
  have inside := placed_end placed
  cases walked : abiType.walk arrayPath 0 true with
  | none => simp [AbiType.compileLoop?, walked] at compiled
  | some walk =>
    obtain ⟨hops, delta, entered, arrayType⟩ := walk
    have walkedCanonical :=
      AbiType.resolveHops_walk (base := start) (position := start) fits walked (by omega) admitted placed (by simp)
    rw [array] at walkedCanonical
    obtain ⟨base, position, chain, baseInRange, arrayAdmits, arrayPlaced, stands⟩ := walkedCanonical
    have arrayInside := placed_end arrayPlaced
    obtain ⟨final, entry, finalInRange, positionIs, settled⟩ :=
      AbiType.resolveHops_enter_placed fits baseInRange (by omega) stands
    cases arrayType with
    | staticArray element length =>
      simp only [AbiType.compileLoop?, walked] at compiled
      split at compiled
      · rename_i nonempty
        simp only [Option.some.injEq] at compiled
        subst compiled
        simp only [AbiType.admits] at arrayAdmits
        have lengthIs := AbiType.length_eq_of_admitsAll arrayAdmits
        rw [List.length_replicate] at lengthIs
        subst lengthIs
        simp only [AbiType.encode] at arrayPlaced
        refine ⟨position, LoopHint.resolveArray_eq_ok.mpr ⟨final, resolveHops_append.mpr ⟨base, chain, entry⟩, ?_⟩, ?_⟩
        · simp [Nat.pos_iff_ne_zero.mp nonempty, positionIs]
        · intro elementIndex item itemAt
          obtain ⟨elementStart, resolvedElement, elementAdmits, elementPlaced⟩ :=
            elementAt_placed false arrayAdmits fits arrayPlaced itemAt
          exact ⟨elementStart, resolvedElement,
            (element.decodeStrict_eq_some_iff data elementStart item).mpr ⟨elementAdmits, fits, elementPlaced⟩⟩
      · simp at compiled
    | dynamicArray element =>
      simp only [AbiType.compileLoop?, walked, Option.some.injEq] at compiled
      subst compiled
      have arrayDynamic : (AbiType.dynamicArray element).isDynamic = true := rfl
      rw [settled arrayDynamic] at positionIs
      simp only [AbiType.admits, Bool.and_eq_true, decide_eq_true_eq] at arrayAdmits
      simp only [AbiType.encode] at arrayPlaced
      have lengthPlaced := placed_trans arrayPlaced (piece := beBytes WORD_SIZE items.length) (offset := 0)
        ⟨[], joinComponents (AbiType.encodeComponents (List.replicate items.length element) items), by simp, rfl⟩
      have elementsPlaced := placed_trans arrayPlaced
        (piece := joinComponents (AbiType.encodeComponents (List.replicate items.length element) items))
        ⟨beBytes WORD_SIZE items.length, [], by simp, rfl⟩
      have lengthEnd := placed_end lengthPlaced
      simp only [beBytes_length, Nat.add_zero] at lengthEnd lengthPlaced elementsPlaced
      rw [advance_zero finalInRange] at positionIs
      subst positionIs
      have entryResolved : resolveHops data (enter (!entered) delta).1 base = .ok position := by
        simpa [AbiType.isDynamic] using entry
      refine ⟨position + WORD_SIZE,
        LoopHint.resolveArray_eq_ok.mpr ⟨position, resolveHops_append.mpr ⟨base, chain, entryResolved⟩, ?_⟩, ?_⟩
      · have noDelta : (enter (!entered) delta).2 = 0 := by simpa [AbiType.isDynamic] using settled arrayDynamic
        simp only [↓reduceIte, noDelta, advance_zero finalInRange]
        rw [readWord_placed fits lengthPlaced arrayAdmits.1, advance_of_lt (by omega)]
        exact ⟨lengthEnd, rfl, rfl⟩
      · intro elementIndex item itemAt
        obtain ⟨elementStart, resolvedElement, elementAdmits, elementPlaced⟩ :=
          elementAt_placed true arrayAdmits.2 fits elementsPlaced itemAt
        exact ⟨elementStart, resolvedElement,
          (element.decodeStrict_eq_some_iff data elementStart item).mpr ⟨elementAdmits, fits, elementPlaced⟩⟩
    | word | bytes | string | tuple => simp [AbiType.compileLoop?, walked] at compiled

/-- Theorem 24 for loops, an array the value does not hold: on canonical calldata, the loop's hint stops at a fixed
index past a dynamic array's length, never at a read past the end of the calldata. -/
theorem AbiType.resolveArray_compileLoop?_absent {abiType : AbiType} {data : Bytes} {start : Nat} {value : Value}
    (canonical : abiType.decodeStrict data start = some value) {arrayPath : Path} (absent : value.at arrayPath = none)
    {loop : LoopHint} (compiled : abiType.compileLoop? arrayPath = some loop) :
    loop.resolveArray data start = .error .arrayIndexOutOfBounds := by
  obtain ⟨admitted, fits, placed⟩ := (abiType.decodeStrict_eq_some_iff data start value).mp canonical
  have inside := placed_end placed
  cases walked : abiType.walk arrayPath 0 true with
  | none => simp [AbiType.compileLoop?, walked] at compiled
  | some walk =>
    obtain ⟨hops, delta, entered, arrayType⟩ := walk
    have walkedCanonical :=
      AbiType.resolveHops_walk (base := start) (position := start) fits walked (by omega) admitted placed (by simp)
    rw [absent] at walkedCanonical
    cases arrayType with
    | staticArray element length =>
      simp only [AbiType.compileLoop?, walked] at compiled
      split at compiled
      · simp only [Option.some.injEq] at compiled
        subst compiled
        exact LoopHint.resolveArray_of_error (resolveHops_append_of_error walkedCanonical)
      · simp at compiled
    | dynamicArray element =>
      simp only [AbiType.compileLoop?, walked, Option.some.injEq] at compiled
      subst compiled
      exact LoopHint.resolveArray_of_error (resolveHops_append_of_error walkedCanonical)
    | word | bytes | string | tuple => simp [AbiType.compileLoop?, walked] at compiled

/-! ## Theorem 14 at path level -/

theorem Descriptor.skipNodes_encodeNodes (types : List AbiType) (fit : AbiType.allFit types = true) {index : Nat}
    (within : index ≤ types.length) (rest : Bytes) :
    skipNodes index (AbiType.encodeNodes types ++ rest) = some (AbiType.sumNodeLength (types.take index)) := by
  induction types generalizing index with
  | nil =>
    simp only [List.length_nil, Nat.le_zero] at within
    subst within
    simp [skipNodes, AbiType.sumNodeLength]
  | cons abiType types more =>
    simp only [AbiType.allFit, Bool.and_eq_true] at fit
    cases index with
    | zero => simp [skipNodes, AbiType.sumNodeLength]
    | succ index =>
      simp only [List.length_cons, Nat.add_le_add_iff_right] at within
      have dropped : (abiType.encodeNode ++ (AbiType.encodeNodes types ++ rest)).drop abiType.nodeLength =
          AbiType.encodeNodes types ++ rest := by
        rw [← AbiType.encodeNode_length, List.drop_left]
      simp only [skipNodes, AbiType.encodeNodes, List.append_assoc, skipNode_encodeNode abiType fit.1,
        Option.bind_some, dropped, more fit.2 within, Option.map_some, List.take_succ_cons, AbiType.sumNodeLength]

/-- Theorem 14 at path level, for parameters: on a valid descriptor, parameter `index` lies where repeated `skipNode`
finds it, `sumNodeLength (types.take index)` past the parameter count, and the walk reaches it. -/
theorem Descriptor.skipNodes_param {desc : Bytes} (isValid : valid desc = true) {types : List AbiType}
    (decoded : decode desc = some types) {index : Nat} (below : index < types.length) :
    skipNodes index (desc.drop 2) = some (AbiType.sumNodeLength (types.take index)) ∧
      NodeAt desc (2 + AbiType.sumNodeLength (types.take index)) := by
  obtain ⟨encoded, limits, rfl⟩ := (valid_iff_encoded desc).mp isValid
  rw [decode_encode encoded limits, Option.some.injEq] at decoded
  subst decoded
  obtain ⟨countFits, fit, -⟩ := (withinLimits_iff encoded).mp limits
  simp only [MAX_PARAMS, Nat.reducePow] at countFits
  refine ⟨by simpa [encode] using skipNodes_encodeNodes encoded fit (Nat.le_of_lt below) [], ?_⟩
  apply NodeAt.param rfl
  · rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega : encoded.length < 2 ^ 8)]
    exact below
  · simpa using decodeNodes_take encoded fit index (Nat.le_of_lt below) []

/-- Theorem 14 at path level, for tuple fields: on a valid descriptor, field `index` of a tuple node the walk reaches
lies where repeated `skipNode` finds it, `TUPLE_HEADER_SIZE + sumNodeLength (fields.take index)` past the tuple, and the
walk reaches it. An array's element needs no skipping: it follows the array's header. -/
theorem Descriptor.skipNodes_field {desc : Bytes} {offset : Nat} (isValid : valid desc = true)
    (reached : NodeAt desc offset) {fields : List AbiType} {span : Nat}
    (tupleAt : decodeNode (desc.drop offset) = some (.tuple fields, span)) {index : Nat}
    (below : index < fields.length) :
    skipNodes index (desc.drop (offset + TUPLE_HEADER_SIZE)) = some (AbiType.sumNodeLength (fields.take index)) ∧
      NodeAt desc (offset + TUPLE_HEADER_SIZE + AbiType.sumNodeLength (fields.take index)) := by
  obtain ⟨found, rest, fits, foundAt⟩ := encodeNode_at isValid reached
  rw [foundAt, decodeNode_encodeNode found fits rest, Option.some.injEq, Prod.mk.injEq] at tupleAt
  obtain ⟨rfl, -⟩ := tupleAt
  have tupleFits := fits
  simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at tupleFits
  obtain ⟨⟨⟨-, countFits⟩, -, -⟩, fieldsFit⟩ := tupleFits
  simp only [MAX_TUPLE_FIELDS, MAX_NODE_LENGTH, TUPLE_HEADER_SIZE] at countFits
  obtain ⟨countHigh, countLow, countBytes, countRead⟩ := be16_reads (by omega : fields.length < 2 ^ 16)
  have fieldsAt : desc.drop (offset + TUPLE_HEADER_SIZE) = AbiType.encodeNodes fields ++ rest := by
    rw [← List.drop_drop, foundAt, AbiType.encodeNode, AbiType.compositeHeader, countBytes]
    simp [compositeMeta, TUPLE_HEADER_SIZE]
  refine ⟨by rw [fieldsAt]; exact skipNodes_encodeNodes fields fieldsFit (Nat.le_of_lt below) rest, ?_⟩
  let metaValue := (AbiType.tuple fields).staticWords * 2 ^ 12 + (AbiType.tuple fields).nodeLength
  apply NodeAt.field reached (high := UInt8.ofNat (metaValue / 2 ^ 16)) (middle := UInt8.ofNat (metaValue / 2 ^ 8))
    (low := UInt8.ofNat metaValue) (countHigh := countHigh) (countLow := countLow)
    (fieldBytes := AbiType.encodeNodes fields ++ rest)
  · rw [foundAt, AbiType.encodeNode, AbiType.compositeHeader, countBytes]
    simp [compositeMeta, metaValue]
  · rw [countRead]
    exact below
  · exact decodeNodes_take fields fieldsFit index (Nat.le_of_lt below) rest

end Callcium
