import Callcium.Wire.Encode
import Callcium.Theorems.Abi
import Callcium.Theorems.Descriptor

/-!
# Wire

The storage reader reads back what the encoder writes: `Policy.parse_encode` returns a well-formed formula's compiled
normal form, hints and operand words included. Theorem 6: the encoder's blobs pass storage validation. Theorem 7: they
decode to the normal form, and one normal form gives one blob. Theorem 30: one blob comes from one normal form.
-/

namespace Callcium

open Reader

/-! ## Readers -/

theorem Reader.bind_of {Item Other : Type} {reader : Reader Item} {next : Item → Reader Other} {bytes rest : Bytes}
    {item : Item} (reads : reader bytes = some (item, rest)) : (reader >>= next) bytes = next item rest := by
  simp [bind, StateT.bind, reads]

theorem Reader.map_of {Item Other : Type} {reader : Reader Item} {function : Item → Other} {bytes rest : Bytes}
    {item : Item} (reads : reader bytes = some (item, rest)) :
    (function <$> reader) bytes = some (function item, rest) := by
  simp [Functor.map, StateT.map, reads]

theorem Reader.require_true (bytes : Bytes) : require true bytes = some ((), bytes) := rfl

theorem Reader.some?_some {Item : Type} (item : Item) (bytes : Bytes) : some? (some item) bytes = some (item, bytes) :=
  rfl

theorem Reader.byte_cons (first : UInt8) (rest : Bytes) : byte (first :: rest) = some (first, rest) := rfl

theorem Reader.take_append (bytes rest : Bytes) : take bytes.length (bytes ++ rest) = some (bytes, rest) := by
  simp [take]

theorem Reader.field_beBytes {size value : Nat} (fits : value < 256 ^ size) (rest : Bytes) :
    field size (beBytes size value ++ rest) = some (value, rest) := by
  simp [field, take, beBytes_length, Functor.map, StateT.map, beNat_beBytes, Nat.mod_eq_of_lt fits]

theorem Reader.many_of {Item : Type} {reader : Reader Item} {write : Item → Bytes} {items : List Item}
    (reads : ∀ item ∈ items, ∀ rest, reader (write item ++ rest) = some (item, rest)) (rest : Bytes) :
    many reader items.length (items.flatMap write ++ rest) = some (items, rest) := by
  induction items with
  | nil => rfl
  | cons item items itemsRead =>
    simp only [List.length_cons, many, List.flatMap_cons, List.append_assoc]
    rw [bind_of (reads item (by simp) _), bind_of (itemsRead (fun other isMember => reads other (by simp [isMember])))]
    rfl

theorem Reader.framed_of {Item : Type} {reader : Reader Item} {bytes : Bytes} {item : Item}
    (reads : reader bytes = some (item, [])) (rest : Bytes) :
    framed bytes.length reader (bytes ++ rest) = some (item, rest) := by
  simp only [framed]
  rw [bind_of (take_append bytes rest), reads]
  rfl

theorem readFramed_frameRule {Item : Type} {reader : Reader Item} {content : Bytes} {item : Item}
    (reads : reader content = some (item, [])) (fits : (frameRule content).length < 2 ^ 16) (rest : Bytes) :
    readFramed reader (frameRule content ++ rest) = some (item, rest) := by
  simp only [frameRule, List.length_append, beBytes_length] at fits
  simp only [readFramed, frameRule, List.append_assoc]
  rw [bind_of (field_beBytes (by simp only [Policy.RULE_SIZE_SIZE] at fits ⊢; omega) _)]
  simp only [Policy.RULE_SIZE_SIZE, Nat.add_sub_cancel]
  exact framed_of reads rest

/-! ## Operand widths -/

theorem WordType.narrow_length (wordType : WordType) (word : Word) : (wordType.narrow word).length = wordType.width :=
  beBytes_length _ _

theorem WordType.flatMap_narrow_length (wordType : WordType) (values : List Word) :
    (values.flatMap wordType.narrow).length = values.length * wordType.width := by
  induction values with
  | nil => simp
  | cons value values shorter =>
    rw [List.flatMap_cons, List.length_append, shorter, WordType.narrow_length, List.length_cons, Nat.succ_mul,
      Nat.add_comm]

theorem WordType.width_pos (wordType : WordType) : 0 < wordType.width := by
  cases wordType <;> simp [WordType.width]

/-- A right-aligned word below `2 ^ (8 * width)` loads back from its `width` bytes. -/
theorem load_narrow_right {width : Nat} {word : Word} (below : word.toNat < 2 ^ (8 * width)) :
    BitVec.ofNat 256 (beNat (beBytes width word.toNat) * 1) = word := by
  apply BitVec.eq_of_toNat_eq
  have : (256 : Nat) ^ width = 2 ^ (8 * width) := by rw [Nat.pow_mul]
  simp [beNat_beBytes, this, Nat.mod_eq_of_lt below]

