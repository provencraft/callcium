import Callcium.Abi.DecodeStrict

/-!
# ABI

The head-length lemma: a static value's encoding is `staticWords` words long. Round trip: `decodeSolc` reads back
every encoded value, wherever the encoding sits in the data, and `decodeStrict` accepts exactly the canonical
encodings. Locality: a component of a decoded value is the value decoded where the component starts.
-/

namespace Callcium

/-! ## Bytes and words -/

theorem beBytes_length (count value : Nat) : (beBytes count value).length = count := by
  induction count generalizing value with
  | zero => rfl
  | succ count shorter => simp [beBytes, shorter]

theorem beNat_append_byte (bytes : Bytes) (byte : UInt8) :
    beNat (bytes ++ [byte]) = beNat bytes * 256 + byte.toNat := by
  simp [beNat, List.foldl_append]

theorem beNat_beBytes (count value : Nat) : beNat (beBytes count value) = value % 256 ^ count := by
  induction count generalizing value with
  | zero => simp [beBytes, beNat, Nat.mod_one]
  | succ count shorter =>
    rw [beBytes, beNat_append_byte, shorter, UInt8.toNat_ofNat',
      show 256 ^ (count + 1) = 256 * 256 ^ count by rw [Nat.pow_succ, Nat.mul_comm], Nat.mod_mul]
    simp only [Nat.reducePow]
    omega

theorem readBytes_append (before bytes after : Bytes) :
    readBytes (before ++ bytes ++ after) before.length bytes.length = bytes := by
  simp [readBytes, List.append_assoc]

theorem readWord_beBytes (before after : Bytes) (value : Nat) :
    readWord (before ++ beBytes WORD_SIZE value ++ after) before.length = BitVec.ofNat 256 value := by
  have reads := readBytes_append before (beBytes WORD_SIZE value) after
  rw [beBytes_length] at reads
  simp only [readWord, reads, beNat_beBytes]
  apply BitVec.eq_of_toNat_eq
  simp only [BitVec.toNat_ofNat, WORD_SIZE, Nat.reducePow, Nat.mod_mod]

theorem toNat_readWord_beBytes (before after : Bytes) {value : Nat} (fits : value < 2 ^ 256) :
    (readWord (before ++ beBytes WORD_SIZE value ++ after) before.length).toNat = value := by
  rw [readWord_beBytes, BitVec.toNat_ofNat, Nat.mod_eq_of_lt fits]

theorem advance_of_lt {position offset : Nat} (fits : position + offset < 2 ^ 256) :
    advance position offset = position + offset :=
  Nat.mod_eq_of_lt fits

/-! ## Heads and tails -/

theorem headsAndTails_heads_length (components : List (Bool × Bytes)) (tailOffset : Nat) :
    (headsAndTails components tailOffset).1.length = (components.map headLength).sum := by
  induction components generalizing tailOffset with
  | nil => rfl
  | cons component components rest =>
    obtain ⟨dynamic, encoding⟩ := component
    cases dynamic <;> simp [headsAndTails, headLength, rest, beBytes_length]

theorem headsAndTails_tails_of_static {components : List (Bool × Bytes)}
    (static : ∀ component ∈ components, component.1 = false) (tailOffset : Nat) :
    (headsAndTails components tailOffset).2 = [] := by
  induction components generalizing tailOffset with
  | nil => rfl
  | cons component components rest =>
    obtain ⟨dynamic, encoding⟩ := component
    have isStatic : dynamic = false := static _ List.mem_cons_self
    subst isStatic
    simp [headsAndTails, rest fun component member => static component (List.mem_cons_of_mem _ member)]

theorem headsAndTails_length_mod {components : List (Bool × Bytes)}
    (whole : ∀ component ∈ components, component.2.length % WORD_SIZE = 0) (tailOffset : Nat) :
    (headsAndTails components tailOffset).1.length % WORD_SIZE = 0 ∧
      (headsAndTails components tailOffset).2.length % WORD_SIZE = 0 := by
  induction components generalizing tailOffset with
  | nil => simp [headsAndTails]
  | cons component components rest =>
    obtain ⟨dynamic, encoding⟩ := component
    have encodingWhole : encoding.length % WORD_SIZE = 0 := whole _ List.mem_cons_self
    have restWhole := rest fun component member => whole component (List.mem_cons_of_mem _ member)
    cases dynamic
    · have := restWhole tailOffset
      simp only [headsAndTails, Bool.false_eq_true, ↓reduceIte, List.length_append]
      unfold WORD_SIZE at *
      omega
    · have := restWhole (tailOffset + encoding.length)
      simp only [headsAndTails, ↓reduceIte, List.length_append, beBytes_length]
      unfold WORD_SIZE at *
      omega

