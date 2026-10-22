import Callcium.Theorems.Wire
import Callcium.Theorems.Normalize

/-!
# Byte order

Over one signature, the size-free bytes of the encoded rules order them as `Rule.key` does, so the encoder's layout of
`normalize`'s order is the byte order the implementations sort by.
-/

namespace Callcium

/-! ## Lexicographic order -/

/-- The lists differ at a position within both, so neither is a prefix of the other. -/
def Separate {Item : Type} (list other : List Item) : Prop :=
  ∃ common first second rest otherRest, first ≠ second ∧ list = common ++ first :: rest ∧
    other = common ++ second :: otherRest

theorem append_lt_append_left_iff {Item : Type} [LT Item] [Std.Irrefl (α := Item) (· < ·)] (common : List Item)
    {list other : List Item} : common ++ list < common ++ other ↔ list < other := by
  induction common with
  | nil => rfl
  | cons item common shorter => simp [shorter]

theorem Separate.append {Item : Type} {list other : List Item} (separate : Separate list other)
    (tail otherTail : List Item) :
    Separate (list ++ tail) (other ++ otherTail) := by
  obtain ⟨common, first, second, rest, otherRest, differ, rfl, rfl⟩ := separate
  exact ⟨common, first, second, rest ++ tail, otherRest ++ otherTail, differ, by simp, by simp⟩

theorem Separate.prepend {Item : Type} {list other : List Item} (separate : Separate list other) (common : List Item) :
    Separate (common ++ list) (common ++ other) := by
  obtain ⟨prefix_, first, second, rest, otherRest, differ, rfl, rfl⟩ := separate
  exact ⟨common ++ prefix_, first, second, rest, otherRest, differ, by simp, by simp⟩

theorem Separate.ne {Item : Type} {list other : List Item} (separate : Separate list other) : list ≠ other := by
  obtain ⟨common, first, second, rest, otherRest, differ, rfl, rfl⟩ := separate
  intro same
  simp only [List.append_cancel_left_eq, List.cons.injEq] at same
  exact differ same.1

theorem Separate.lt_iff {Item : Type} [LT Item] [Std.Irrefl (α := Item) (· < ·)] {list other : List Item}
    (separate : Separate list other)
    (tail otherTail : List Item) : list ++ tail < other ++ otherTail ↔ list < other := by
  obtain ⟨common, first, second, rest, otherRest, differ, rfl, rfl⟩ := separate
  simp only [List.append_assoc, List.cons_append, append_lt_append_left_iff, List.cons_lt_cons_iff, differ, false_and,
    or_false]

theorem separate_of_length {Item : Type} :
    ∀ {list other : List Item}, list.length = other.length → list ≠ other → Separate list other
  | [], [], _, differ => absurd rfl differ
  | first :: rest, second :: otherRest, sameLength, differ => by
    by_cases same : first = second
    · subst same
      obtain ⟨common, item, otherItem, tail, otherTail, itemsDiffer, rfl, rfl⟩ :=
        separate_of_length (by simpa using sameLength) (by simpa using differ)
      exact ⟨first :: common, item, otherItem, tail, otherTail, itemsDiffer, rfl, rfl⟩
    · exact ⟨[], first, second, rest, otherRest, same, rfl, rfl⟩

/-- A key and its bytes order two items alike: both are equal, or both differ within both lists and in the same
direction. -/
def Agree (key otherKey : List Nat) (bytes otherBytes : Bytes) : Prop :=
  (key = otherKey ∧ bytes = otherBytes) ∨
    (Separate key otherKey ∧ Separate bytes otherBytes ∧ (key < otherKey ↔ bytes < otherBytes))

theorem Agree.refl (key : List Nat) (bytes : Bytes) : Agree key key bytes bytes := Or.inl ⟨rfl, rfl⟩

theorem Agree.lt_iff {key otherKey : List Nat} {bytes otherBytes : Bytes}
    (agree : Agree key otherKey bytes otherBytes) :
    key < otherKey ↔ bytes < otherBytes := by
  rcases agree with ⟨rfl, rfl⟩ | ⟨-, -, order⟩
  · exact ⟨fun less => absurd less (List.lt_irrefl _), fun less => absurd less (List.lt_irrefl _)⟩
  · exact order

theorem Agree.append {key otherKey : List Nat} {bytes otherBytes : Bytes} {tail otherTail : List Nat}
    {byteTail otherByteTail : Bytes} (first : Agree key otherKey bytes otherBytes)
    (second : key = otherKey → bytes = otherBytes → Agree tail otherTail byteTail otherByteTail) :
    Agree (key ++ tail) (otherKey ++ otherTail) (bytes ++ byteTail) (otherBytes ++ otherByteTail) := by
  rcases first with ⟨rfl, rfl⟩ | ⟨keysSeparate, bytesSeparate, order⟩
  · rcases second rfl rfl with ⟨rfl, rfl⟩ | ⟨keysSeparate, bytesSeparate, order⟩
    · exact Or.inl ⟨rfl, rfl⟩
    · exact Or.inr ⟨keysSeparate.prepend _, bytesSeparate.prepend _, by
        rw [append_lt_append_left_iff, append_lt_append_left_iff]; exact order⟩
  · exact Or.inr ⟨keysSeparate.append _ _, bytesSeparate.append _ _, by
      rw [keysSeparate.lt_iff, bytesSeparate.lt_iff]; exact order⟩

theorem agree_of_length {key otherKey : List Nat} {bytes otherBytes : Bytes} (keyLength : key.length = otherKey.length)
    (bytesLength : bytes.length = otherBytes.length) (same : key = otherKey ↔ bytes = otherBytes)
    (order : key < otherKey ↔ bytes < otherBytes) : Agree key otherKey bytes otherBytes := by
  by_cases keysSame : key = otherKey
  · exact Or.inl ⟨keysSame, same.mp keysSame⟩
  · exact Or.inr ⟨separate_of_length keyLength keysSame,
      separate_of_length bytesLength (fun bytesSame => keysSame (same.mpr bytesSame)), order⟩