/-- A left-aligned word whose low `shift` bits are zero loads back from its high bytes. -/
theorem load_narrow_left {width : Nat} {word : Word} (fills : 8 * width + (256 - 8 * width) = 256)
    (lowZero : word.toNat % 2 ^ (256 - 8 * width) = 0) :
    BitVec.ofNat 256 (beNat (beBytes width (word.toNat / 2 ^ (256 - 8 * width))) * 2 ^ (256 - 8 * width)) = word := by
  apply BitVec.eq_of_toNat_eq
  have : (256 : Nat) ^ width = 2 ^ (8 * width) := by rw [Nat.pow_mul]
  have high : word.toNat / 2 ^ (256 - 8 * width) < 2 ^ (8 * width) := by
    rw [Nat.div_lt_iff_lt_mul (Nat.two_pow_pos _), ← Nat.pow_add, fills]
    exact word.isLt
  simp only [beNat_beBytes, this, Nat.mod_eq_of_lt high, Nat.div_mul_cancel (Nat.dvd_of_mod_eq_zero lowZero),
    BitVec.toNat_ofNat, Nat.mod_eq_of_lt word.isLt]

theorem lowZero_of_shiftLeft {word : Word} {bits : Nat} (le : bits ≤ 256) (zero : word <<< bits = 0) :
    word.toNat % 2 ^ (256 - bits) = 0 := by
  have toNat := congrArg BitVec.toNat zero
  rw [BitVec.toNat_shiftLeft, Nat.shiftLeft_eq] at toNat
  have split : (2 : Nat) ^ 256 = 2 ^ (256 - bits) * 2 ^ bits := by rw [← Nat.pow_add]; congr 1; omega
  rw [split, Nat.mul_mod_mul_right] at toNat
  exact (Nat.mul_eq_zero.mp (by simpa using toNat)).resolve_right (Nat.pos_iff_ne_zero.mp (Nat.two_pow_pos _))

theorem below_of_shiftRight {word : Word} {bits : Nat} (zero : word >>> bits = 0) : word.toNat < 2 ^ bits := by
  have toNat := congrArg BitVec.toNat zero
  rw [BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow] at toNat
  exact (Nat.div_eq_zero_iff_lt (Nat.two_pow_pos _)).mp (by simpa using toNat)

/-- A canonical word loads back from its operand bytes. -/
theorem WordType.load_narrow {wordType : WordType} {word : Word} (canonical : wordType.isCanonical word = true) :
    wordType.load (wordType.narrow word) = word := by
  cases wordType with
  | uint width =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical
    have := below_of_shiftRight canonical
    simp only [WordType.load, WordType.narrow, WordType.shift, WordType.leftAligned, WordType.width, ByteWidth.bits]
      at this ⊢
    simpa using load_narrow_right (width := width.index.val + 1) this
  | int width =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical
    simp only [WordType.load, WordType.narrow, WordType.shift, WordType.leftAligned, WordType.width]
    conv => rhs; rw [← canonical]
    simp only [Word.signExtendFrom]
    congr 1
    apply BitVec.eq_of_toNat_eq
    have : (256 : Nat) ^ (width.index.val + 1) = 2 ^ width.bits := by
      rw [ByteWidth.bits, Nat.pow_mul]
    have widthLe : width.bits ≤ 256 := by have := width.index.isLt; simp only [ByteWidth.bits]; omega
    simp [beNat_beBytes, this, BitVec.toNat_setWidth, Nat.mod_mod_of_dvd _ (Nat.pow_dvd_pow 2 widthLe)]
  | address =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical
    simpa [WordType.load, WordType.narrow, WordType.shift, WordType.leftAligned, WordType.width] using
      load_narrow_right (width := 20) (below_of_shiftRight canonical)
  | bool =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical
    simpa [WordType.load, WordType.narrow, WordType.shift, WordType.leftAligned, WordType.width] using
      load_narrow_right (width := 1) (Nat.lt_of_lt_of_le (below_of_shiftRight canonical) (by decide))
  | function =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical
    simpa [WordType.load, WordType.narrow, WordType.shift, WordType.leftAligned, WordType.width] using
      load_narrow_left (width := 24) (by decide) (lowZero_of_shiftLeft (by decide) canonical)
  | fixedBytes width =>
    simp only [WordType.isCanonical, beq_iff_eq] at canonical
    have widthLe : width.bits ≤ 256 := by have := width.index.isLt; simp only [ByteWidth.bits]; omega
    have lowZero := lowZero_of_shiftLeft widthLe canonical
    simp only [ByteWidth.bits] at lowZero widthLe
    simp only [WordType.load, WordType.narrow, WordType.shift, WordType.leftAligned, WordType.width, ite_true]
    exact load_narrow_left (by omega) lowZero

/-! ## Hints -/

theorem ArrayMeta.word_lt {array : ArrayMeta} (fits : array.strideWords < META_STRIDE_LIMIT) : array.word < 2 ^ 16 := by
  rcases array with ⟨dynamicArray, elementDynamic, strideWords⟩
  simp only [META_STRIDE_LIMIT] at fits
  cases dynamicArray <;> cases elementDynamic <;>
    simp [ArrayMeta.word, META_ELEMENT_DYNAMIC, META_DYNAMIC_ARRAY] <;> omega

theorem ArrayMeta.ofWord?_word {array : ArrayMeta} (fits : array.strideWords < META_STRIDE_LIMIT) :
    ArrayMeta.ofWord? array.word = some array := by
  rcases array with ⟨dynamicArray, elementDynamic, strideWords⟩
  simp only [META_STRIDE_LIMIT] at fits
  cases dynamicArray <;> cases elementDynamic <;>
    simp [ArrayMeta.word, ArrayMeta.ofWord?, ArrayMeta.ofWordMasked, META_ELEMENT_DYNAMIC, META_DYNAMIC_ARRAY,
      META_STRIDE_LIMIT] <;> omega