theorem joinComponents_length_mod {components : List (Bool × Bytes)}
    (whole : ∀ component ∈ components, component.2.length % WORD_SIZE = 0) :
    (joinComponents components).length % WORD_SIZE = 0 := by
  have := headsAndTails_length_mod whole (components.map headLength).sum
  simp only [joinComponents, List.length_append]
  unfold WORD_SIZE at *
  omega

/-! ## Components -/

theorem sum_map_mul (factor : Nat) {Item : Type} (items : List Item) (size : Item → Nat) :
    (items.map fun item => factor * size item).sum = factor * (items.map size).sum := by
  induction items with
  | nil => rfl
  | cons item items rest => simp [rest, Nat.mul_add]

theorem AbiType.anyDynamic_eq_false_iff (types : List AbiType) :
    AbiType.anyDynamic types = false ↔ ∀ abiType ∈ types, abiType.isDynamic = false := by
  induction types with
  | nil => simp [AbiType.anyDynamic]
  | cons abiType types rest => simp [AbiType.anyDynamic, rest]

theorem AbiType.sumStaticWords_eq (types : List AbiType) :
    AbiType.sumStaticWords types = (types.map AbiType.staticWords).sum := by
  induction types with
  | nil => rfl
  | cons abiType types rest => simp [AbiType.sumStaticWords, rest]

/-- Every component is an admitted value of one of the types, encoded. -/
theorem AbiType.mem_encodeComponents {types : List AbiType} {values : List Value}
    (admitted : AbiType.admitsAll types values = true) {component : Bool × Bytes}
    (member : component ∈ AbiType.encodeComponents types values) :
    ∃ abiType ∈ types, ∃ value, abiType.admits value = true ∧
      component = (abiType.isDynamic, abiType.encode value) := by
  induction types generalizing values with
  | nil => cases values <;> simp [AbiType.encodeComponents] at member
  | cons abiType types rest =>
    cases values with
    | nil => simp [AbiType.admitsAll] at admitted
    | cons value values =>
      simp only [AbiType.admitsAll, Bool.and_eq_true] at admitted
      simp only [AbiType.encodeComponents, List.mem_cons] at member
      rcases member with first | later
      · exact ⟨abiType, List.mem_cons_self, value, admitted.1, first⟩
      · obtain ⟨found, foundMember, foundValue, foundAdmitted, foundComponent⟩ := rest admitted.2 later
        exact ⟨found, List.mem_cons_of_mem _ foundMember, foundValue, foundAdmitted, foundComponent⟩

theorem AbiType.map_headLength_encodeComponents {types : List AbiType} {values : List Value}
    (lengths : ∀ abiType ∈ types, ∀ value, abiType.admits value = true →
      headLength (abiType.isDynamic, abiType.encode value) = abiType.headSize)
    (admitted : AbiType.admitsAll types values = true) :
    (AbiType.encodeComponents types values).map headLength = types.map AbiType.headSize := by
  induction types generalizing values with
  | nil => cases values <;> simp [AbiType.encodeComponents]
  | cons abiType types rest =>
    cases values with
    | nil => simp [AbiType.admitsAll] at admitted
    | cons value values =>
      simp only [AbiType.admitsAll, Bool.and_eq_true] at admitted
      simp only [AbiType.encodeComponents, List.map_cons, List.cons.injEq]
      exact ⟨lengths abiType List.mem_cons_self value admitted.1,
        rest (fun found member => lengths found (List.mem_cons_of_mem _ member)) admitted.2⟩

/-- The encoding of static components is their heads. -/
theorem AbiType.joinComponents_length_of_static {types : List AbiType} {values : List Value}
    (lengths : ∀ abiType ∈ types, ∀ value, abiType.admits value = true →
      headLength (abiType.isDynamic, abiType.encode value) = abiType.headSize)
    (static : ∀ abiType ∈ types, abiType.isDynamic = false) (admitted : AbiType.admitsAll types values = true) :
    (joinComponents (AbiType.encodeComponents types values)).length = (types.map AbiType.headSize).sum := by
  have tails := headsAndTails_tails_of_static (components := AbiType.encodeComponents types values) (by
    intro component member
    obtain ⟨abiType, typeMember, _, _, rfl⟩ := AbiType.mem_encodeComponents admitted member
    exact static abiType typeMember)
  simp only [joinComponents, tails, List.append_nil, headsAndTails_heads_length,
    AbiType.map_headLength_encodeComponents lengths admitted]