theorem Agree.flatMap {Item : Type} {keyOf : Item → List Nat} {bytesOf : Item → Bytes} {items : List Item}
    (agree : ∀ item ∈ items, ∀ other ∈ items, Agree (keyOf item) (keyOf other) (bytesOf item) (bytesOf other)) :
    ∀ {first second : List Item}, (∀ item ∈ first, item ∈ items) → (∀ item ∈ second, item ∈ items) →
      first.length = second.length →
      Agree (first.flatMap keyOf) (second.flatMap keyOf) (first.flatMap bytesOf) (second.flatMap bytesOf)
  | [], [], _, _, _ => Agree.refl _ _
  | item :: first, other :: second, inFirst, inSecond, sameLength => by
    simp only [List.flatMap_cons]
    exact Agree.append (agree item (inFirst item (by simp)) other (inSecond other (by simp))) fun _ _ =>
      Agree.flatMap agree (fun inner isMember => inFirst inner (by simp [isMember]))
        (fun inner isMember => inSecond inner (by simp [isMember])) (by simpa using sameLength)


/-! ## Fields -/

theorem beBytes_mod : ∀ (count value : Nat), beBytes count (value % 256 ^ count) = beBytes count value
  | 0, _ => rfl
  | count + 1, value => by
    simp only [beBytes]
    have high : value % 256 ^ (count + 1) / 256 = value / 256 % 256 ^ count := by
      rw [Nat.pow_succ', Nat.mod_mul_right_div_self]
    have low : UInt8.ofNat (value % 256 ^ (count + 1)) = UInt8.ofNat value := by
      apply UInt8.toNat_inj.mp
      simp only [UInt8.toNat_ofNat', Nat.pow_succ]
      exact Nat.mod_mul_left_mod value _ 256
    rw [high, low, beBytes_mod count (value / 256)]

theorem beBytes_inj {count value other : Nat} (fits : value < 256 ^ count) (otherFits : other < 256 ^ count)
    (same : beBytes count value = beBytes count other) : value = other := by
  have := congrArg beNat same
  rwa [beNat_beBytes, beNat_beBytes, Nat.mod_eq_of_lt fits, Nat.mod_eq_of_lt otherFits] at this

theorem UInt8.ofNat_lt_ofNat_iff {value other : Nat} (fits : value < 256) (otherFits : other < 256) :
    UInt8.ofNat value < UInt8.ofNat other ↔ value < other := by
  simp [UInt8.lt_iff_toNat_lt, UInt8.toNat_ofNat', Nat.mod_eq_of_lt fits, Nat.mod_eq_of_lt otherFits]

theorem beBytes_lt_iff : ∀ (count : Nat) {value other : Nat}, value < 256 ^ count → other < 256 ^ count →
    (beBytes count value < beBytes count other ↔ value < other)
  | 0, value, other, fits, otherFits => by
    simp only [Nat.pow_zero, Nat.lt_one_iff] at fits otherFits
    subst fits otherFits
    simp [beBytes]
  | count + 1, value, other, fits, otherFits => by
    simp only [beBytes]
    have highFits : value / 256 < 256 ^ count := by rw [Nat.div_lt_iff_lt_mul (by decide)]; rwa [← Nat.pow_succ]
    have otherHighFits : other / 256 < 256 ^ count := by
      rw [Nat.div_lt_iff_lt_mul (by decide)]; rwa [← Nat.pow_succ]
    by_cases same : value / 256 = other / 256
    · rw [same, append_lt_append_left_iff, List.cons_lt_cons_iff]
      simp only [List.not_lt_nil, and_false, or_false, UInt8.lt_iff_toNat_lt, UInt8.toNat_ofNat']
      omega
    · have separate : Separate (beBytes count (value / 256)) (beBytes count (other / 256)) :=
        separate_of_length (by simp [beBytes_length]) fun bytesSame =>
          same (beBytes_inj highFits otherHighFits bytesSame)
      rw [separate.lt_iff, beBytes_lt_iff count highFits otherHighFits]
      omega

/-- Two one-entry keys and two one-byte encodings that agree on equality and order agree. -/
theorem agree_single {key otherKey : Nat} {byte otherByte : UInt8} (same : key = otherKey ↔ byte = otherByte)
    (order : key < otherKey ↔ byte < otherByte) : Agree [key] [otherKey] [byte] [otherByte] :=
  agree_of_length rfl rfl (by simpa using same) (by simpa [List.cons_lt_cons_iff] using order)

theorem agree_byte {value other : Nat} (fits : value < 256) (otherFits : other < 256) :
    Agree [value] [other] [UInt8.ofNat value] [UInt8.ofNat other] :=
  agree_single
    ⟨fun same => same ▸ rfl, fun same => by
      have := congrArg UInt8.toNat same
      simpa [UInt8.toNat_ofNat', Nat.mod_eq_of_lt fits, Nat.mod_eq_of_lt otherFits] using this⟩
    (UInt8.ofNat_lt_ofNat_iff fits otherFits).symm

theorem agree_field {count value other : Nat} (fits : value < 256 ^ count) (otherFits : other < 256 ^ count) :
    Agree [value] [other] (beBytes count value) (beBytes count other) :=
  agree_of_length rfl (by simp [beBytes_length])
    ⟨fun same => by simp_all, fun same => by simpa using beBytes_inj fits otherFits same⟩
    (by simpa [List.cons_lt_cons_iff] using (beBytes_lt_iff count fits otherFits).symm)

/-! ## Operands -/

theorem byte_pow (count : Nat) : (256 : Nat) ^ count = 2 ^ (8 * count) := by
  rw [Nat.pow_mul]

/-- A canonical `intN` word is its low bits, raised by `2 ^ 256 - 2 ^ N` when the sign bit is set. -/
theorem WordType.int_toNat {width : ByteWidth} {word : Word}
    (canonical : (WordType.int width).isCanonical word = true) :
    word.toNat = word.toNat % 2 ^ width.bits +
      if 2 ^ (width.bits - 1) ≤ word.toNat % 2 ^ width.bits then 2 ^ 256 - 2 ^ width.bits else 0 := by
  simp only [WordType.isCanonical, beq_iff_eq, Word.signExtendFrom] at canonical
  have widthLe : width.bits ≤ 256 := by have := width.index.isLt; simp only [ByteWidth.bits]; omega
  have lowFits : word.toNat % 2 ^ width.bits < 2 ^ 256 :=
    Nat.lt_of_lt_of_le (Nat.mod_lt _ (Nat.two_pow_pos _)) (Nat.pow_le_pow_right (by decide) widthLe)
  conv => lhs; rw [← canonical]
  rw [BitVec.toNat_signExtend, BitVec.msb_eq_decide]
  simp [BitVec.toNat_setWidth, Nat.mod_eq_of_lt lowFits]

theorem div_lt_div_iff_of_mod {value other divisor : Nat} (positive : 0 < divisor) (divides : value % divisor = 0)
    (otherDivides : other % divisor = 0) : value / divisor < other / divisor ↔ value < other := by
  obtain ⟨quotient, rfl⟩ := Nat.dvd_of_mod_eq_zero divides
  obtain ⟨otherQuotient, rfl⟩ := Nat.dvd_of_mod_eq_zero otherDivides
  rw [Nat.mul_div_cancel_left _ positive, Nat.mul_div_cancel_left _ positive, Nat.mul_lt_mul_left positive]

/-- Operand bytes order canonical words as their values, compared unsigned. -/
theorem WordType.narrow_lt_iff {wordType : WordType} {word other : Word} (canonical : wordType.isCanonical word = true)
    (otherCanonical : wordType.isCanonical other = true) :
    wordType.narrow word < wordType.narrow other ↔ word.toNat < other.toNat := by
  have rightAligned : ∀ {width : Nat}, word.toNat < 2 ^ (8 * width) → other.toNat < 2 ^ (8 * width) →
      (beBytes width (word.toNat / 2 ^ 0) < beBytes width (other.toNat / 2 ^ 0) ↔ word.toNat < other.toNat) := by
    intro width below otherBelow
    rw [Nat.pow_zero, Nat.div_one, Nat.div_one]
    exact beBytes_lt_iff width (by rwa [byte_pow]) (by rwa [byte_pow])
  have leftAligned : ∀ {width : Nat}, 8 * width ≤ 256 → word.toNat % 2 ^ (256 - 8 * width) = 0 →
      other.toNat % 2 ^ (256 - 8 * width) = 0 →
      (beBytes width (word.toNat / 2 ^ (256 - 8 * width)) < beBytes width (other.toNat / 2 ^ (256 - 8 * width)) ↔
        word.toNat < other.toNat) := by
    intro width le lowZero otherLowZero
    have fits : ∀ value : Word, value.toNat / 2 ^ (256 - 8 * width) < 256 ^ width := by
      intro value
      rw [Nat.div_lt_iff_lt_mul (Nat.two_pow_pos _), byte_pow, ← Nat.pow_add,
        show 8 * width + (256 - 8 * width) = 256 by omega]
      exact value.isLt
    rw [beBytes_lt_iff width (fits word) (fits other)]
    exact div_lt_div_iff_of_mod (Nat.two_pow_pos _) lowZero otherLowZero
  cases wordType with
  | uint width =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical otherCanonical
    exact rightAligned (below_of_shiftRight canonical) (below_of_shiftRight otherCanonical)
  | address =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical otherCanonical
    exact rightAligned (width := 20) (below_of_shiftRight canonical) (below_of_shiftRight otherCanonical)
  | bool =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical otherCanonical
    exact rightAligned (width := 1) (Nat.lt_of_lt_of_le (below_of_shiftRight canonical) (by decide))
      (Nat.lt_of_lt_of_le (below_of_shiftRight otherCanonical) (by decide))
  | function =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical otherCanonical
    exact leftAligned (width := 24) (by decide) (lowZero_of_shiftLeft (by decide) canonical)
      (lowZero_of_shiftLeft (by decide) otherCanonical)
  | fixedBytes width =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical otherCanonical
    have widthLe : width.bits ≤ 256 := by have := width.index.isLt; simp only [ByteWidth.bits]; omega
    have lowZero := lowZero_of_shiftLeft widthLe canonical
    have otherLowZero := lowZero_of_shiftLeft widthLe otherCanonical
    simp only [ByteWidth.bits] at lowZero otherLowZero widthLe
    exact leftAligned widthLe lowZero otherLowZero
  | int width =>
    have toNat := WordType.int_toNat canonical
    have otherToNat := WordType.int_toNat otherCanonical
    have widthLe : width.bits ≤ 256 := by have := width.index.isLt; simp only [ByteWidth.bits]; omega
    have widthPos : 8 ≤ width.bits := by simp only [ByteWidth.bits]; omega
    have bytesWidth : (256 : Nat) ^ (width.index.val + 1) = 2 ^ width.bits := by
      rw [ByteWidth.bits, Nat.pow_mul]
    have half : 2 ^ width.bits = 2 * 2 ^ (width.bits - 1) := by
      rw [← Nat.pow_succ']; congr 1
    have bounded : 2 ^ width.bits ≤ 2 ^ 256 := Nat.pow_le_pow_right (by decide) widthLe
    have low := Nat.mod_lt word.toNat (Nat.two_pow_pos width.bits)
    have otherLow := Nat.mod_lt other.toNat (Nat.two_pow_pos width.bits)
    simp only [WordType.narrow, WordType.shift, WordType.leftAligned, WordType.width, Bool.false_eq_true,
      ↓reduceIte, Nat.pow_zero, Nat.div_one]
    rw [← beBytes_mod _ word.toNat, ← beBytes_mod _ other.toNat, bytesWidth,
      beBytes_lt_iff _ (by rw [bytesWidth]; exact low) (by rw [bytesWidth]; exact otherLow)]
    split at toNat <;> split at otherToNat <;> omega

theorem agree_narrow {wordType : WordType} {word other : Word} (canonical : wordType.isCanonical word = true)
    (otherCanonical : wordType.isCanonical other = true) :
    Agree [word.toNat] [other.toNat] (wordType.narrow word) (wordType.narrow other) :=
  agree_of_length rfl (by simp [WordType.narrow_length])
    ⟨fun same => by simp_all [BitVec.toNat_inj], fun same => by
      have := congrArg wordType.load same
      rw [WordType.load_narrow canonical, WordType.load_narrow otherCanonical] at this
      rw [this]⟩
    (by simpa [List.cons_lt_cons_iff] using (WordType.narrow_lt_iff canonical otherCanonical).symm)

theorem agree_scaled {count scale value other : Nat} (positive : 0 < scale) (fits : value * scale < 256 ^ count)
    (otherFits : other * scale < 256 ^ count) :
    Agree [value] [other] (beBytes count (value * scale)) (beBytes count (other * scale)) :=
  agree_of_length rfl (by simp [beBytes_length])
    ⟨fun same => by simp_all, fun same => by
      simpa [Nat.mul_right_cancel_iff positive] using beBytes_inj fits otherFits same⟩
    (by simpa [List.cons_lt_cons_iff, beBytes_lt_iff count fits otherFits] using
      (Nat.mul_lt_mul_right positive).symm)

/-! ## Operators -/

theorem Comparison.code_lt_iff (comparison other : Comparison) :
    comparison.code.toNat < other.code.toNat ↔ comparison.ctorIdx < other.ctorIdx := by
  cases comparison <;> cases other <;> decide

theorem Comparison.code_eq_iff (comparison other : Comparison) :
    comparison.code.toNat = other.code.toNat ↔ comparison.ctorIdx = other.ctorIdx := by
  cases comparison <;> cases other <;> decide

theorem agree_opCode (operator other : Operator) :
    Agree [operator.negated.toNat, operator.operand.source, operator.comparison.ctorIdx]
      [other.negated.toNat, other.operand.source, other.comparison.ctorIdx] [operator.opCode] [other.opCode] := by
  have codeLt := Comparison.code_lt_iff operator.comparison other.comparison
  have codeEq := Comparison.code_eq_iff operator.comparison other.comparison
  have codeFits := operator.comparison.code_lt
  have otherCodeFits := other.comparison.code_lt
  have sourceLe : operator.operand.source ≤ 1 := by cases operator.operand <;> simp [Operand.source]
  have otherSourceLe : other.operand.source ≤ 1 := by cases other.operand <;> simp [Operand.source]
  have negatedLe := Bool.toNat_le operator.negated
  have otherNegatedLe := Bool.toNat_le other.negated
  simp only [SOURCE_SHIFT] at codeFits otherCodeFits
  refine agree_of_length rfl rfl ?_ ?_
  · simp only [List.cons.injEq, and_true, Operator.opCode, ← UInt8.toNat_inj, UInt8.toNat_ofNat', NOT_FLAG,
      SOURCE_SHIFT]
    omega
  · simp only [List.cons_lt_cons_iff, List.not_lt_nil, and_false, or_false, Operator.opCode, UInt8.lt_iff_toNat_lt,
      UInt8.toNat_ofNat', NOT_FLAG, SOURCE_SHIFT]
    omega

/-- Two operators that compare a target of type code `code` and fit order by their bytes as by their keys. -/
theorem Operator.agree {operator other : Operator} {code : UInt8} (compares : operator.compares code = true)
    (otherCompares : other.compares code = true) (fits : operator.fits code = true)
    (otherFits : other.fits code = true) : Agree operator.key other.key (operator.write code) (other.write code) := by
  have keySplit : ∀ operator : Operator, operator.key =
      [operator.negated.toNat, operator.operand.source, operator.comparison.ctorIdx] ++ operator.operand.key :=
    fun _ => rfl
  have writeSplit : ∀ operator : Operator, operator.write code =
      [operator.opCode] ++ (beBytes 2 (operator.data code).length ++ operator.data code) := fun _ => rfl
  rw [keySplit, keySplit, writeSplit, writeSplit]
  refine Agree.append (agree_opCode operator other) fun same _ => ?_
  simp only [List.cons.injEq, and_true] at same
  obtain ⟨-, sameSource, sameComparison⟩ := same
  rcases operator with ⟨negated, comparison, operand⟩
  rcases other with ⟨otherNegated, otherComparison, otherOperand⟩
  simp only at sameSource sameComparison ⊢
  obtain rfl := Comparison.ctorIdx_inj sameComparison
  obtain ⟨wordType, typed⟩ : ∃ wordType, operandType comparison code = some wordType := by
    cases typed : operandType comparison code <;> simp_all [Operator.compares]
  simp only [Operator.fits, Bool.and_eq_true, decide_eq_true_eq] at fits otherFits
  rcases operand with values | property <;> rcases otherOperand with otherValues | otherProperty <;>
    simp only [Operand.source] at sameSource
  · -- Constant operands.
    have canonical : ∀ value ∈ values ++ otherValues, wordType.isCanonical value = true := by
      simp only [Operator.compares, typed, List.all_eq_true] at compares otherCompares
      intro value isMember
      rcases List.mem_append.mp isMember with isMember | isMember
      · exact compares value isMember
      · exact otherCompares value isMember
    have data : ∀ (negated : Bool) (values : List Word),
        Operator.data ⟨negated, comparison, .constant values⟩ code = values.flatMap wordType.narrow := by
      intro negated values
      simp [Operator.data, typed]
    simp only [data, WordType.flatMap_narrow_length] at fits otherFits ⊢
    have keySplit : ∀ values : List Word, Operand.key (.constant values) =
        [values.length] ++ values.flatMap fun value => [value.toNat] := by
      intro values
      simp only [Operand.key, List.singleton_append, List.cons.injEq, true_and]
      induction values <;> simp_all
    rw [keySplit, keySplit]
    refine Agree.append (agree_scaled (count := 2) wordType.width_pos (by simpa using fits.2)
        (by simpa using otherFits.2))
      fun sameLength _ => ?_
    exact Agree.flatMap (items := values ++ otherValues)
      (fun value isMember other isOther => agree_narrow (canonical value isMember) (canonical other isOther))
      (fun value isMember => List.mem_append_left _ isMember) (fun value isMember => List.mem_append_right _ isMember)
      (by simpa using sameLength)
  · omega
  · omega
  · -- Context property operands.
    simp only [Operator.data, Operand.key, beBytes_length]
    exact Agree.append (key := []) (otherKey := []) (Agree.refl [] _) fun _ _ =>
      agree_field (by simpa using fits.1) (by simpa using otherFits.1)

/-! ## Rules -/

theorem Agree.prepend_bytes {key otherKey : List Nat} {bytes otherBytes : Bytes} (common : Bytes)
    (agree : Agree key otherKey bytes otherBytes) : Agree key otherKey (common ++ bytes) (common ++ otherBytes) := by
  simpa using Agree.append (key := []) (otherKey := []) (Agree.refl [] common) fun _ _ => agree

theorem agree_path {path other : Path} (fits : Path.fits path = true) (otherFits : Path.fits other = true) :
    Agree (path.length :: path) (other.length :: other) (writePath path) (writePath other) := by
  simp only [Path.fits, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at fits otherFits
  have split : ∀ path : Path, path.length :: path = [path.length] ++ path.flatMap fun step => [step] := by
    intro path
    simp
  rw [split, split, writePath, writePath, ← List.singleton_append, ← List.singleton_append (l := other.flatMap _)]
  refine Agree.append (agree_byte fits.1 otherFits.1) fun same _ => ?_
  exact Agree.flatMap (items := path ++ other)
    (fun step isMember otherStep isOther => agree_field (count := 2)
      (by rcases List.mem_append.mp isMember with isMember | isMember
          · simpa using fits.2 step isMember
          · simpa using otherFits.2 step isMember)
      (by rcases List.mem_append.mp isOther with isOther | isOther
          · simpa using fits.2 otherStep isOther
          · simpa using otherFits.2 otherStep isOther))
    (fun step isMember => List.mem_append_left _ isMember) (fun step isMember => List.mem_append_right _ isMember)
    (by simpa using same)

theorem Rule.compileTest_shape {start : AbiType} {rule : Rule} {test : CompiledTest}
    (compiled : rule.compileTest start = some test) :
    (∃ property operator, rule = .contextTest property operator ∧ test = .contextTest property operator ∧
        operator.compares (contextPropertyType property).code = true) ∨
      ∃ path operator hint, rule = .test path operator ∧ start.compile? path = some hint ∧
        test = .test path hint.wire operator ∧ operator.compares hint.target.code = true := by
  cases rule with
  | contextTest property operator =>
    simp only [Rule.compileTest] at compiled
    split at compiled
    case isFalse => contradiction
    cases compiled
    exact Or.inl ⟨_, _, rfl, rfl, by assumption⟩
  | test path operator =>
    simp only [Rule.compileTest, Option.bind_eq_some_iff] at compiled
    obtain ⟨hint, compiledHint, compiled⟩ := compiled
    split at compiled
    case isFalse => contradiction
    cases compiled
    exact Or.inr ⟨_, _, _, rfl, compiledHint, rfl, by assumption⟩
  | loop => simp [Rule.compileTest] at compiled

/-- Two tests compiled from one starting point order by their size-free bytes as by their keys. -/
theorem agree_compileTest {start : AbiType} {rule other : Rule} {test otherTest : CompiledTest}
    (compiled : rule.compileTest start = some test) (otherCompiled : other.compileTest start = some otherTest)
    (fits : test.fits = true) (otherFits : otherTest.fits = true) :
    Agree rule.key other.key test.sizeFree otherTest.sizeFree := by
  rcases Rule.compileTest_shape compiled with
    ⟨property, operator, rfl, rfl, compares⟩ | ⟨path, operator, hint, rfl, compiledHint, rfl, compares⟩ <;>
  rcases Rule.compileTest_shape otherCompiled with
    ⟨otherProperty, otherOperator, rfl, rfl, otherCompares⟩ |
      ⟨otherPath, otherOperator, otherHint, rfl, otherCompiledHint, rfl, otherCompares⟩ <;>
  simp only [CompiledTest.fits, Bool.and_eq_true, decide_eq_true_eq] at fits otherFits
  · -- Two context tests.
    show Agree ([0] ++ ([property] ++ operator.key)) ([0] ++ ([otherProperty] ++ otherOperator.key))
      ([UInt8.ofNat 0] ++ ([1] ++ (beBytes 2 property ++ operator.write (contextPropertyType property).code)))
      ([UInt8.ofNat 0] ++ ([1] ++ (beBytes 2 otherProperty ++
        otherOperator.write (contextPropertyType otherProperty).code)))
    refine Agree.append (agree_byte (by decide) (by decide)) fun _ _ => Agree.prepend_bytes [1] ?_
    refine Agree.append (agree_field (count := 2) fits.2.1 otherFits.2.1) fun same _ => ?_
    obtain rfl : property = otherProperty := by simpa using same
    exact Operator.agree compares otherCompares fits.2.2 otherFits.2.2
  · show Agree ([0] ++ _) ([1] ++ _) ([UInt8.ofNat 0] ++ _) ([UInt8.ofNat 1] ++ _)
    exact Agree.append (agree_byte (by decide) (by decide)) fun same => by simp at same
  · show Agree ([1] ++ _) ([0] ++ _) ([UInt8.ofNat 1] ++ _) ([UInt8.ofNat 0] ++ _)
    exact Agree.append (agree_byte (by decide) (by decide)) fun same => by simp at same
  · -- Two calldata tests.
    show Agree ([1] ++ ((path.length :: path) ++ operator.key))
      ([1] ++ ((otherPath.length :: otherPath) ++ otherOperator.key))
      ([UInt8.ofNat 1] ++ (writePath path ++ hint.wire.write ++ operator.write hint.wire.typeCode))
      ([UInt8.ofNat 1] ++ (writePath otherPath ++ otherHint.wire.write ++ otherOperator.write otherHint.wire.typeCode))
    simp only [List.append_assoc]
    refine Agree.append (agree_byte (by decide) (by decide)) fun _ _ => ?_
    refine Agree.append (agree_path fits.2.1.1 otherFits.2.1.1) fun same _ => ?_
    obtain rfl : path = otherPath := (List.cons.inj same).2
    obtain rfl : hint = otherHint := Option.some.inj (compiledHint.symm.trans otherCompiledHint)
    exact Agree.prepend_bytes _ (Operator.agree compares otherCompares fits.2.2 otherFits.2.2)

theorem Quantifier.agree (quantifier other : Quantifier) :
    Agree [quantifier.ctorIdx] [other.ctorIdx] [quantifier.code] [other.code] :=
  agree_single (by cases quantifier <;> cases other <;> decide) (by cases quantifier <;> cases other <;> decide)

theorem Group.keyOf_eq_flatMap (group : Group) : Group.keyOf group = group.flatMap Rule.key := by
  induction group with
  | nil => rfl
  | cons rule rules shorter => simp [Group.keyOf, shorter]

theorem mapM_mem {Item Result : Type} {function : Item → Option Result} :
    ∀ {items : List Item} {results : List Result}, items.mapM function = some results →
      ∀ item ∈ items, ∃ result ∈ results, function item = some result
  | [], _, _, _, isMember => by simp at isMember
  | item :: items, results, mapped, member, isMember => by
    obtain ⟨first, rest, mapsFirst, mapsRest, rfl⟩ := mapM_cons_eq_some.mp mapped
    rcases List.mem_cons.mp isMember with rfl | isMember
    · exact ⟨first, by simp, mapsFirst⟩
    · obtain ⟨result, isResult, maps⟩ := mapM_mem mapsRest member isMember
      exact ⟨result, by simp [isResult], maps⟩

theorem mapM_mem_results {Item Result : Type} {function : Item → Option Result} :
    ∀ {items : List Item} {results : List Result}, items.mapM function = some results →
      ∀ result ∈ results, ∃ item ∈ items, function item = some result
  | [], results, mapped, _, isResult => by simp_all
  | item :: items, results, mapped, result, isResult => by
    obtain ⟨first, rest, mapsFirst, mapsRest, rfl⟩ := mapM_cons_eq_some.mp mapped
    rcases List.mem_cons.mp isResult with rfl | isResult
    · exact ⟨item, by simp, mapsFirst⟩
    · obtain ⟨member, isMember, maps⟩ := mapM_mem_results mapsRest result isResult
      exact ⟨member, by simp [isMember], maps⟩

theorem mapM_flatMap {Item Result Other : Type} {function : Item → Option Result} {bytesOf : Result → List Other} :
    ∀ {items : List Item} {results : List Result}, items.mapM function = some results →
      results.flatMap bytesOf = items.flatMap fun item => ((function item).map bytesOf).getD []
  | [], results, mapped => by simp_all
  | item :: items, results, mapped => by
    obtain ⟨first, rest, mapsFirst, mapsRest, rfl⟩ := mapM_cons_eq_some.mp mapped
    simp [mapsFirst, mapM_flatMap mapsRest]

theorem mapM_pairwise {Item Result : Type} {function : Item → Option Result} {before : Item → Item → Prop}
    {after : Result → Result → Prop} :
    ∀ {items : List Item} {results : List Result}, items.mapM function = some results →
      (∀ item other result otherResult, result ∈ results → otherResult ∈ results → function item = some result →
        function other = some otherResult → before item other → after result otherResult) →
      items.Pairwise before → results.Pairwise after
  | [], results, mapped, _, _ => by simp_all
  | item :: items, results, mapped, transfer, sorted => by
    obtain ⟨first, rest, mapsFirst, mapsRest, rfl⟩ := mapM_cons_eq_some.mp mapped
    rw [List.pairwise_cons] at sorted ⊢
    refine ⟨fun result isResult => ?_, mapM_pairwise mapsRest (fun inner other result otherResult isResult isOther =>
      transfer inner other result otherResult (by simp [isResult]) (by simp [isOther])) sorted.2⟩
    obtain ⟨other, isOther, mapsOther⟩ := mapM_mem_results mapsRest result isResult
    exact transfer item other first result (by simp) (by simp [isResult]) mapsFirst mapsOther (sorted.1 other isOther)

theorem Rule.compile_shape {start : AbiType} {rule : Rule} {compiled : CompiledRule}
    (compiledEq : rule.compile start = some compiled) :
    (∃ test, rule.compileTest start = some test ∧ compiled = .test test) ∨
      ∃ quantifier arrayPath body hint compiledBody, rule = .loop quantifier arrayPath body ∧
        start.compileLoop? arrayPath = some hint ∧ body.mapM (Rule.compileTest hint.element) = some compiledBody ∧
        compiled = .loop quantifier arrayPath hint.frame compiledBody := by
  cases rule
  case loop quantifier arrayPath body =>
    simp only [Rule.compile, Option.bind_eq_some_iff, Option.map_eq_some_iff] at compiledEq
    obtain ⟨hint, compiledHint, compiledBody, bodyCompiled, rfl⟩ := compiledEq
    exact Or.inr ⟨_, _, _, _, _, rfl, compiledHint, bodyCompiled, rfl⟩
  all_goals
    simp only [Rule.compile, Option.map_eq_some_iff] at compiledEq
    obtain ⟨test, compiledTest, rfl⟩ := compiledEq
    exact Or.inl ⟨test, compiledTest, rfl⟩

/-- A test leads its key and its bytes with its scope, below a loop's. -/
theorem Rule.agree_test_loop {start : AbiType} {rule : Rule} {test : CompiledTest} {key : List Nat} {bytes : Bytes}
    (compiled : rule.compileTest start = some test) :
    Agree rule.key (2 :: key) test.sizeFree (SCOPE_LOOP :: bytes) ∧
      Agree (2 :: key) rule.key (SCOPE_LOOP :: bytes) test.sizeFree := by
  rcases Rule.compileTest_shape compiled with ⟨property, operator, rfl, rfl, -⟩ | ⟨path, operator, hint, rfl, -, rfl, -⟩
  · exact ⟨Agree.append (key := [0]) (otherKey := [2]) (bytes := [UInt8.ofNat 0]) (otherBytes := [UInt8.ofNat 2])
        (agree_byte (by decide) (by decide)) fun same => by simp at same,
      Agree.append (key := [2]) (otherKey := [0]) (bytes := [UInt8.ofNat 2]) (otherBytes := [UInt8.ofNat 0])
        (agree_byte (by decide) (by decide)) fun same => by simp at same⟩
  · exact ⟨Agree.append (key := [1]) (otherKey := [2]) (bytes := [UInt8.ofNat 1]) (otherBytes := [UInt8.ofNat 2])
        (agree_byte (by decide) (by decide)) fun same => by simp at same,
      Agree.append (key := [2]) (otherKey := [1]) (bytes := [UInt8.ofNat 2]) (otherBytes := [UInt8.ofNat 1])
        (agree_byte (by decide) (by decide)) fun same => by simp at same⟩

/-- Two rules compiled from one starting point order by their size-free bytes as by their keys. -/
theorem agree_compile {start : AbiType} {rule other : Rule} {compiled compiledOther : CompiledRule}
    (compiledEq : rule.compile start = some compiled) (otherCompiled : other.compile start = some compiledOther)
    (fits : compiled.fits = true) (otherFits : compiledOther.fits = true) :
    Agree rule.key other.key compiled.sizeFree compiledOther.sizeFree := by
  rcases Rule.compile_shape compiledEq with ⟨test, compiledTest, rfl⟩ |
    ⟨quantifier, arrayPath, body, hint, compiledBody, rfl, compiledHint, bodyCompiled, rfl⟩ <;>
  rcases Rule.compile_shape otherCompiled with ⟨otherTest, otherCompiledTest, rfl⟩ |
    ⟨otherQuantifier, otherArrayPath, otherBody, otherHint, otherCompiledBody, rfl, otherCompiledHint,
      otherBodyCompiled, rfl⟩ <;>
  simp only [CompiledRule.fits, Bool.and_eq_true, decide_eq_true_eq] at fits otherFits
  · exact agree_compileTest compiledTest otherCompiledTest fits.2 otherFits.2
  · exact (Rule.agree_test_loop compiledTest).1
  · exact (Rule.agree_test_loop otherCompiledTest).2
  · -- Two loops.
    obtain ⟨-, ⟨⟨pathFits, -⟩, countFits⟩, bodyFits⟩ := fits
    obtain ⟨-, ⟨⟨otherPathFits, -⟩, otherCountFits⟩, otherBodyFits⟩ := otherFits
    simp only [List.all_eq_true] at bodyFits otherBodyFits
    show Agree ([2] ++ ([quantifier.ctorIdx] ++ ((arrayPath.length :: arrayPath) ++
        ([body.length] ++ Group.keyOf body))))
      ([2] ++ ([otherQuantifier.ctorIdx] ++ ((otherArrayPath.length :: otherArrayPath) ++
        ([otherBody.length] ++ Group.keyOf otherBody))))
      ([UInt8.ofNat 2] ++ ([quantifier.code] ++ (writePath arrayPath ++ hint.frame.write ++
        beBytes 2 compiledBody.length ++ compiledBody.flatMap CompiledTest.sizeFree)))
      ([UInt8.ofNat 2] ++ ([otherQuantifier.code] ++ (writePath otherArrayPath ++ otherHint.frame.write ++
        beBytes 2 otherCompiledBody.length ++ otherCompiledBody.flatMap CompiledTest.sizeFree)))
    simp only [List.append_assoc]
    refine Agree.append (agree_byte (by decide) (by decide)) fun _ _ => ?_
    refine Agree.append (Quantifier.agree quantifier otherQuantifier) fun _ _ => ?_
    refine Agree.append (agree_path pathFits otherPathFits) fun same _ => ?_
    obtain rfl : arrayPath = otherArrayPath := (List.cons.inj same).2
    obtain rfl : hint = otherHint := Option.some.inj (compiledHint.symm.trans otherCompiledHint)
    refine Agree.prepend_bytes _ ?_
    rw [mapM_length bodyCompiled] at countFits ⊢
    rw [mapM_length otherBodyCompiled] at otherCountFits ⊢
    refine Agree.append (agree_field (count := 2) (by simpa using countFits) (by simpa using otherCountFits))
      fun sameLength _ => ?_
    rw [Group.keyOf_eq_flatMap, Group.keyOf_eq_flatMap, mapM_flatMap bodyCompiled, mapM_flatMap otherBodyCompiled]
    have bodyAgree : ∀ inner ∈ body ++ otherBody,
        ∃ test, inner.compileTest hint.element = some test ∧ test.fits = true := by
      intro inner isMember
      rcases List.mem_append.mp isMember with isMember | isMember
      · obtain ⟨test, isTest, compiledTest⟩ := mapM_mem bodyCompiled inner isMember
        exact ⟨test, compiledTest, bodyFits test isTest⟩
      · obtain ⟨test, isTest, compiledTest⟩ := mapM_mem otherBodyCompiled inner isMember
        exact ⟨test, compiledTest, otherBodyFits test isTest⟩
    refine Agree.flatMap (items := body ++ otherBody) (fun inner isMember other isOther => ?_)
      (fun inner isMember => List.mem_append_left _ isMember) (fun inner isMember => List.mem_append_right _ isMember)
      (by simpa using sameLength)
    obtain ⟨test, compiledTest, testFits⟩ := bodyAgree inner isMember
    obtain ⟨otherTest, otherCompiledTest, otherTestFits⟩ := bodyAgree other isOther
    simpa [compiledTest, otherCompiledTest] using
      agree_compileTest compiledTest otherCompiledTest testFits otherTestFits

/-- Over one starting point, two rules order by their size-free bytes as by their keys. -/
theorem Rule.key_lt_iff_sizeFree_lt {start : AbiType} {rule other : Rule} {compiled compiledOther : CompiledRule}
    (compiledEq : rule.compile start = some compiled) (otherCompiled : other.compile start = some compiledOther)
    (fits : compiled.fits = true) (otherFits : compiledOther.fits = true) :
    rule.key < other.key ↔ compiled.sizeFree < compiledOther.sizeFree :=
  (agree_compile compiledEq otherCompiled fits otherFits).lt_iff

/-! ## Groups and policies -/

theorem nil_lt_of_ne_nil {Item : Type} [LT Item] : ∀ {list : List Item}, list ≠ [] → [] < list
  | [], nonempty => absurd rfl nonempty
  | item :: rest, _ => List.nil_lt_cons item rest

/-- Concatenations of items whose keys and bytes agree pairwise, and are never empty, order alike. -/
theorem flatMap_lt_iff {Item : Type} {keyOf : Item → List Nat} {bytesOf : Item → Bytes} {items : List Item}
    (agree : ∀ item ∈ items, ∀ other ∈ items, Agree (keyOf item) (keyOf other) (bytesOf item) (bytesOf other))
    (keyNonempty : ∀ item ∈ items, keyOf item ≠ []) (bytesNonempty : ∀ item ∈ items, bytesOf item ≠ []) :
    ∀ {first second : List Item}, (∀ item ∈ first, item ∈ items) → (∀ item ∈ second, item ∈ items) →
      (first.flatMap keyOf < second.flatMap keyOf ↔ first.flatMap bytesOf < second.flatMap bytesOf)
  | [], [], _, _ => by simp [List.lt_irrefl]
  | [], other :: second, _, inSecond => by
    have isOther := inSecond other (by simp)
    simp only [List.flatMap_nil, List.flatMap_cons]
    exact ⟨fun _ => nil_lt_of_ne_nil (by simp [bytesNonempty other isOther]),
      fun _ => nil_lt_of_ne_nil (by simp [keyNonempty other isOther])⟩
  | item :: first, [], _, _ => by simp [List.not_lt_nil]
  | item :: first, other :: second, inFirst, inSecond => by
    simp only [List.flatMap_cons]
    rcases agree item (inFirst item (by simp)) other (inSecond other (by simp)) with
      ⟨sameKey, sameBytes⟩ | ⟨keysSeparate, bytesSeparate, order⟩
    · rw [sameKey, sameBytes, append_lt_append_left_iff, append_lt_append_left_iff]
      exact flatMap_lt_iff agree keyNonempty bytesNonempty (fun inner isMember => inFirst inner (by simp [isMember]))
        (fun inner isMember => inSecond inner (by simp [isMember]))
    · rw [keysSeparate.lt_iff, bytesSeparate.lt_iff]
      exact order

theorem Rule.key_ne_nil (rule : Rule) : rule.key ≠ [] := by
  cases rule <;> simp [Rule.key]

theorem CompiledRule.sizeFree_ne_nil (rule : CompiledRule) : rule.sizeFree ≠ [] := by
  cases rule <;> simp [CompiledRule.sizeFree, CompiledRule.content, CompiledTest.sizeFree]

/-- Two groups compiled from one starting point order by the concatenation of their rules' size-free bytes as by their
keys. -/
theorem Group.keyOf_lt_iff {start : AbiType} {group other : Group} {rules otherRules : List CompiledRule}
    (compiled : group.mapM (Rule.compile start) = some rules)
    (otherCompiled : other.mapM (Rule.compile start) = some otherRules) (fit : ∀ rule ∈ rules, rule.fits = true)
    (otherFit : ∀ rule ∈ otherRules, rule.fits = true) :
    Group.keyOf group < Group.keyOf other ↔
      rules.flatMap CompiledRule.sizeFree < otherRules.flatMap CompiledRule.sizeFree := by
  have compiles : ∀ rule ∈ group ++ other, ∃ compiledRule, rule.compile start = some compiledRule ∧
      compiledRule.fits = true := by
    intro rule isMember
    rcases List.mem_append.mp isMember with isMember | isMember
    · obtain ⟨compiledRule, isCompiled, compiledEq⟩ := mapM_mem compiled rule isMember
      exact ⟨compiledRule, compiledEq, fit compiledRule isCompiled⟩
    · obtain ⟨compiledRule, isCompiled, compiledEq⟩ := mapM_mem otherCompiled rule isMember
      exact ⟨compiledRule, compiledEq, otherFit compiledRule isCompiled⟩
  rw [Group.keyOf_eq_flatMap, Group.keyOf_eq_flatMap, mapM_flatMap compiled, mapM_flatMap otherCompiled]
  refine flatMap_lt_iff (items := group ++ other) (fun rule isMember otherRule isOther => ?_)
    (fun rule _ => rule.key_ne_nil) (fun rule isMember => ?_) (fun rule isMember => List.mem_append_left _ isMember)
    (fun rule isMember => List.mem_append_right _ isMember)
  · obtain ⟨compiledRule, compiledEq, fits⟩ := compiles rule isMember
    obtain ⟨compiledOther, otherCompiledEq, otherFits⟩ := compiles otherRule isOther
    simpa [compiledEq, otherCompiledEq] using agree_compile compiledEq otherCompiledEq fits otherFits
  · obtain ⟨compiledRule, compiledEq, -⟩ := compiles rule isMember
    simpa [compiledEq] using compiledRule.sizeFree_ne_nil

/-- Over one signature, a well-formed formula's normal form compiles to rules and groups in canonical order: every
group and every loop body strictly ascending by size-free bytes, and the groups by their rules' bytes. The encoder
writes `normalize`'s order and needs no sort. -/
theorem Policy.ordered_compile {signature : Signature} {formula : Formula} {policy : CompiledPolicy}
    (wellFormed : WellFormed signature formula)
    (compiled : CompiledPolicy.compile signature (normalize formula) = some policy) : policy.ordered = true := by
  obtain ⟨-, -, compiledFits⟩ := wellFormed
  rw [compiled] at compiledFits
  simp only [Option.map_some, Option.some.injEq, CompiledPolicy.fits, Bool.and_eq_true, decide_eq_true_eq,
    List.all_eq_true] at compiledFits
  obtain ⟨-, groupsFit⟩ := compiledFits
  have rulesFit : ∀ rules ∈ policy.groups, ∀ rule ∈ rules, rule.fits = true := by
    intro rules isRules
    have := groupsFit rules isRules
    simp only [groupFits, Bool.and_eq_true, List.all_eq_true] at this
    exact this.2
  have normal := normal_normalize formula
  simp only [Formula.normal, Bool.and_eq_true, List.all_eq_true] at normal
  obtain ⟨groupsNormal, groupsSorted⟩ := normal
  simp only [CompiledPolicy.compile, Option.map_eq_some_iff] at compiled
  obtain ⟨groups, groupsCompiled, rfl⟩ := compiled
  simp only [CompiledPolicy.ordered, ascendingBytes, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true]
  refine ⟨?_, fun rules isRules => ?_⟩
  · simp only [strictlySorted, decide_eq_true_eq] at groupsSorted
    exact mapM_pairwise groupsCompiled (fun group other rules otherRules isRules isOther compiledGroup
      otherCompiledGroup less => (Group.keyOf_lt_iff compiledGroup otherCompiledGroup (rulesFit rules isRules)
        (rulesFit otherRules isOther)).mp less) groupsSorted
  obtain ⟨group, isGroup, compiledGroup⟩ := mapM_mem_results groupsCompiled rules isRules
  obtain ⟨rulesNormal, rulesSorted, -⟩ := Group.normal_iff_parts.mp (groupsNormal group isGroup)
  simp only [strictlySorted, decide_eq_true_eq] at rulesSorted
  refine ⟨mapM_pairwise compiledGroup (fun rule other compiledRule compiledOther isRule isOther compiledEq
    otherCompiledEq less => (agree_compile compiledEq otherCompiledEq (rulesFit rules isRules compiledRule isRule)
      (rulesFit rules isRules compiledOther isOther)).lt_iff.mp less) rulesSorted, fun compiledRule isRule => ?_⟩
  obtain ⟨rule, isFormulaRule, compiledEq⟩ := mapM_mem_results compiledGroup compiledRule isRule
  rcases Rule.compile_shape compiledEq with ⟨test, -, rfl⟩ |
    ⟨quantifier, arrayPath, body, hint, compiledBody, rfl, -, bodyCompiled, rfl⟩
  · rfl
  · have bodyFits := rulesFit rules isRules _ isRule
    simp only [CompiledRule.fits, Bool.and_eq_true, List.all_eq_true] at bodyFits
    obtain ⟨-, bodySorted, -⟩ := Group.normal_iff_parts.mp (rulesNormal _ isFormulaRule)
    simp only [strictlySorted, decide_eq_true_eq] at bodySorted
    simp only [CompiledRule.ordered, ascendingBytes, decide_eq_true_eq]
    exact mapM_pairwise bodyCompiled (fun test other compiledTest compiledOther isTest isOther testCompiled
      otherTestCompiled less => (agree_compileTest testCompiled otherTestCompiled (bodyFits.2.2 compiledTest isTest)
        (bodyFits.2.2 compiledOther isOther)).lt_iff.mp less) bodySorted

end Callcium