theorem Hop.read_write {hop : Hop} (fits : hop.fits = true) (rest : Bytes) :
    Hop.read (hop.write ++ rest) = some (hop, rest) := by
  cases hop with
  | plain delta =>
    simp only [Hop.fits, decide_eq_true_eq] at fits
    simp only [Hop.read, Hop.write, List.append_assoc]
    rw [bind_of (field_beBytes (by simpa using fits) _), bind_of (field_beBytes (by decide) _),
      bind_of (field_beBytes (by decide) _)]
    rfl
  | element index array =>
    simp only [Hop.fits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨indexFits, strideFits⟩ := fits
    simp only [PATH_MARKER_BASE] at indexFits
    simp only [Hop.read, Hop.write, List.append_assoc]
    rw [bind_of (field_beBytes (by decide) _), bind_of (field_beBytes (by simp; omega) _),
      bind_of (field_beBytes (by simpa using ArrayMeta.word_lt strideFits) _)]
    simp [HINT_NO_INDEX, PATH_MARKER_BASE, show index ≠ 65535 by omega, show index < 65280 from indexFits,
      ArrayMeta.ofWord?_word strideFits]
    rfl

theorem readHops_writeHops {hops : List Hop} (fit : hopsFit hops = true) (rest : Bytes) :
    readHops (writeHops hops ++ rest) = some (hops, rest) := by
  simp only [hopsFit, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at fit
  obtain ⟨countFits, hopsFit⟩ := fit
  simp only [MAX_HOP_COUNT] at countFits
  have count : (UInt8.ofNat hops.length).toNat = hops.length := by
    simp only [UInt8.toNat_ofNat']; omega
  simp only [readHops, writeHops, List.cons_append]
  rw [bind_of (byte_cons _ _), count]
  simp only [MAX_HOP_COUNT, show hops.length ≤ 2 ^ 6 - 1 by omega, decide_true]
  rw [bind_of (require_true _)]
  exact many_of (fun hop isMember => Hop.read_write (hopsFit hop isMember)) rest

theorem TestHint.read_write {hint : TestHint} (fits : hint.fits = true)
    (described : hint.targetMeta.isSome = (hint.typeCode == TypeCode.DYNAMIC_ARRAY)) (rest : Bytes) :
    TestHint.read (hint.write ++ rest) = some (hint, rest) := by
  rcases hint with ⟨hops, targetDelta, targetMeta, typeCode⟩
  simp only [TestHint.fits, Bool.and_eq_true, decide_eq_true_eq] at fits
  obtain ⟨⟨hopsFit, deltaFits⟩, metaFits⟩ := fits
  simp only [TestHint.read, TestHint.write, List.append_assoc]
  rw [bind_of (readHops_writeHops hopsFit _), bind_of (field_beBytes (by simpa using deltaFits) _)]
  cases targetMeta with
  | none =>
    simp only [Option.isSome_none, Option.map_none, Option.getD_none] at described ⊢
    rw [bind_of (field_beBytes (by decide) _), List.singleton_append, bind_of (byte_cons _ _)]
    simp only [show typeCode ≠ TypeCode.DYNAMIC_ARRAY by simpa using described.symm]
    rfl
  | some array =>
    simp only [Option.isSome_some, Option.map_some, Option.getD_some, Option.all_some, decide_eq_true_eq]
      at described metaFits ⊢
    rw [bind_of (field_beBytes (by simpa using ArrayMeta.word_lt metaFits) _), List.singleton_append,
      bind_of (byte_cons _ _)]
    simp only [show typeCode = TypeCode.DYNAMIC_ARRAY by simpa using described.symm, ↓reduceIte,
      ArrayMeta.ofWord?_word metaFits]
    rfl

theorem FrameHint.read_write {hint : FrameHint} (fits : hint.fits = true) (rest : Bytes) :
    FrameHint.read (hint.write ++ rest) = some (hint, rest) := by
  rcases hint with ⟨hops, arrayDelta, count, array⟩
  simp only [FrameHint.fits, Bool.and_eq_true, decide_eq_true_eq] at fits
  obtain ⟨⟨⟨hopsFit, deltaFits⟩, countFits⟩, strideFits⟩ := fits
  simp only [FrameHint.read, FrameHint.write, List.append_assoc]
  rw [bind_of (readHops_writeHops hopsFit _), bind_of (field_beBytes (by simpa using deltaFits) _),
    bind_of (field_beBytes (by simpa using countFits) _),
    bind_of (field_beBytes (by simpa using ArrayMeta.word_lt strideFits) _)]
  simp only [ArrayMeta.ofWord?_word strideFits]
  rfl

/-! ## Paths -/

theorem readPath_writePath {path : Path} (fits : Path.fits path = true) (indices : Path.indicesOnly path = true)
    (rest : Bytes) : readPath (writePath path ++ rest) = some (path, rest) := by
  simp only [Path.fits, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at fits
  obtain ⟨depthFits, stepsFit⟩ := fits
  have depth : (UInt8.ofNat path.length).toNat = path.length := by simp only [UInt8.toNat_ofNat']; omega
  simp only [readPath, writePath, List.cons_append]
  rw [bind_of (byte_cons _ _), depth,
    bind_of (many_of (fun step isMember rest => field_beBytes (by simpa using stepsFit step isMember) rest) rest),
    indices]
  rfl

/-! ## Operators -/

theorem Comparison.code_lt (comparison : Comparison) : comparison.code.toNat < 2 ^ SOURCE_SHIFT := by
  cases comparison <;> decide

theorem Comparison.ofCode?_code (comparison : Comparison) :
    Comparison.ofCode? comparison.code.toNat = some comparison := by
  cases comparison <;> decide

theorem Operator.opCode_fields (operator : Operator) :
    operator.opCode.toNat / NOT_FLAG = operator.negated.toNat ∧
      operator.opCode.toNat % NOT_FLAG / 2 ^ SOURCE_SHIFT = operator.operand.source ∧
      operator.opCode.toNat % 2 ^ SOURCE_SHIFT = operator.comparison.code.toNat := by
  have codeLt := operator.comparison.code_lt
  have sourceLe : operator.operand.source ≤ 1 := by cases operator.operand <;> simp [Operand.source]
  have negatedLe : operator.negated.toNat ≤ 1 := Bool.toNat_le _
  simp only [Operator.opCode, NOT_FLAG, SOURCE_SHIFT, UInt8.toNat_ofNat'] at codeLt ⊢
  omega

theorem Operator.counts_of_admissible {negated : Bool} {comparison : Comparison} {values : List Word}
    (admissible : Operator.admissible ⟨negated, comparison, .constant values⟩ = true) :
    (comparison.arity.map (· == values.length)).getD (decide (0 < values.length)) = true ∧
      (comparison != .in_ || (values.zip values.tail).all fun (lower, upper) => lower.ult upper) = true := by
  cases comparison <;> rcases values with _ | ⟨first, _ | ⟨second, _ | ⟨third, rest⟩⟩⟩ <;>
    simp_all [Operator.admissible, Comparison.arity] <;> exact Or.inl rfl

theorem Operator.context_of_admissible {negated : Bool} {comparison : Comparison} {property : PropertyId}
    (admissible : Operator.admissible ⟨negated, comparison, .context property⟩ = true) :
    comparison.swap?.isSome = true ∧ property ≤ CTX_MAX := by
  cases comparison <;> simp_all [Operator.admissible, Comparison.swap?]

/-- An admissible operator that compares and fits its target reads back. -/
theorem Operator.read_write {operator : Operator} {code : UInt8} (admissible : operator.admissible = true)
    (compares : operator.compares code = true) (fits : operator.fits code = true) (rest : Bytes) :
    Operator.read code (operator.write code ++ rest) = some (operator, rest) := by
  obtain ⟨negatedField, sourceField, comparisonField⟩ := operator.opCode_fields
  rcases operator with ⟨negated, comparison, operand⟩
  simp only at negatedField sourceField comparisonField
  have negatedRead : decide (negated.toNat = 1) = negated := by cases negated <;> rfl
  obtain ⟨wordType, typed⟩ : ∃ wordType, operandType comparison code = some wordType := by
    cases typed : operandType comparison code <;> simp_all [Operator.compares]
  simp only [Operator.fits, Bool.and_eq_true, decide_eq_true_eq] at fits
  cases operand with
  | constant values =>
    obtain ⟨-, dataFits⟩ := fits
    obtain ⟨counted, ascending⟩ := Operator.counts_of_admissible admissible
    have canonical : ∀ value ∈ values, wordType.isCanonical value = true := by
      simpa [Operator.compares, typed] using compares
    have data : Operator.data ⟨negated, comparison, .constant values⟩ code = values.flatMap wordType.narrow := by
      simp [Operator.data, typed]
    have dataLength := wordType.flatMap_narrow_length values
    rw [data, dataLength] at dataFits
    simp only [Operator.read, Operator.write, data, dataLength, List.cons_append, List.append_assoc]
    rw [bind_of (byte_cons _ _)]
    simp only [negatedField, sourceField, comparisonField, negatedRead, Comparison.ofCode?_code]
    rw [bind_of (some?_some _ _), typed, bind_of (some?_some _ _), bind_of (field_beBytes (by simpa using dataFits) _)]
    have count : values.length * wordType.width / wordType.width = values.length :=
      Nat.mul_div_cancel _ wordType.width_pos
    simp only [Operand.source, SOURCE_CONSTANT, ↓reduceIte, count, counted, Bool.and_true, decide_true]
    rw [bind_of (require_true _)]
    have chunks : values.flatMap wordType.narrow = (values.map wordType.narrow).flatMap id := by
      simp [List.flatMap_map]
    rw [chunks, ← List.length_map (f := wordType.narrow),
      bind_of (many_of (write := id) (fun chunk isMember rest => by
        obtain ⟨value, -, rfl⟩ := List.mem_map.mp isMember
        simpa [WordType.narrow_length] using take_append (wordType.narrow value) rest) rest)]
    have loads : (values.map wordType.narrow).map wordType.load = values := by
      rw [List.map_map]
      exact (List.map_congr_left fun value isMember => WordType.load_narrow (canonical value isMember)).trans
        (List.map_id' values)
    simp only [loads, ascending]
    rw [bind_of (require_true _)]
    rfl
  | context property =>
    obtain ⟨propertyFits, -⟩ := fits
    obtain ⟨swaps, defined⟩ := Operator.context_of_admissible admissible
    simp only [Operator.read, Operator.write, Operator.data, List.cons_append, List.append_assoc, beBytes_length]
    rw [bind_of (byte_cons _ _)]
    simp only [negatedField, sourceField, comparisonField, negatedRead, Comparison.ofCode?_code]
    rw [bind_of (some?_some _ _), typed, bind_of (some?_some _ _), bind_of (field_beBytes (by decide) _)]
    simp only [Operand.source, SOURCE_CONSTANT, SOURCE_CONTEXT, swaps, Nat.one_ne_zero, ↓reduceIte, decide_true,
      Bool.and_self]
    rw [bind_of (require_true _), bind_of (field_beBytes (by simpa using propertyFits) _)]
    simp only [defined, decide_true]
    rw [bind_of (require_true _)]
    rfl

/-! ## Type codes -/

/-- A type's code is the first byte of its descriptor node. -/
theorem AbiType.encodeNode_head (abiType : AbiType) : abiType.encodeNode.head? = some abiType.code := by
  cases abiType <;> simp [AbiType.encodeNode, AbiType.compositeHeader, AbiType.code]

/-! ## Compiled lists -/

theorem mapM_cons_eq_some {Item Result : Type} {function : Item → Option Result} {item : Item} {items : List Item}
    {results : List Result} :
    (item :: items).mapM function = some results ↔
      ∃ result rest, function item = some result ∧ items.mapM function = some rest ∧ results = result :: rest := by
  simp only [List.mapM_cons, bind, pure]
  cases function item <;> cases items.mapM function <;> simp [eq_comm]

theorem mapM_forall {Item Result : Type} {function : Item → Option Result} {property : Result → Prop} :
    ∀ {items : List Item} {results : List Result}, items.mapM function = some results →
      (∀ item ∈ items, ∀ result, function item = some result → property result) → ∀ result ∈ results, property result
  | [], results, mapped, _ => by simp_all
  | item :: items, results, mapped, each => by
    obtain ⟨first, rest, mapsFirst, mapsRest, rfl⟩ := mapM_cons_eq_some.mp mapped
    intro result isMember
    rcases List.mem_cons.mp isMember with rfl | isMember
    · exact each item (by simp) _ mapsFirst
    · exact mapM_forall mapsRest (fun other isOther => each other (by simp [isOther])) result isMember

theorem mapM_length {Item Result : Type} {function : Item → Option Result} :
    ∀ {items : List Item} {results : List Result}, items.mapM function = some results → results.length = items.length
  | [], results, mapped => by simp_all
  | item :: items, results, mapped => by
    obtain ⟨first, rest, -, mapsRest, rfl⟩ := mapM_cons_eq_some.mp mapped
    simp [mapM_length mapsRest]

theorem mapM_map_inverse {Item Result : Type} {function : Item → Option Result} {inverse : Result → Item}
    (inverts : ∀ item result, function item = some result → inverse result = item) :
    ∀ {items : List Item} {results : List Result}, items.mapM function = some results → results.map inverse = items
  | [], results, mapped => by simp_all
  | item :: items, results, mapped => by
    obtain ⟨first, rest, mapsFirst, mapsRest, rfl⟩ := mapM_cons_eq_some.mp mapped
    simp [inverts _ _ mapsFirst, mapM_map_inverse inverts mapsRest]

/-! ## Tests and rules -/

/-- A test's hint carries a target meta word exactly when its type code is the dynamic array code. -/
theorem Hint.wire_described (hint : Hint) :
    hint.wire.targetMeta.isSome = (hint.wire.typeCode == TypeCode.DYNAMIC_ARRAY) := by
  rcases hint with ⟨hops, targetDelta, target⟩
  cases target <;> simp [Hint.wire, AbiType.code, WordType.code_ne_dynamicArray] <;> decide

theorem CompiledTest.scope_ne_loop (test : CompiledTest) : test.scope ≠ SCOPE_LOOP := by
  cases test <;> simp [CompiledTest.scope] <;> decide

theorem Rule.readScoped_compileTest {start : AbiType} {rule : Rule} {test : CompiledTest} {root : Bool} {depth : Nat}
    (compiled : rule.compileTest start = some test) (admissible : rule.admissibleTest root depth = true)
    (fits : test.fits = true) (rest : Bytes) :
    CompiledTest.readScoped root depth test.scope (test.payload ++ rest) = some (test, rest) := by
  cases rule with
  | contextTest property operator =>
    simp only [Rule.compileTest] at compiled
    split at compiled
    case isFalse => contradiction
    rename_i compares
    cases compiled
    simp only [Rule.admissibleTest, Bool.and_eq_true, decide_eq_true_eq] at admissible
    obtain ⟨defined, operatorAdmissible⟩ := admissible
    simp only [CompiledTest.fits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨-, propertyFits, operatorFits⟩ := fits
    simp only [CompiledTest.readScoped, CompiledTest.scope, CompiledTest.payload, ↓reduceIte, List.cons_append,
      List.append_assoc]
    rw [bind_of (byte_cons _ _)]
    simp only [decide_true]
    rw [bind_of (require_true _), bind_of (field_beBytes (by simpa using propertyFits) _)]
    simp only [defined, decide_true]
    rw [bind_of (require_true _), bind_of (Operator.read_write operatorAdmissible compares operatorFits _)]
    rfl
  | test path operator =>
    simp only [Rule.compileTest, Option.bind_eq_some_iff] at compiled
    obtain ⟨hint, compiledHint, compiled⟩ := compiled
    split at compiled
    case isFalse => contradiction
    rename_i compares
    cases compiled
    simp only [Rule.admissibleTest, Bool.and_eq_true, decide_eq_true_eq] at admissible
    obtain ⟨⟨⟨nonempty, indices⟩, deep⟩, operatorAdmissible⟩ := admissible
    simp only [CompiledTest.fits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨-, ⟨pathFits, hintFits⟩, operatorFits⟩ := fits
    have typeCode : hint.wire.typeCode = hint.target.code := rfl
    simp only [CompiledTest.readScoped, CompiledTest.scope, CompiledTest.payload, SCOPE_CONTEXT, SCOPE_CALLDATA,
      List.append_assoc]
    simp only [show (1 : UInt8) ≠ 0 by decide, ↓reduceIte]
    rw [bind_of (readPath_writePath pathFits indices _)]
    simp only [nonempty, deep, decide_true, Bool.and_self]
    rw [bind_of (require_true _), bind_of (TestHint.read_write hintFits hint.wire_described _), typeCode,
      bind_of (Operator.read_write operatorAdmissible compares (typeCode ▸ operatorFits) _)]
    rfl
  | loop => simp [Rule.compileTest] at compiled

theorem Rule.read_compileTest {start : AbiType} {rule : Rule} {test : CompiledTest} {depth : Nat}
    (compiled : rule.compileTest start = some test) (admissible : rule.admissibleTest false depth = true)
    (fits : test.fits = true) (rest : Bytes) : CompiledTest.read depth (test.write ++ rest) = some (test, rest) := by
  have sizeFits : test.write.length < 2 ^ 16 := by
    cases test <;> simp_all [CompiledTest.fits]
  refine readFramed_frameRule ?_ sizeFits rest
  rw [CompiledTest.sizeFree, bind_of (byte_cons _ _), ← List.append_nil test.payload]
  exact Rule.readScoped_compileTest compiled admissible fits []

theorem Quantifier.ofCode?_code (quantifier : Quantifier) : Quantifier.ofCode? quantifier.code = some quantifier := by
  cases quantifier <;> decide

theorem Rule.read_compile {start : AbiType} {rule : Rule} {compiled : CompiledRule}
    (compiledEq : rule.compile start = some compiled) (admissible : rule.admissible = true)
    (fits : compiled.fits = true) (rest : Bytes) :
    CompiledRule.read (compiled.write ++ rest) = some (compiled, rest) := by
  have sizeFits : compiled.write.length < 2 ^ 16 := by
    simp only [CompiledRule.fits, Bool.and_eq_true, decide_eq_true_eq] at fits
    exact fits.1
  rw [CompiledRule.read, CompiledRule.write]
  refine readFramed_frameRule ?_ sizeFits rest
  cases rule
  case loop quantifier arrayPath body =>
    simp only [Rule.compile, Option.bind_eq_some_iff, Option.map_eq_some_iff] at compiledEq
    obtain ⟨hint, -, compiledBody, bodyCompiled, rfl⟩ := compiledEq
    simp only [Rule.admissible, Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq, List.isEmpty_eq_false_iff,
      List.all_eq_true] at admissible
    obtain ⟨⟨⟨⟨⟨nonempty, indices⟩, shallow⟩, bodyNonempty⟩, bodyAdmissible⟩, -⟩ := admissible
    simp only [CompiledRule.fits, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at fits
    obtain ⟨-, ⟨⟨pathFits, hintFits⟩, countFits⟩, bodyFits⟩ := fits
    have length : compiledBody.length = body.length := mapM_length bodyCompiled
    have arrayNonempty : arrayPath.isEmpty = false := by simpa using nonempty
    simp only [CompiledRule.content, List.cons_append, List.append_assoc]
    rw [bind_of (byte_cons _ _)]
    simp only [↓reduceIte]
    rw [bind_of (byte_cons _ _), Quantifier.ofCode?_code, bind_of (some?_some _ _),
      bind_of (readPath_writePath pathFits indices _)]
    simp only [arrayNonempty, shallow, Bool.not_false, decide_true, Bool.and_self]
    rw [bind_of (require_true _), bind_of (FrameHint.read_write hintFits _),
      bind_of (field_beBytes (by simpa using countFits) _)]
    simp only [length, List.length_pos_iff.mpr bodyNonempty, decide_true]
    rw [bind_of (require_true _), ← length, ← List.append_nil (compiledBody.flatMap CompiledTest.write),
      bind_of (many_of (fun test isMember rest =>
      mapM_forall (property := fun test => test.fits = true → CompiledTest.read arrayPath.length (test.write ++ rest) =
          some (test, rest)) bodyCompiled
        (fun rule isMember test compiled fits =>
          Rule.read_compileTest compiled (bodyAdmissible rule isMember) fits rest)
        test isMember (bodyFits test isMember)) [])]
    rfl
  all_goals
    simp only [Rule.compile, Option.map_eq_some_iff] at compiledEq
    obtain ⟨test, compiledTest, rfl⟩ := compiledEq
    simp only [CompiledRule.fits, Bool.and_eq_true] at fits
    simp only [CompiledRule.content, CompiledTest.sizeFree]
    rw [bind_of (byte_cons _ _)]
    simp only [test.scope_ne_loop, ↓reduceIte]
    rw [← List.append_nil test.payload, map_of (Rule.readScoped_compileTest compiledTest admissible fits.2 [])]

/-! ## Groups and policies -/

theorem readGroup_writeGroup {start : AbiType} {group : Group} {rules : List CompiledRule}
    (compiled : group.mapM (Rule.compile start) = some rules) (admissible : ∀ rule ∈ group, rule.admissible = true)
    (nonempty : group ≠ []) (fits : groupFits rules = true) (rest : Bytes) :
    readGroup (writeGroup rules ++ rest) = some (rules, rest) := by
  simp only [groupFits, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at fits
  obtain ⟨⟨countFits, sizeFits⟩, rulesFit⟩ := fits
  have length : rules.length = group.length := mapM_length compiled
  simp only [readGroup, writeGroup, List.append_assoc]
  rw [bind_of (field_beBytes (by simpa using countFits) _), bind_of (field_beBytes (by simpa using sizeFits) _)]
  simp only [length, List.length_pos_iff.mpr nonempty, decide_true]
  rw [bind_of (require_true _), ← length]
  refine framed_of ?_ rest
  rw [← List.append_nil (rules.flatMap CompiledRule.write)]
  exact many_of (fun compiledRule isMember rest =>
    mapM_forall (property := fun compiledRule => compiledRule.fits = true →
        CompiledRule.read (compiledRule.write ++ rest) = some (compiledRule, rest)) compiled
      (fun rule isMember compiledRule compiledEq fits =>
        Rule.read_compile compiledEq (admissible rule isMember) fits rest)
      compiledRule isMember (rulesFit compiledRule isMember)) []

theorem Policy.header_version (selectorless : Bool) :
    (header selectorless).toNat >>> MAJOR_SHIFT = MAJOR ∧
      (header selectorless).toNat >>> MINOR_SHIFT &&& MINOR_MASK = MINOR := by
  cases selectorless <;> decide

theorem Policy.header_selectorless (selectorless : Bool) :
    decide ((header selectorless).toNat &&& FLAG_NO_SELECTOR = FLAG_NO_SELECTOR) = selectorless := by
  cases selectorless <;> decide

theorem Policy.selector_read (selector : Option UInt32) :
    (if (header selector.isNone).toNat &&& FLAG_NO_SELECTOR = FLAG_NO_SELECTOR then none
      else some (UInt32.ofNat ((selector.map UInt32.toNat).getD 0))) = selector := by
  cases selector with
  | none =>
    have flagged : (header true).toNat &&& FLAG_NO_SELECTOR = FLAG_NO_SELECTOR := by decide
    simp only [Option.isNone_none, flagged, ↓reduceIte]
  | some selector =>
    have unflagged : ¬(header false).toNat &&& FLAG_NO_SELECTOR = FLAG_NO_SELECTOR := by decide
    simp only [Option.isNone_some, unflagged, ↓reduceIte, Option.map_some, Option.getD_some, UInt32.ofNat_toNat]

/-- A policy compiled from an admissible formula over a signature a descriptor describes, fitting the wire's field
widths, reads back from its blob. -/
theorem CompiledPolicy.parse_write {signature : Signature} {formula : Formula} {policy : CompiledPolicy}
    (compiled : CompiledPolicy.compile signature formula = some policy) (admissible : formula.admissible = true)
    (limits : Descriptor.withinLimits signature.params = true) (fits : policy.fits = true) :
    Policy.parse policy.write = some policy := by
  simp only [CompiledPolicy.compile, Option.map_eq_some_iff] at compiled
  obtain ⟨groups, groupsCompiled, rfl⟩ := compiled
  simp only [Formula.admissible, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff,
    List.all_eq_true] at admissible
  obtain ⟨formulaNonempty, groupsAdmissible⟩ := admissible
  simp only [CompiledPolicy.fits, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at fits
  obtain ⟨⟨descFits, countFits⟩, groupsFit⟩ := fits
  have length : groups.length = formula.length := mapM_length groupsCompiled
  have count : (UInt8.ofNat groups.length).toNat = groups.length := by simp only [UInt8.toNat_ofNat']; omega
  have version := Policy.header_version signature.selector.isNone
  have selectorless := Policy.header_selectorless signature.selector.isNone
  have selectorFits : (signature.selector.map UInt32.toNat).getD 0 < 256 ^ Policy.SELECTOR_SIZE := by
    cases signature.selector with
    | none => decide
    | some selector => simpa [Policy.SELECTOR_SIZE] using UInt32.toNat_lt selector
  have slotZero : (!signature.selector.isNone || decide ((signature.selector.map UInt32.toNat).getD 0 = 0)) = true := by
    cases signature.selector <;> simp
  have selectorRead := Policy.selector_read signature.selector
  have reads : Policy.read (CompiledPolicy.write ⟨signature.selector, Descriptor.encode signature.params, groups⟩) =
      some (⟨signature.selector, Descriptor.encode signature.params, groups⟩, []) := by
    simp only [Policy.read, CompiledPolicy.write, List.cons_append, List.append_assoc]
    rw [bind_of (byte_cons _ _)]
    simp only [version, decide_true, Bool.and_self]
    rw [bind_of (require_true _), bind_of (field_beBytes selectorFits _)]
    simp only [selectorless, slotZero]
    rw [bind_of (require_true _), bind_of (field_beBytes (by simpa using descFits) _), bind_of (take_append _ _)]
    simp only [Descriptor.wellFormed_encode signature.params limits]
    rw [bind_of (require_true _), bind_of (byte_cons _ _), count]
    simp only [length, List.length_pos_iff.mpr formulaNonempty, decide_true]
    rw [bind_of (require_true _), ← length, ← List.append_nil (groups.flatMap writeGroup),
      bind_of (many_of (fun rules isMember rest =>
        mapM_forall (property := fun rules => groupFits rules = true →
            readGroup (writeGroup rules ++ rest) = some (rules, rest)) groupsCompiled
          (fun group isMember rules compiledGroup fits =>
            readGroup_writeGroup compiledGroup (groupsAdmissible group isMember).2
              (by simpa using (groupsAdmissible group isMember).1) fits rest)
          rules isMember (groupsFit rules isMember)) [])]
    simp only [selectorRead]
    rfl
  simp [Policy.parse, reads]

/-! ## Compiling keeps the formula -/

theorem Rule.compileTest_rule {start : AbiType} {rule : Rule} {test : CompiledTest}
    (compiled : rule.compileTest start = some test) : test.rule = rule := by
  cases rule with
  | contextTest property operator =>
    simp only [Rule.compileTest] at compiled
    split at compiled
    case isFalse => contradiction
    cases compiled
    rfl
  | test path operator =>
    simp only [Rule.compileTest, Option.bind_eq_some_iff] at compiled
    obtain ⟨hint, -, compiled⟩ := compiled
    split at compiled
    case isFalse => contradiction
    cases compiled
    rfl
  | loop => simp [Rule.compileTest] at compiled

theorem Rule.compile_rule {start : AbiType} {rule : Rule} {compiled : CompiledRule}
    (compiledEq : rule.compile start = some compiled) : compiled.rule = rule := by
  cases rule
  case loop quantifier arrayPath body =>
    simp only [Rule.compile, Option.bind_eq_some_iff, Option.map_eq_some_iff] at compiledEq
    obtain ⟨hint, -, compiledBody, bodyCompiled, rfl⟩ := compiledEq
    simp [CompiledRule.rule, mapM_map_inverse (fun _ _ => Rule.compileTest_rule) bodyCompiled]
  all_goals
    simp only [Rule.compile, Option.map_eq_some_iff] at compiledEq
    obtain ⟨test, compiledTest, rfl⟩ := compiledEq
    exact Rule.compileTest_rule compiledTest

theorem CompiledPolicy.compile_formula {signature : Signature} {formula : Formula} {policy : CompiledPolicy}
    (compiled : CompiledPolicy.compile signature formula = some policy) : policy.formula = formula := by
  simp only [CompiledPolicy.compile, Option.map_eq_some_iff] at compiled
  obtain ⟨groups, groupsCompiled, rfl⟩ := compiled
  exact mapM_map_inverse (fun _ _ => mapM_map_inverse fun _ _ => Rule.compile_rule) groupsCompiled

/-! ## Theorems 6, 7 and 30 -/

namespace Policy

theorem compiled_of_wellFormed {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula) :
    ∃ policy, CompiledPolicy.compile signature (normalize formula) = some policy ∧ policy.fits = true := by
  obtain ⟨-, -, compiledFits⟩ := wellFormed
  simpa [Option.map_eq_some_iff] using compiledFits

/-- The blob of a well-formed formula reads back as its compiled normal form, hints and operand words included. -/
theorem parse_encode {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula) :
    parse (encode signature formula) = CompiledPolicy.compile signature (normalize formula) := by
  obtain ⟨policy, compiled, fits⟩ := compiled_of_wellFormed wellFormed
  obtain ⟨admissible, limits, -⟩ := wellFormed
  simp only [encode, compiled, Option.map_some, Option.getD_some]
  exact CompiledPolicy.parse_write compiled admissible limits fits

/-- Theorem 6: the encoder emits only blobs that pass storage validation. -/
theorem validate_encode {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula) :
    validate (encode signature formula) = true := by
  obtain ⟨policy, compiled, -⟩ := compiled_of_wellFormed wellFormed
  simp [validate, parse_encode wellFormed, compiled]

/-- Theorem 7: a well-formed formula's blob decodes to its normal form. -/
theorem decode_encode {signature : Signature} {formula : Formula} (wellFormed : WellFormed signature formula) :
    decode (encode signature formula) = some (normalize formula) := by
  obtain ⟨policy, compiled, -⟩ := compiled_of_wellFormed wellFormed
  simp [decode, parse_encode wellFormed, compiled, CompiledPolicy.compile_formula compiled]

/-- Theorem 7: formulas with one normal form get one blob. -/
theorem encode_normalize (signature : Signature) {formula other : Formula}
    (same : normalize formula = normalize other) :
    encode signature formula = encode signature other := by
  simp only [encode, same]

/-- Theorem 30: one blob comes from one normal form. -/
theorem normalize_of_encode {signature : Signature} {formula other : Formula}
    (wellFormed : WellFormed signature formula) (otherWellFormed : WellFormed signature other)
    (same : encode signature formula = encode signature other) : normalize formula = normalize other := by
  have decodes := decode_encode wellFormed
  rw [same, decode_encode otherWellFormed] at decodes
  exact (Option.some.inj decodes).symm

end Policy

end Callcium