/-! ## Encoding length -/

/-- Every encoding is whole words. -/
theorem AbiType.encode_length_mod (abiType : AbiType) {value : Value} (admitted : abiType.admits value = true) :
    (abiType.encode value).length % WORD_SIZE = 0 := by
  induction abiType generalizing value with
  | word wordType =>
    cases value <;> simp_all [AbiType.admits, AbiType.encode, beBytes_length]
  | bytes | string =>
    cases value <;> simp_all [AbiType.admits, AbiType.encode, beBytes_length, paddingLength] <;>
      unfold WORD_SIZE <;> omega
  | staticArray element length whole =>
    cases value <;> simp only [AbiType.admits, Bool.false_eq_true] at admitted
    apply joinComponents_length_mod
    intro component member
    obtain ⟨abiType, typeMember, found, foundAdmitted, rfl⟩ := AbiType.mem_encodeComponents admitted member
    rw [List.eq_of_mem_replicate typeMember] at foundAdmitted ⊢
    exact whole foundAdmitted
  | dynamicArray element whole =>
    cases value with
    | word | bytes => simp [AbiType.admits] at admitted
    | list items =>
    simp only [AbiType.admits, Bool.and_eq_true] at admitted
    have joined :
        (joinComponents (AbiType.encodeComponents (List.replicate items.length element) items)).length %
          WORD_SIZE = 0 := by
      apply joinComponents_length_mod
      intro component member
      obtain ⟨abiType, typeMember, found, foundAdmitted, rfl⟩ := AbiType.mem_encodeComponents admitted.2 member
      rw [List.eq_of_mem_replicate typeMember] at foundAdmitted ⊢
      exact whole foundAdmitted
    simp only [AbiType.encode, List.length_append, beBytes_length]
    unfold WORD_SIZE at *
    omega
  | tuple fields whole =>
    cases value <;> simp only [AbiType.admits, Bool.false_eq_true] at admitted
    apply joinComponents_length_mod
    intro component member
    obtain ⟨abiType, typeMember, found, foundAdmitted, rfl⟩ := AbiType.mem_encodeComponents admitted member
    exact whole abiType typeMember foundAdmitted

/-- An admitted value's head is the type's `headSize`: one word when dynamic, its whole encoding when static. -/
theorem AbiType.headLength_encode (abiType : AbiType) {value : Value} (admitted : abiType.admits value = true) :
    headLength (abiType.isDynamic, abiType.encode value) = abiType.headSize := by
  induction abiType generalizing value with
  | word wordType =>
    cases value <;> simp_all [AbiType.admits, AbiType.encode, AbiType.isDynamic, AbiType.headSize,
      AbiType.staticWords, headLength, beBytes_length]
  | bytes | string | dynamicArray =>
    simp [AbiType.isDynamic, AbiType.headSize, headLength]
  | staticArray element length lengths =>
    cases value <;> simp only [AbiType.admits, Bool.false_eq_true] at admitted
    cases dynamic : element.isDynamic
    · have joined := AbiType.joinComponents_length_of_static
        (fun found member _ foundAdmitted => by
          rw [List.eq_of_mem_replicate member] at foundAdmitted ⊢
          exact lengths foundAdmitted)
        (fun found member => by rw [List.eq_of_mem_replicate member]; exact dynamic) admitted
      simp only [AbiType.isDynamic, dynamic, AbiType.headSize, AbiType.staticWords, headLength, Bool.false_eq_true,
        ↓reduceIte, AbiType.encode, joined, List.map_replicate, List.sum_replicate_nat]
      rw [Nat.mul_left_comm]
    · simp [AbiType.isDynamic, dynamic, AbiType.headSize, headLength]
  | tuple fields lengths =>
    cases value <;> simp only [AbiType.admits, Bool.false_eq_true] at admitted
    cases dynamic : AbiType.anyDynamic fields
    · have static := (AbiType.anyDynamic_eq_false_iff fields).mp dynamic
      have joined := AbiType.joinComponents_length_of_static
        (fun found member _ foundAdmitted => lengths found member foundAdmitted) static admitted
      have heads : fields.map AbiType.headSize = fields.map (WORD_SIZE * ·.staticWords) :=
        List.map_congr_left fun found member => by simp [AbiType.headSize, static found member]
      simp only [AbiType.isDynamic, dynamic, AbiType.headSize, AbiType.staticWords, headLength, Bool.false_eq_true,
        ↓reduceIte, AbiType.encode, joined, heads, AbiType.sumStaticWords_eq, sum_map_mul]
    · simp [AbiType.isDynamic, dynamic, AbiType.headSize, headLength]

/-- The head-length lemma: a static value's encoding is `staticWords` words long. -/
theorem AbiType.encode_length_of_static (abiType : AbiType) {value : Value} (static : abiType.isDynamic = false)
    (admitted : abiType.admits value = true) : (abiType.encode value).length = WORD_SIZE * abiType.staticWords := by
  have := abiType.headLength_encode admitted
  simpa [headLength, AbiType.headSize, static] using this

/-! ## Round trip -/

theorem AbiType.decodeElements_eq (element : AbiType) (data : Bytes) (base head count : Nat) :
    decodeElements (element.decodeSolc data) element data base head count =
      AbiType.decodeFields (List.replicate count element) data base head := by
  induction count generalizing head with
  | zero => simp [decodeElements, AbiType.decodeFields]
  | succ count rest => simp [decodeElements, AbiType.decodeFields, List.replicate_succ, rest]

/-- Fields decode to the values whose components' heads lie at `head` and whose tails lie at `tailOffset` past
`base`. -/
theorem AbiType.decodeFields_encode {types : List AbiType} {values : List Value}
    (decodes : ∀ abiType ∈ types, ∀ {value : Value} (before after : Bytes), abiType.admits value = true →
      (before ++ abiType.encode value ++ after).length < 2 ^ 256 →
      abiType.decodeSolc (before ++ abiType.encode value ++ after) before.length = value)
    (admitted : AbiType.admitsAll types values = true) {data : Bytes} (fits : data.length < 2 ^ 256)
    {base head tailOffset : Nat}
    (headsAt : ∃ before after,
      data = before ++ (headsAndTails (AbiType.encodeComponents types values) tailOffset).1 ++ after ∧
        before.length = head)
    (tailsAt : ∃ before after,
      data = before ++ (headsAndTails (AbiType.encodeComponents types values) tailOffset).2 ++ after ∧
        before.length = base + tailOffset) :
    AbiType.decodeFields types data base head = values := by
  induction types generalizing values head tailOffset with
  | nil => cases values <;> simp_all [AbiType.admitsAll, AbiType.decodeFields]
  | cons abiType types rest =>
    cases values with
    | nil => simp [AbiType.admitsAll] at admitted
    | cons value values =>
    simp only [AbiType.admitsAll, Bool.and_eq_true] at admitted
    obtain ⟨headsBefore, headsAfter, headsData, headsPosition⟩ := headsAt
    obtain ⟨tailsBefore, tailsAfter, tailsData, tailsPosition⟩ := tailsAt
    have restDecodes := fun found member => @decodes found (List.mem_cons_of_mem abiType member)
    have headsLength := congrArg List.length headsData
    have tailsLength := congrArg List.length tailsData
    simp only [AbiType.decodeFields, List.cons.injEq]
    cases dynamic : abiType.isDynamic
    · simp only [AbiType.encodeComponents, dynamic, headsAndTails, Bool.false_eq_true, ↓reduceIte]
        at headsData tailsData headsLength tailsLength
      have encodingLength : (abiType.encode value).length = abiType.headSize := by
        simpa [headLength, dynamic] using abiType.headLength_encode admitted.1
      simp only [List.length_append] at headsLength
      refine ⟨?_, ?_⟩
      · have reads := decodes abiType List.mem_cons_self headsBefore
          ((headsAndTails (AbiType.encodeComponents types values) tailOffset).1 ++ headsAfter) admitted.1
          (by simp only [List.length_append] at fits ⊢; omega)
        simp only [AbiType.componentStart, dynamic, Bool.false_eq_true, ↓reduceIte]
        rw [headsData, ← headsPosition]
        simpa only [List.append_assoc] using reads
      · rw [advance_of_lt (by omega)]
        exact rest restDecodes admitted.2
          ⟨headsBefore ++ abiType.encode value, headsAfter, by simp [headsData], by simp; omega⟩
          ⟨tailsBefore, tailsAfter, tailsData, tailsPosition⟩
    · simp only [AbiType.encodeComponents, dynamic, headsAndTails, ↓reduceIte]
        at headsData tailsData headsLength tailsLength
      simp only [List.length_append, beBytes_length] at headsLength tailsLength
      have offsetFits : tailOffset < 2 ^ 256 := by omega
      refine ⟨?_, ?_⟩
      · have reads := decodes abiType List.mem_cons_self tailsBefore
          ((headsAndTails (AbiType.encodeComponents types values) (tailOffset + (abiType.encode value).length)).2 ++
            tailsAfter) admitted.1 (by simp only [List.length_append] at fits ⊢; omega)
        have offset : (readWord data head).toNat = tailOffset := by
          rw [headsData, ← headsPosition]
          simpa only [List.append_assoc] using toNat_readWord_beBytes headsBefore
            ((headsAndTails (AbiType.encodeComponents types values)
              (tailOffset + (abiType.encode value).length)).1 ++ headsAfter) offsetFits
        simp only [AbiType.componentStart, dynamic, ↓reduceIte, offset]
        rw [advance_of_lt (by omega), tailsData, ← tailsPosition]
        simpa only [List.append_assoc] using reads
      · have headSize : abiType.headSize = WORD_SIZE := by simp [AbiType.headSize, dynamic]
        rw [headSize, advance_of_lt (by unfold WORD_SIZE at *; omega)]
        exact rest (tailOffset := tailOffset + (abiType.encode value).length) restDecodes admitted.2
          ⟨headsBefore ++ beBytes WORD_SIZE tailOffset, headsAfter, by simp [headsData],
            by simp [beBytes_length]; omega⟩
          ⟨tailsBefore ++ abiType.encode value, tailsAfter, by simp [tailsData], by simp; omega⟩

/-- Components laid out by `joinComponents` decode back from where they start. -/
theorem AbiType.decodeFields_joinComponents {types : List AbiType} {values : List Value}
    (decodes : ∀ abiType ∈ types, ∀ {value : Value} (before after : Bytes), abiType.admits value = true →
      (before ++ abiType.encode value ++ after).length < 2 ^ 256 →
      abiType.decodeSolc (before ++ abiType.encode value ++ after) before.length = value)
    (admitted : AbiType.admitsAll types values = true) (before after : Bytes)
    (fits : (before ++ joinComponents (AbiType.encodeComponents types values) ++ after).length < 2 ^ 256) :
    AbiType.decodeFields types (before ++ joinComponents (AbiType.encodeComponents types values) ++ after)
      before.length before.length = values := by
  have heads := headsAndTails_heads_length (AbiType.encodeComponents types values)
    ((AbiType.encodeComponents types values).map headLength).sum
  apply AbiType.decodeFields_encode decodes admitted fits
    (tailOffset := ((AbiType.encodeComponents types values).map headLength).sum)
  · exact ⟨before, (headsAndTails (AbiType.encodeComponents types values)
      ((AbiType.encodeComponents types values).map headLength).sum).2 ++ after, by simp [joinComponents], rfl⟩
  · exact ⟨before ++ (headsAndTails (AbiType.encodeComponents types values)
      ((AbiType.encodeComponents types values).map headLength).sum).1, after, by simp [joinComponents],
      by simp [heads]⟩

/-- Round trip: wherever an admitted value's encoding sits in data shorter than 2^256 bytes, `decodeSolc` reads the
value back from its first byte. -/
theorem AbiType.decodeSolc_encode (abiType : AbiType) {value : Value} (before after : Bytes)
    (admitted : abiType.admits value = true) (fits : (before ++ abiType.encode value ++ after).length < 2 ^ 256) :
    abiType.decodeSolc (before ++ abiType.encode value ++ after) before.length = value := by
  induction abiType generalizing value before after with
  | word wordType =>
    cases value with
    | word bits signed =>
      simp only [AbiType.admits, Bool.and_eq_true, beq_iff_eq] at admitted
      simp only [AbiType.encode, AbiType.decodeSolc, readWord_beBytes, admitted.2, Value.word.injEq, and_true]
      apply BitVec.eq_of_toNat_eq
      simp
    | bytes | list => simp [AbiType.admits] at admitted
  | bytes | string =>
    cases value with
    | bytes content =>
      simp only [AbiType.admits, decide_eq_true_eq] at admitted
      simp only [AbiType.encode, List.length_append, beBytes_length] at fits
      have length := toNat_readWord_beBytes before
        (content ++ List.replicate (paddingLength content.length) 0 ++ after) admitted
      have reads := readBytes_append (before ++ beBytes WORD_SIZE content.length) content
        (List.replicate (paddingLength content.length) 0 ++ after)
      simp only [List.length_append, beBytes_length] at reads
      simp only [AbiType.encode, AbiType.decodeSolc, List.append_assoc] at length reads ⊢
      rw [length, advance_of_lt (by unfold WORD_SIZE at *; omega), reads]
    | word | list => simp [AbiType.admits] at admitted
  | staticArray element length decodesElement =>
    cases value with
    | list items =>
      simp only [AbiType.admits] at admitted
      simp only [AbiType.encode] at fits ⊢
      simp only [AbiType.decodeSolc, AbiType.decodeElements_eq, Value.list.injEq]
      exact AbiType.decodeFields_joinComponents
        (fun found member => by rw [List.eq_of_mem_replicate member]; exact decodesElement) admitted before after fits
    | word | bytes => simp [AbiType.admits] at admitted
  | dynamicArray element decodesElement =>
    cases value with
    | list items =>
      simp only [AbiType.admits, Bool.and_eq_true, decide_eq_true_eq] at admitted
      simp only [AbiType.encode, List.length_append, beBytes_length] at fits
      have count := toNat_readWord_beBytes before
        (joinComponents (AbiType.encodeComponents (List.replicate items.length element) items) ++ after) admitted.1
      have decodes := AbiType.decodeFields_joinComponents
        (fun found member => by rw [List.eq_of_mem_replicate member]; exact decodesElement) admitted.2
        (before ++ beBytes WORD_SIZE items.length) after (by simp only [List.length_append, beBytes_length]; omega)
      simp only [List.length_append, beBytes_length] at decodes
      simp only [AbiType.encode, AbiType.decodeSolc, AbiType.decodeElements_eq, Value.list.injEq,
        List.append_assoc] at count decodes ⊢
      rw [count, advance_of_lt (by unfold WORD_SIZE at *; omega), decodes]
    | word | bytes => simp [AbiType.admits] at admitted
  | tuple fields decodesField =>
    cases value with
    | list items =>
      simp only [AbiType.admits] at admitted
      simp only [AbiType.encode] at fits ⊢
      simp only [AbiType.decodeSolc, Value.list.injEq]
      exact AbiType.decodeFields_joinComponents decodesField admitted before after fits
    | word | bytes => simp [AbiType.admits] at admitted

/-! ## Strict decoding -/

/-- `decodeStrict` accepts exactly the canonical encodings: an admitted value's encoding at `start`, with any bytes
before and after it, in data shorter than 2^256 bytes. -/
theorem AbiType.decodeStrict_eq_some_iff (abiType : AbiType) (data : Bytes) (start : Nat) (value : Value) :
    abiType.decodeStrict data start = some value ↔
      abiType.admits value = true ∧ data.length < 2 ^ 256 ∧
        ∃ before after, data = before ++ abiType.encode value ++ after ∧ before.length = start := by
  constructor
  · intro accepts
    simp only [AbiType.decodeStrict] at accepts
    split at accepts
    · rename_i canonical
      obtain ⟨admitted, inside, fits, after, opens⟩ := canonical
      cases accepts
      refine ⟨admitted, fits, data.take start, after, ?_, by simp [inside]⟩
      rw [List.append_assoc, opens, List.take_append_drop]
    · cases accepts
  · rintro ⟨admitted, fits, before, after, rfl, rfl⟩
    simp only [AbiType.decodeStrict, abiType.decodeSolc_encode before after admitted fits]
    split
    · rfl
    · rename_i rejected
      exact absurd ⟨admitted, by simp, fits, after, by simp⟩ rejected

theorem AbiType.decodeStrict_encode (abiType : AbiType) {value : Value} (before after : Bytes)
    (admitted : abiType.admits value = true) (fits : (before ++ abiType.encode value ++ after).length < 2 ^ 256) :
    abiType.decodeStrict (before ++ abiType.encode value ++ after) before.length = some value :=
  (abiType.decodeStrict_eq_some_iff _ _ _).mpr ⟨admitted, fits, before, after, rfl, rfl⟩

/-- The strict decoder is a special case of the permissive one. -/
theorem AbiType.decodeSolc_of_strict {abiType : AbiType} {data : Bytes} {start : Nat} {value : Value}
    (accepts : abiType.decodeStrict data start = some value) : abiType.decodeSolc data start = value := by
  simp only [AbiType.decodeStrict] at accepts
  split at accepts <;> simp_all

/-! ## Locality -/

theorem advance_lt (position offset : Nat) : advance position offset < 2 ^ 256 :=
  Nat.mod_lt _ (Nat.two_pow_pos 256)

theorem advance_advance (position first second : Nat) :
    advance (advance position first) second = advance position (first + second) := by
  simp only [advance, Nat.mod_add_mod, Nat.add_assoc]

theorem advance_zero {position : Nat} (inRange : position < 2 ^ 256) : advance position 0 = position :=
  Nat.mod_eq_of_lt inRange

theorem AbiType.componentStart_lt (abiType : AbiType) (data : Bytes) (base position offset : Nat) :
    abiType.componentStart data base (advance position offset) < 2 ^ 256 := by
  unfold AbiType.componentStart
  split <;> exact advance_lt _ _

/-- The element at `index` is read from where it starts, `index` heads past the first. -/
theorem decodeElements_getElem? (decodeElement : Nat → Value) (element : AbiType) (data : Bytes) (base : Nat)
    {head : Nat} (inRange : head < 2 ^ 256) (count index : Nat) :
    (decodeElements decodeElement element data base head count)[index]? =
      if index < count then
        some (decodeElement (element.componentStart data base (advance head (index * element.headSize))))
      else none := by
  induction count generalizing head index with
  | zero => simp [decodeElements]
  | succ count rest =>
    cases index with
    | zero => simp [decodeElements, advance_zero inRange]
    | succ index =>
      simp only [decodeElements, List.getElem?_cons_succ, rest (advance_lt _ _), advance_advance,
        Nat.add_lt_add_iff_right, Nat.succ_mul, Nat.add_comm _ element.headSize]

/-- The field at `index` is read from where it starts, past the heads of the fields before it. -/
theorem AbiType.decodeFields_getElem? (fields : List AbiType) (data : Bytes) (base : Nat) {head : Nat}
    (inRange : head < 2 ^ 256) (index : Nat) :
    (AbiType.decodeFields fields data base head)[index]? =
      fields[index]?.map fun field =>
        field.decodeSolc data
          (field.componentStart data base (advance head ((fields.take index).map headSize).sum)) := by
  induction fields generalizing head index with
  | nil => simp [AbiType.decodeFields]
  | cons field fields rest =>
    cases index with
    | zero => simp [AbiType.decodeFields, advance_zero inRange]
    | succ index =>
      simp only [AbiType.decodeFields, List.getElem?_cons_succ, rest (advance_lt _ _), advance_advance,
        List.take_succ_cons, List.map_cons, List.sum_cons]

/-- Locality: the value at a path is the value of the type found there, decoded from where its encoding starts. -/
theorem AbiType.decodeSolc_at (abiType : AbiType) (data : Bytes) {start : Nat} (inRange : start < 2 ^ 256)
    (path : Path) :
    (abiType.decodeSolc data start).at path =
      (abiType.locate data start path).map fun (found, position) => found.decodeSolc data position := by
  induction path generalizing abiType start with
  | nil => simp [Value.at, AbiType.locate]
  | cons step steps rest =>
    cases abiType with
    | word | bytes | string => simp [AbiType.decodeSolc, Value.at, AbiType.locate]
    | staticArray element length =>
      simp only [AbiType.decodeSolc, Value.at, decodeElements_getElem? _ _ _ _ inRange, AbiType.locate]
      split <;> simp [rest _ (AbiType.componentStart_lt _ _ _ _ _)]
    | dynamicArray element =>
      simp only [AbiType.decodeSolc, Value.at, decodeElements_getElem? _ _ _ _ (advance_lt _ _), AbiType.locate]
      split <;> simp [rest _ (AbiType.componentStart_lt _ _ _ _ _)]
    | tuple fields =>
      simp only [AbiType.decodeSolc, Value.at, AbiType.decodeFields_getElem? _ _ _ inRange, AbiType.locate]
      cases fields[step]? <;> simp [rest _ (AbiType.componentStart_lt _ _ _ _ _)]

end Callcium
