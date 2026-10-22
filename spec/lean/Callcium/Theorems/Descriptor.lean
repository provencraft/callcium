import Callcium.Descriptor.Validate

/-!
# Descriptor

Theorem 9: decoding an encoded type list within limits returns it. Theorem 10: the valid descriptors are exactly the
encodings of type lists within limits. Theorem 12: the builder accepts exactly the type lists within limits. Theorem 13:
a node's `staticWords` is its type's head size in words. Theorem 14: on a valid descriptor, skipping a node by its
`nodeLength` and walking its children end at the same byte.
-/

namespace Callcium

open Descriptor

/-! ## Fields -/

/-- Metadata within its fields reads back. -/
theorem Descriptor.compositeMeta_reads {staticWords nodeLength : Nat} (staticWordsFit : staticWords ≤ MAX_STATIC_WORDS)
    (nodeLengthFits : nodeLength ≤ MAX_NODE_LENGTH) :
    ∃ high middle low, compositeMeta staticWords nodeLength = [high, middle, low] ∧
      metaFields high middle low = (staticWords, nodeLength) := by
  refine ⟨_, _, _, rfl, ?_⟩
  simp only [MAX_STATIC_WORDS, MAX_NODE_LENGTH, Nat.reducePow] at staticWordsFit nodeLengthFits
  simp only [metaFields, UInt8.toNat_ofNat', Nat.reducePow, Prod.mk.injEq]
  omega

theorem Descriptor.compositeMeta_of_metaFields {high middle low : UInt8} {staticWords nodeLength : Nat}
    (fields : metaFields high middle low = (staticWords, nodeLength)) :
    compositeMeta staticWords nodeLength = [high, middle, low] := by
  simp only [metaFields, Nat.reducePow, Prod.mk.injEq] at fields
  have := high.toNat_lt
  have := middle.toNat_lt
  have := low.toNat_lt
  simp only [compositeMeta, Nat.reducePow, List.cons.injEq, ← UInt8.toNat_inj, UInt8.toNat_ofNat', and_true]
  omega

/-- A 16-bit field within its width reads back. -/
theorem Descriptor.be16_reads {value : Nat} (fits : value < 2 ^ 16) :
    ∃ high low, be16 value = [high, low] ∧ readBe16 high low = value := by
  refine ⟨_, _, rfl, ?_⟩
  simp only [Nat.reducePow] at fits
  simp only [readBe16, UInt8.toNat_ofNat', Nat.reducePow]
  omega

theorem Descriptor.be16_of_readBe16 (high low : UInt8) : be16 (readBe16 high low) = [high, low] := by
  have := high.toNat_lt
  have := low.toNat_lt
  simp only [be16, readBe16, Nat.reducePow, List.cons.injEq, ← UInt8.toNat_inj, UInt8.toNat_ofNat', and_true]
  omega

/-! ## Type codes -/

theorem WordType.ofCode?_code (wordType : WordType) : WordType.ofCode? wordType.code = some wordType := by
  cases wordType with
  | uint width => obtain ⟨index⟩ := width; revert index; decide
  | int width => obtain ⟨index⟩ := width; revert index; decide
  | fixedBytes width => obtain ⟨index⟩ := width; revert index; decide
  | _ => decide

theorem WordType.code_of_ofCode? {code : UInt8} {wordType : WordType} (named : WordType.ofCode? code = some wordType) :
    wordType.code = code := by
  unfold WordType.ofCode? at named
  split at named
  · cases named
    simp only [WordType.code, ByteWidth.bits, ← UInt8.toNat_inj, UInt8.toNat_ofNat']
    omega
  · split at named
    · cases named
      simp only [WordType.code, ByteWidth.bits, ← UInt8.toNat_inj, UInt8.toNat_ofNat']
      omega
    · split at named
      · cases named; simp_all [WordType.code]
      · split at named
        · cases named; simp_all [WordType.code]
        · split at named
          · cases named; simp_all [WordType.code]
          · split at named
            · cases named
              simp only [WordType.code, ByteWidth.bits, ← UInt8.toNat_inj, UInt8.toNat_ofNat']
              omega
            · cases named

@[simp] theorem TypeCode.string_ne_bytes : TypeCode.STRING ≠ TypeCode.BYTES := by decide
@[simp] theorem TypeCode.tuple_ne_bytes : TypeCode.TUPLE ≠ TypeCode.BYTES := by decide
@[simp] theorem TypeCode.tuple_ne_string : TypeCode.TUPLE ≠ TypeCode.STRING := by decide
@[simp] theorem TypeCode.staticArray_ne_bytes : TypeCode.STATIC_ARRAY ≠ TypeCode.BYTES := by decide
@[simp] theorem TypeCode.staticArray_ne_string : TypeCode.STATIC_ARRAY ≠ TypeCode.STRING := by decide
@[simp] theorem TypeCode.staticArray_ne_tuple : TypeCode.STATIC_ARRAY ≠ TypeCode.TUPLE := by decide
@[simp] theorem TypeCode.dynamicArray_ne_bytes : TypeCode.DYNAMIC_ARRAY ≠ TypeCode.BYTES := by decide
@[simp] theorem TypeCode.dynamicArray_ne_string : TypeCode.DYNAMIC_ARRAY ≠ TypeCode.STRING := by decide
@[simp] theorem TypeCode.dynamicArray_ne_tuple : TypeCode.DYNAMIC_ARRAY ≠ TypeCode.TUPLE := by decide
@[simp] theorem TypeCode.dynamicArray_ne_staticArray : TypeCode.DYNAMIC_ARRAY ≠ TypeCode.STATIC_ARRAY := by decide

@[simp] theorem WordType.ofCode?_bytes : WordType.ofCode? TypeCode.BYTES = none := by decide
@[simp] theorem WordType.ofCode?_string : WordType.ofCode? TypeCode.STRING = none := by decide
@[simp] theorem WordType.ofCode?_staticArray : WordType.ofCode? TypeCode.STATIC_ARRAY = none := by decide
@[simp] theorem WordType.ofCode?_dynamicArray : WordType.ofCode? TypeCode.DYNAMIC_ARRAY = none := by decide
@[simp] theorem WordType.ofCode?_tuple : WordType.ofCode? TypeCode.TUPLE = none := by decide

@[simp] theorem WordType.code_ne_tuple (wordType : WordType) : wordType.code ≠ TypeCode.TUPLE := fun same => by
  simpa [same] using wordType.ofCode?_code
@[simp] theorem WordType.code_ne_staticArray (wordType : WordType) : wordType.code ≠ TypeCode.STATIC_ARRAY :=
  fun same => by simpa [same] using wordType.ofCode?_code
@[simp] theorem WordType.code_ne_dynamicArray (wordType : WordType) : wordType.code ≠ TypeCode.DYNAMIC_ARRAY :=
  fun same => by simpa [same] using wordType.ofCode?_code
@[simp] theorem TypeCode.bytes_ne_tuple : TypeCode.BYTES ≠ TypeCode.TUPLE := by decide
@[simp] theorem TypeCode.bytes_ne_staticArray : TypeCode.BYTES ≠ TypeCode.STATIC_ARRAY := by decide
@[simp] theorem TypeCode.bytes_ne_dynamicArray : TypeCode.BYTES ≠ TypeCode.DYNAMIC_ARRAY := by decide
@[simp] theorem TypeCode.string_ne_tuple : TypeCode.STRING ≠ TypeCode.TUPLE := by decide
@[simp] theorem TypeCode.string_ne_staticArray : TypeCode.STRING ≠ TypeCode.STATIC_ARRAY := by decide
@[simp] theorem TypeCode.string_ne_dynamicArray : TypeCode.STRING ≠ TypeCode.DYNAMIC_ARRAY := by decide

/-! ## Node length -/

theorem AbiType.encodeNode_length (abiType : AbiType) : abiType.encodeNode.length = abiType.nodeLength := by
  induction abiType with
  | word | bytes | string => rfl
  | staticArray element length elementLength =>
    simp only [AbiType.encodeNode, AbiType.compositeHeader, compositeMeta, be16, AbiType.nodeLength,
      List.length_append, List.length_cons, List.length_nil, elementLength, ARRAY_HEADER_SIZE, ARRAY_LENGTH_SIZE]
  | dynamicArray element elementLength =>
    simp only [AbiType.encodeNode, AbiType.compositeHeader, compositeMeta, AbiType.nodeLength, List.length_append,
      List.length_cons, List.length_nil, elementLength, ARRAY_HEADER_SIZE]
  | tuple fields fieldLengths =>
    simp only [AbiType.encodeNode, AbiType.compositeHeader, compositeMeta, be16, AbiType.nodeLength,
      List.length_append, List.length_cons, List.length_nil, encodeNodes_length fields fieldLengths,
      TUPLE_HEADER_SIZE]
where
  encodeNodes_length (fields : List AbiType) (lengths : ∀ field ∈ fields, field.encodeNode.length = field.nodeLength) :
      (AbiType.encodeNodes fields).length = AbiType.sumNodeLength fields := by
    induction fields with
    | nil => rfl
    | cons field fields fieldsLength =>
      simp only [AbiType.encodeNodes, AbiType.sumNodeLength, List.length_append, lengths field (by simp),
        fieldsLength fun other isMember => lengths other (by simp [isMember])]

theorem AbiType.encodeNodes_length (fields : List AbiType) :
    (AbiType.encodeNodes fields).length = AbiType.sumNodeLength fields :=
  AbiType.encodeNode_length.encodeNodes_length fields fun field _ => field.encodeNode_length

theorem AbiType.allFit_iff (types : List AbiType) : AbiType.allFit types = true ↔ ∀ abiType ∈ types, abiType.fits := by
  induction types <;> simp [AbiType.allFit, *]

theorem AbiType.allWithinDepth_iff (depth : Nat) (types : List AbiType) :
    AbiType.allWithinDepth depth types = true ↔ ∀ abiType ∈ types, abiType.withinDepth depth := by
  induction types <;> simp [AbiType.allWithinDepth, *]

/-- The limits, member by member. -/
theorem Descriptor.withinLimits_iff (types : List AbiType) :
    withinLimits types = true ↔
      types.length ≤ MAX_PARAMS ∧ AbiType.allFit types = true ∧ AbiType.allWithinDepth 1 types = true := by
  simp only [withinLimits, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true, AbiType.allFit_iff,
    AbiType.allWithinDepth_iff]
  constructor
  · intro ⟨countFits, each⟩
    exact ⟨countFits, fun abiType isMember => (each abiType isMember).1,
      fun abiType isMember => (each abiType isMember).2⟩
  · intro ⟨countFits, fit, deep⟩
    exact ⟨countFits, fun abiType isMember => ⟨fit abiType isMember, deep abiType isMember⟩⟩

/-! ## Decoding an encoding -/

theorem Descriptor.decodeNode_encodeNode (abiType : AbiType) (fits : abiType.fits = true) (rest : Bytes) :
    decodeNode (abiType.encodeNode ++ rest) = some (abiType, abiType.nodeLength) := by
  induction abiType generalizing rest with
  | word wordType =>
    rw [AbiType.encodeNode, decodeNode.eq_def]
    simp [WordType.ofCode?_code, AbiType.nodeLength]
  | bytes =>
    rw [AbiType.encodeNode, decodeNode.eq_def]
    simp [AbiType.nodeLength]
  | string =>
    rw [AbiType.encodeNode, decodeNode.eq_def]
    simp [AbiType.nodeLength]
  | staticArray element length elementDecodes =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨⟨⟨-, lengthFits⟩, nodeLengthFits, staticWordsFit⟩, elementFits⟩ := fits
    simp only [MAX_STATIC_ARRAY_LENGTH] at lengthFits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads staticWordsFit nodeLengthFits
    obtain ⟨lengthHigh, lengthLow, lengthBytes, lengthRead⟩ := be16_reads (by omega : length < 2 ^ 16)
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes, lengthBytes, decodeNode.eq_def]
    simp [elementDecodes elementFits, drop_encodeNode, checkMeta, metaRead, lengthRead]
    simp only [AbiType.nodeLength, and_self]
  | dynamicArray element elementDecodes =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨⟨nodeLengthFits, staticWordsFit⟩, elementFits⟩ := fits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads staticWordsFit nodeLengthFits
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes, decodeNode.eq_def]
    simp [elementDecodes elementFits, checkMeta, metaRead]
    simp only [AbiType.nodeLength, and_self]
  | tuple fields fieldsDecode =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨⟨⟨-, countFits⟩, nodeLengthFits, staticWordsFit⟩, fieldsFit⟩ := fits
    simp only [MAX_TUPLE_FIELDS, MAX_NODE_LENGTH, TUPLE_HEADER_SIZE] at countFits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads staticWordsFit nodeLengthFits
    obtain ⟨countHigh, countLow, countBytes, countRead⟩ := be16_reads (by omega : fields.length < 2 ^ 16)
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes, countBytes, decodeNode.eq_def]
    simp [countRead, decodeNodes_encodeNodes fields fieldsDecode fieldsFit, checkMeta, metaRead]
    simp only [AbiType.nodeLength, and_self]
where
  drop_encodeNode (abiType : AbiType) (tail : Bytes) : (abiType.encodeNode ++ tail).drop abiType.nodeLength = tail := by
    rw [← abiType.encodeNode_length, List.drop_left]
  decodeNodes_encodeNodes (fields : List AbiType)
      (decodes : ∀ field ∈ fields, field.fits = true → ∀ rest, decodeNode (field.encodeNode ++ rest) =
        some (field, field.nodeLength))
      (fit : AbiType.allFit fields = true) (rest : Bytes) :
      decodeNodes fields.length (AbiType.encodeNodes fields ++ rest) = some (fields, AbiType.sumNodeLength fields) := by
    induction fields with
    | nil => simp [decodeNodes, AbiType.encodeNodes, AbiType.sumNodeLength]
    | cons field fields fieldsDecode =>
      simp only [AbiType.allFit, Bool.and_eq_true] at fit
      rw [List.length_cons, decodeNodes, AbiType.encodeNodes, List.append_assoc, decodes field (by simp) fit.1]
      simp only [drop_encodeNode, fieldsDecode (fun other isMember => decodes other (by simp [isMember])) fit.2,
        AbiType.sumNodeLength]

theorem Descriptor.decodeNodes_encodeNodes (types : List AbiType) (fit : AbiType.allFit types = true) (rest : Bytes) :
    decodeNodes types.length (AbiType.encodeNodes types ++ rest) = some (types, AbiType.sumNodeLength types) :=
  decodeNode_encodeNode.decodeNodes_encodeNodes types (fun field _ fits rest => decodeNode_encodeNode field fits rest)
    fit rest

/-- Theorem 9: decoding the descriptor of a type list within limits returns the list. -/
theorem Descriptor.decode_encode (types : List AbiType) (limits : withinLimits types = true) :
    decode (encode types) = some types := by
  obtain ⟨countFits, fit, -⟩ := (withinLimits_iff types).mp limits
  simp only [MAX_PARAMS, Nat.reducePow] at countFits
  have decodes := decodeNodes_encodeNodes types fit []
  rw [List.append_nil] at decodes
  simp [encode, decode, VERSION, UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega : types.length < 256), decodes,
    AbiType.encodeNodes_length]

/-! ## Well-formed encodings -/

@[simp] theorem Descriptor.isElementary_code (wordType : WordType) : isElementary wordType.code := by
  simp [isElementary, WordType.ofCode?_code]
@[simp] theorem Descriptor.isElementary_bytes : isElementary TypeCode.BYTES := by decide
@[simp] theorem Descriptor.isElementary_string : isElementary TypeCode.STRING := by decide
@[simp] theorem Descriptor.isElementary_tuple : isElementary TypeCode.TUPLE = false := by decide
@[simp] theorem Descriptor.isElementary_staticArray : isElementary TypeCode.STATIC_ARRAY = false := by decide
@[simp] theorem Descriptor.isElementary_dynamicArray : isElementary TypeCode.DYNAMIC_ARRAY = false := by decide
@[simp] theorem Descriptor.isComposite_tuple : isComposite TypeCode.TUPLE := by decide
@[simp] theorem Descriptor.isComposite_staticArray : isComposite TypeCode.STATIC_ARRAY := by decide
@[simp] theorem Descriptor.isComposite_dynamicArray : isComposite TypeCode.DYNAMIC_ARRAY := by decide

theorem Descriptor.skipNode_encodeNode (abiType : AbiType) (fits : abiType.fits = true) (rest : Bytes) :
    skipNode (abiType.encodeNode ++ rest) = some abiType.nodeLength := by
  have spans : abiType.nodeLength ≤ (abiType.encodeNode ++ rest).length := by
    simp [← abiType.encodeNode_length]
  cases abiType with
  | word wordType => simp [AbiType.encodeNode, skipNode, AbiType.nodeLength]
  | bytes => simp [AbiType.encodeNode, skipNode, AbiType.nodeLength]
  | string => simp [AbiType.encodeNode, skipNode, AbiType.nodeLength]
  | staticArray element length =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads fits.1.2.2 fits.1.2.1
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes] at spans ⊢
    simp [skipNode, metaRead, headerSize, ARRAY_HEADER_SIZE, AbiType.nodeLength] at spans ⊢
    omega
  | dynamicArray element =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads fits.1.2 fits.1.1
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes] at spans ⊢
    simp [skipNode, metaRead, headerSize, ARRAY_HEADER_SIZE, AbiType.nodeLength] at spans ⊢
    omega
  | tuple fields =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads fits.1.2.2 fits.1.2.1
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes] at spans ⊢
    simp [skipNode, metaRead, headerSize, TUPLE_HEADER_SIZE, AbiType.nodeLength] at spans ⊢
    omega

theorem Descriptor.checkNode_encodeNode (abiType : AbiType) (fits : abiType.fits = true) (depth : Nat)
    (deep : abiType.withinDepth depth = true) (rest : Bytes) :
    checkNode depth (abiType.encodeNode ++ rest) = some abiType.nodeLength := by
  induction abiType generalizing depth rest with
  | word wordType =>
    have skips := skipNode_encodeNode _ fits rest
    rw [AbiType.encodeNode] at skips ⊢
    rw [checkNode.eq_def]
    simp only [List.cons_append, List.nil_append] at skips ⊢
    simp [skips]
  | bytes | string =>
    have skips := skipNode_encodeNode _ fits rest
    rw [AbiType.encodeNode] at skips ⊢
    rw [checkNode.eq_def]
    simp only [List.cons_append, List.nil_append] at skips ⊢
    simp [skips]
  | staticArray element length elementChecks =>
    have skips := skipNode_encodeNode _ fits rest
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨⟨⟨lengthPositive, lengthFits⟩, nodeLengthFits, staticWordsFit⟩, elementFits⟩ := fits
    simp only [AbiType.withinDepth, Bool.and_eq_true, decide_eq_true_eq] at deep
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads staticWordsFit nodeLengthFits
    obtain ⟨lengthHigh, lengthLow, lengthBytes, lengthRead⟩ :=
      be16_reads (by simp only [MAX_STATIC_ARRAY_LENGTH] at lengthFits; omega : length < 2 ^ 16)
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes, lengthBytes] at skips ⊢
    rw [checkNode.eq_def]
    simp only [List.cons_append, List.nil_append, List.append_assoc] at skips ⊢
    simp [skips, elementChecks elementFits (depth + 1) deep.2, decodeNode_encodeNode.drop_encodeNode, lengthRead,
      deep.1, lengthPositive, lengthFits]
  | dynamicArray element elementChecks =>
    have skips := skipNode_encodeNode _ fits rest
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨⟨nodeLengthFits, staticWordsFit⟩, elementFits⟩ := fits
    simp only [AbiType.withinDepth, Bool.and_eq_true, decide_eq_true_eq] at deep
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads staticWordsFit nodeLengthFits
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes] at skips ⊢
    rw [checkNode.eq_def]
    simp only [List.cons_append, List.nil_append] at skips ⊢
    simp [skips, elementChecks elementFits (depth + 1) deep.2, deep.1]
  | tuple fields fieldsCheck =>
    have skips := skipNode_encodeNode _ fits rest
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨⟨⟨countPositive, countFits⟩, nodeLengthFits, staticWordsFit⟩, fieldsFit⟩ := fits
    simp only [AbiType.withinDepth, Bool.and_eq_true, decide_eq_true_eq] at deep
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads staticWordsFit nodeLengthFits
    obtain ⟨countHigh, countLow, countBytes, countRead⟩ :=
      be16_reads (by simp only [MAX_TUPLE_FIELDS, MAX_NODE_LENGTH, TUPLE_HEADER_SIZE] at countFits; omega :
        fields.length < 2 ^ 16)
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes, countBytes] at skips ⊢
    rw [checkNode.eq_def]
    simp only [List.cons_append, List.nil_append] at skips ⊢
    simp [skips, countRead, deep.1, countPositive, countFits,
      checkNodes_encodeNodes fields fieldsCheck fieldsFit (depth + 1) deep.2]
where
  checkNodes_encodeNodes (fields : List AbiType)
      (checks : ∀ field ∈ fields, field.fits = true → ∀ depth, field.withinDepth depth = true → ∀ rest,
        checkNode depth (field.encodeNode ++ rest) = some field.nodeLength)
      (fit : AbiType.allFit fields = true) (depth : Nat) (deep : AbiType.allWithinDepth depth fields = true)
      (rest : Bytes) :
      checkNodes depth fields.length (AbiType.encodeNodes fields ++ rest) = some (AbiType.sumNodeLength fields) := by
    induction fields with
    | nil => simp [checkNodes, AbiType.sumNodeLength]
    | cons field fields fieldsCheck =>
      simp only [AbiType.allFit, AbiType.allWithinDepth, Bool.and_eq_true] at fit deep
      rw [List.length_cons, checkNodes, AbiType.encodeNodes, List.append_assoc,
        checks field (by simp) fit.1 depth deep.1]
      simp only [decodeNode_encodeNode.drop_encodeNode,
        fieldsCheck (fun other isMember => checks other (by simp [isMember])) fit.2 deep.2, Option.map_some,
        AbiType.sumNodeLength]

theorem Descriptor.checkNodes_encodeNodes (types : List AbiType) (fit : AbiType.allFit types = true) (depth : Nat)
    (deep : AbiType.allWithinDepth depth types = true) (rest : Bytes) :
    checkNodes depth types.length (AbiType.encodeNodes types ++ rest) = some (AbiType.sumNodeLength types) :=
  checkNode_encodeNode.checkNodes_encodeNodes types
    (fun field _ fits depth deep rest => checkNode_encodeNode field fits depth deep rest) fit depth deep rest

theorem Descriptor.wellFormed_encode (types : List AbiType) (limits : withinLimits types = true) :
    wellFormed (encode types) = true := by
  obtain ⟨countFits, fit, deep⟩ := (withinLimits_iff types).mp limits
  simp only [MAX_PARAMS, Nat.reducePow] at countFits
  have checks := checkNodes_encodeNodes types fit 1 deep []
  rw [List.append_nil] at checks
  simp [encode, wellFormed, VERSION, UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega : types.length < 256), checks,
    AbiType.encodeNodes_length]

/-! ## Decoded descriptors are encodings -/

/-- A decoded node is the encoding of its type, its span the type's node length. -/
theorem Descriptor.decode_reconstructs :
    (∀ bytes abiType span, decodeNode bytes = some (abiType, span) →
      span = abiType.nodeLength ∧ bytes = abiType.encodeNode ++ bytes.drop span) ∧
    (∀ count bytes types span, decodeNodes count bytes = some (types, span) →
      types.length = count ∧ span = AbiType.sumNodeLength types ∧
        bytes = AbiType.encodeNodes types ++ bytes.drop span) := by
  refine decodeNode.mutual_induct
    (fun bytes => ∀ abiType span, decodeNode bytes = some (abiType, span) →
      span = abiType.nodeLength ∧ bytes = abiType.encodeNode ++ bytes.drop span)
    (fun count bytes => ∀ types span, decodeNodes count bytes = some (types, span) →
      types.length = count ∧ span = AbiType.sumNodeLength types ∧ bytes = AbiType.encodeNodes types ++ bytes.drop span)
    ?empty ?word ?bytes ?string ?tuple ?tupleNone ?tupleShort ?staticArray ?staticArrayShort ?staticArrayNone
    ?dynamicArray ?dynamicArrayNone ?unknown ?metaShort ?nodesZero ?nodesSucc ?nodesSuccNone ?nodesNone
  case empty => intro abiType span decodes; simp [decodeNode] at decodes
  case tupleNone =>
    intro high middle low countHigh countLow fieldBytes noFields _ _ _ _ abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp [noFields] at decodes
  case tupleShort =>
    intro high middle low body short _ _ _ abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp at decodes
  case staticArrayShort =>
    intro high middle low body element elementSpan elementDecodes short _ _ _ _ _ abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp [elementDecodes] at decodes
  case staticArrayNone =>
    intro high middle low body noElement _ _ _ _ _ abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp [noElement] at decodes
  case dynamicArrayNone =>
    intro high middle low body noElement _ _ _ _ _ _ abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp [noElement] at decodes
  case unknown =>
    intro code notWord notBytes notString high middle low body notTuple notStatic notDynamic abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp [notWord, notBytes, notString, notTuple, notStatic, notDynamic] at decodes
  case metaShort =>
    intro code rest notWord notBytes notString short abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp [notWord, notBytes, notString] at decodes
  case nodesSuccNone =>
    intro count bytes element elementSpan elementDecodes noRest _ _ types span decodes
    simp [decodeNodes, elementDecodes, noRest] at decodes
  case nodesNone =>
    intro count bytes noElement _ types span decodes
    simp [decodeNodes, noElement] at decodes
  case word =>
    intro code rest wordType named abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp only [named, Option.some.injEq, Prod.mk.injEq] at decodes
    obtain ⟨rfl, rfl⟩ := decodes
    simp [AbiType.nodeLength, AbiType.encodeNode, WordType.code_of_ofCode? named]
  case bytes =>
    intro rest _ abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp at decodes
    obtain ⟨rfl, rfl⟩ := decodes
    simp [AbiType.nodeLength, AbiType.encodeNode]
  case string =>
    intro rest _ _ abiType span decodes
    rw [decodeNode.eq_def] at decodes
    simp at decodes
    obtain ⟨rfl, rfl⟩ := decodes
    simp [AbiType.nodeLength, AbiType.encodeNode]
  case tuple =>
    intro high middle low countHigh countLow fieldBytes fields fieldsSpan fieldsDecode _ _ _ fieldsRebuild abiType span
      decodes
    obtain ⟨count, fieldsSpanIs, fieldBytesAre⟩ := fieldsRebuild fields fieldsSpan fieldsDecode
    rw [decodeNode.eq_def] at decodes
    simp [fieldsDecode, checkMeta] at decodes
    obtain ⟨metaRead, rfl, rfl⟩ := decodes
    have nodeLengthIs : TUPLE_HEADER_SIZE + fieldsSpan = (AbiType.tuple fields).nodeLength := by
      simp [AbiType.nodeLength, fieldsSpanIs]
    rw [nodeLengthIs] at metaRead
    refine ⟨nodeLengthIs, ?_⟩
    rw [AbiType.encodeNode, AbiType.compositeHeader, compositeMeta_of_metaFields metaRead, count, be16_of_readBe16,
      show TUPLE_HEADER_SIZE + fieldsSpan = fieldsSpan + 1 + 1 + 1 + 1 + 1 + 1 by simp only [TUPLE_HEADER_SIZE]; omega]
    simp only [List.drop_succ_cons, List.cons_append, List.nil_append]
    rw [← fieldBytesAre]
  case staticArray =>
    intro high middle low body element elementSpan elementDecodes lengthHigh lengthLow tail lengthBytes _ _ _ _
      elementRebuild abiType span decodes
    obtain ⟨elementSpanIs, bodyIs⟩ := elementRebuild element elementSpan elementDecodes
    rw [decodeNode.eq_def] at decodes
    simp [elementDecodes, lengthBytes, checkMeta] at decodes
    obtain ⟨metaRead, rfl, rfl⟩ := decodes
    have nodeLengthIs : ARRAY_HEADER_SIZE + elementSpan + ARRAY_LENGTH_SIZE =
        (AbiType.staticArray element (readBe16 lengthHigh lengthLow)).nodeLength := by
      simp [AbiType.nodeLength, elementSpanIs]
    rw [nodeLengthIs] at metaRead
    refine ⟨nodeLengthIs, ?_⟩
    have tailIs : body.drop (elementSpan + 2) = tail := by
      rw [← List.drop_drop, lengthBytes]
      rfl
    rw [AbiType.encodeNode, AbiType.compositeHeader, compositeMeta_of_metaFields metaRead, be16_of_readBe16,
      show ARRAY_HEADER_SIZE + elementSpan + ARRAY_LENGTH_SIZE = elementSpan + 2 + 1 + 1 + 1 + 1 by
        simp only [ARRAY_HEADER_SIZE, ARRAY_LENGTH_SIZE]; omega]
    simp only [List.drop_succ_cons, List.cons_append, List.nil_append, List.append_assoc, tailIs]
    conv => lhs; rw [bodyIs, lengthBytes]
  case dynamicArray =>
    intro high middle low body element elementSpan elementDecodes _ _ _ _ _ elementRebuild abiType span decodes
    obtain ⟨elementSpanIs, bodyIs⟩ := elementRebuild element elementSpan elementDecodes
    rw [decodeNode.eq_def] at decodes
    simp [elementDecodes, checkMeta] at decodes
    obtain ⟨metaRead, rfl, rfl⟩ := decodes
    have nodeLengthIs : ARRAY_HEADER_SIZE + elementSpan = (AbiType.dynamicArray element).nodeLength := by
      simp [AbiType.nodeLength, elementSpanIs]
    rw [nodeLengthIs] at metaRead
    refine ⟨nodeLengthIs, ?_⟩
    rw [AbiType.encodeNode, AbiType.compositeHeader, compositeMeta_of_metaFields metaRead,
      show ARRAY_HEADER_SIZE + elementSpan = elementSpan + 1 + 1 + 1 + 1 by simp only [ARRAY_HEADER_SIZE]; omega]
    simp only [List.drop_succ_cons, List.cons_append, List.nil_append]
    rw [← bodyIs]
  case nodesZero =>
    intro bytes types span decodes
    simp only [decodeNodes, Option.some.injEq, Prod.mk.injEq] at decodes
    obtain ⟨rfl, rfl⟩ := decodes
    simp [AbiType.sumNodeLength, AbiType.encodeNodes]
  case nodesSucc =>
    intro count bytes element elementSpan elementDecodes rest restSpan restDecodes elementRebuild restRebuild types span
      decodes
    simp only [decodeNodes, elementDecodes, restDecodes, Option.some.injEq, Prod.mk.injEq] at decodes
    obtain ⟨rfl, rfl⟩ := decodes
    obtain ⟨elementSpanIs, bytesAre⟩ := elementRebuild element elementSpan elementDecodes
    obtain ⟨count, restSpanIs, restAre⟩ := restRebuild rest restSpan restDecodes
    refine ⟨by simp [count], by simp [AbiType.sumNodeLength, elementSpanIs, restSpanIs], ?_⟩
    rw [AbiType.encodeNodes, List.append_assoc, ← List.drop_drop, ← restAre, ← bytesAre]

/-! ## Inversion -/

theorem Descriptor.metaFields_le (high middle low : UInt8) :
    (metaFields high middle low).1 ≤ MAX_STATIC_WORDS ∧ (metaFields high middle low).2 ≤ MAX_NODE_LENGTH := by
  have := high.toNat_lt
  have := middle.toNat_lt
  have := low.toNat_lt
  simp only [metaFields, MAX_STATIC_WORDS, MAX_NODE_LENGTH, Nat.reducePow]
  omega

theorem Descriptor.decodeNode_staticArray {high middle low : UInt8} {body : Bytes} {abiType : AbiType} {span : Nat}
    (decodes : decodeNode (TypeCode.STATIC_ARRAY :: high :: middle :: low :: body) = some (abiType, span)) :
    ∃ element elementSpan lengthHigh lengthLow tail, decodeNode body = some (element, elementSpan) ∧
      body.drop elementSpan = lengthHigh :: lengthLow :: tail ∧
      abiType = .staticArray element (readBe16 lengthHigh lengthLow) ∧
      span = ARRAY_HEADER_SIZE + elementSpan + ARRAY_LENGTH_SIZE ∧
      metaFields high middle low = (abiType.staticWords, span) := by
  rw [decodeNode.eq_def] at decodes
  simp only [WordType.ofCode?_staticArray, TypeCode.staticArray_ne_bytes, TypeCode.staticArray_ne_string,
    TypeCode.staticArray_ne_tuple, ite_false, ite_true] at decodes
  split at decodes
  · rename_i element elementSpan elementDecodes
    split at decodes
    · rename_i lengthHigh lengthLow tail lengthBytes
      simp only [checkMeta] at decodes
      split at decodes
      · rename_i metaRead
        simp only [Option.some.injEq, Prod.mk.injEq] at decodes
        obtain ⟨rfl, rfl⟩ := decodes
        exact ⟨element, elementSpan, lengthHigh, lengthLow, tail, elementDecodes, lengthBytes, rfl, rfl, metaRead⟩
      · cases decodes
    · cases decodes
  · cases decodes

theorem Descriptor.decodeNode_dynamicArray {high middle low : UInt8} {body : Bytes} {abiType : AbiType} {span : Nat}
    (decodes : decodeNode (TypeCode.DYNAMIC_ARRAY :: high :: middle :: low :: body) = some (abiType, span)) :
    ∃ element elementSpan, decodeNode body = some (element, elementSpan) ∧ abiType = .dynamicArray element ∧
      span = ARRAY_HEADER_SIZE + elementSpan ∧ metaFields high middle low = (abiType.staticWords, span) := by
  rw [decodeNode.eq_def] at decodes
  simp only [WordType.ofCode?_dynamicArray, TypeCode.dynamicArray_ne_bytes, TypeCode.dynamicArray_ne_string,
    TypeCode.dynamicArray_ne_tuple, TypeCode.dynamicArray_ne_staticArray, ite_false, ite_true] at decodes
  split at decodes
  · rename_i element elementSpan elementDecodes
    simp only [checkMeta] at decodes
    split at decodes
    · rename_i metaRead
      simp only [Option.some.injEq, Prod.mk.injEq] at decodes
      obtain ⟨rfl, rfl⟩ := decodes
      exact ⟨element, elementSpan, elementDecodes, rfl, rfl, metaRead⟩
    · cases decodes
  · cases decodes

theorem Descriptor.decodeNode_tuple {high middle low countHigh countLow : UInt8} {fieldBytes : Bytes}
    {abiType : AbiType} {span : Nat}
    (decodes : decodeNode (TypeCode.TUPLE :: high :: middle :: low :: countHigh :: countLow :: fieldBytes) =
      some (abiType, span)) :
    ∃ fields fieldsSpan, decodeNodes (readBe16 countHigh countLow) fieldBytes = some (fields, fieldsSpan) ∧
      abiType = .tuple fields ∧ span = TUPLE_HEADER_SIZE + fieldsSpan ∧
      metaFields high middle low = (abiType.staticWords, span) := by
  rw [decodeNode.eq_def] at decodes
  simp only [WordType.ofCode?_tuple, TypeCode.tuple_ne_bytes, TypeCode.tuple_ne_string, ite_false, ite_true] at decodes
  split at decodes
  · rename_i fields fieldsSpan fieldsDecode
    simp only [checkMeta] at decodes
    split at decodes
    · rename_i metaRead
      simp only [Option.some.injEq, Prod.mk.injEq] at decodes
      obtain ⟨rfl, rfl⟩ := decodes
      exact ⟨fields, fieldsSpan, fieldsDecode, rfl, rfl, metaRead⟩
    · cases decodes
  · cases decodes

theorem Descriptor.checkNode_staticArray {depth : Nat} {high middle low : UInt8} {body : Bytes} {span : Nat}
    (checks : checkNode depth (TypeCode.STATIC_ARRAY :: high :: middle :: low :: body) = some span) :
    depth ≤ MAX_NESTING_DEPTH ∧ ∃ elementSpan lengthHigh lengthLow tail, checkNode (depth + 1) body = some elementSpan ∧
      body.drop elementSpan = lengthHigh :: lengthLow :: tail ∧ 0 < readBe16 lengthHigh lengthLow ∧
      readBe16 lengthHigh lengthLow ≤ MAX_STATIC_ARRAY_LENGTH := by
  rw [checkNode.eq_def] at checks
  simp only [TypeCode.staticArray_ne_tuple, ite_false, ite_true] at checks
  split at checks
  · cases checks
  · split at checks
    · rename_i shallow
      split at checks
      · rename_i elementSpan elementChecks
        split at checks
        · rename_i lengthHigh lengthLow tail lengthBytes
          split at checks
          · rename_i inRange
            exact ⟨shallow, elementSpan, lengthHigh, lengthLow, tail, elementChecks, lengthBytes, inRange⟩
          · cases checks
        · cases checks
      · cases checks
    · cases checks

theorem Descriptor.checkNode_dynamicArray {depth : Nat} {high middle low : UInt8} {body : Bytes} {span : Nat}
    (checks : checkNode depth (TypeCode.DYNAMIC_ARRAY :: high :: middle :: low :: body) = some span) :
    depth ≤ MAX_NESTING_DEPTH ∧ ∃ elementSpan, checkNode (depth + 1) body = some elementSpan := by
  rw [checkNode.eq_def] at checks
  simp only [TypeCode.dynamicArray_ne_tuple, TypeCode.dynamicArray_ne_staticArray, ite_false, ite_true] at checks
  split at checks
  · cases checks
  · split at checks
    · rename_i shallow
      cases elementChecks : checkNode (depth + 1) body with
      | none => simp [elementChecks] at checks
      | some elementSpan => exact ⟨shallow, elementSpan, rfl⟩
    · cases checks

theorem Descriptor.checkNode_tuple {depth : Nat} {high middle low countHigh countLow : UInt8} {fieldBytes : Bytes}
    {span : Nat}
    (checks : checkNode depth (TypeCode.TUPLE :: high :: middle :: low :: countHigh :: countLow :: fieldBytes) =
      some span) :
    depth ≤ MAX_NESTING_DEPTH ∧ 0 < readBe16 countHigh countLow ∧ readBe16 countHigh countLow ≤ MAX_TUPLE_FIELDS ∧
      ∃ fieldsSpan, checkNodes (depth + 1) (readBe16 countHigh countLow) fieldBytes = some fieldsSpan := by
  rw [checkNode.eq_def] at checks
  simp only [ite_true] at checks
  split at checks
  · cases checks
  · split at checks
    · rename_i inRange
      cases fieldsCheck : checkNodes (depth + 1) (readBe16 countHigh countLow) fieldBytes with
      | none => simp [fieldsCheck] at checks
      | some fieldsSpan => exact ⟨inRange.1, inRange.2.1, inRange.2.2, fieldsSpan, rfl⟩
    · cases checks

theorem Descriptor.decodeNodes_succ {count : Nat} {bytes : Bytes} {types : List AbiType} {span : Nat}
    (decodes : decodeNodes (count + 1) bytes = some (types, span)) :
    ∃ abiType nodeSpan rest restSpan, decodeNode bytes = some (abiType, nodeSpan) ∧
      decodeNodes count (bytes.drop nodeSpan) = some (rest, restSpan) ∧ types = abiType :: rest := by
  simp only [decodeNodes] at decodes
  split at decodes
  · rename_i abiType nodeSpan nodeDecodes
    split at decodes
    · rename_i rest restSpan restDecodes
      simp only [Option.some.injEq, Prod.mk.injEq] at decodes
      exact ⟨abiType, nodeSpan, rest, restSpan, nodeDecodes, restDecodes, decodes.1.symm⟩
    · cases decodes
  · cases decodes

theorem Descriptor.checkNodes_succ {depth count : Nat} {bytes : Bytes} {span : Nat}
    (checks : checkNodes depth (count + 1) bytes = some span) :
    ∃ nodeSpan restSpan, checkNode depth bytes = some nodeSpan ∧
      checkNodes depth count (bytes.drop nodeSpan) = some restSpan := by
  simp only [checkNodes] at checks
  split at checks
  · rename_i nodeSpan nodeChecks
    cases restChecks : checkNodes depth count (bytes.drop nodeSpan) with
    | none => simp [restChecks] at checks
    | some restSpan => exact ⟨nodeSpan, restSpan, nodeChecks, restChecks⟩
  · cases checks

/-! ## Well-formed decoded nodes are within limits -/

/-- A composite type's metadata within its fields: what decoding its node checks. -/
theorem Descriptor.metaFits_of_metaFields {abiType : AbiType} {high middle low : UInt8}
    (metaRead : metaFields high middle low = (abiType.staticWords, abiType.nodeLength)) : abiType.metaFits = true := by
  have bounds := metaFields_le high middle low
  rw [metaRead] at bounds
  simp [AbiType.metaFits, bounds.1, bounds.2]

/-- A node that decodes to its own type and is well-formed at `depth` fits and is within depth. -/
theorem Descriptor.limits_of_checkNode (abiType : AbiType) (depth : Nat) (rest : Bytes)
    (decodes : decodeNode (abiType.encodeNode ++ rest) = some (abiType, abiType.nodeLength))
    (checks : ∃ span, checkNode depth (abiType.encodeNode ++ rest) = some span) :
    abiType.fits = true ∧ abiType.withinDepth depth = true := by
  induction abiType generalizing depth rest with
  | word | bytes | string => simp [AbiType.fits, AbiType.withinDepth]
  | staticArray element length elementLimits =>
    obtain ⟨high, middle, low, metaBytes⟩ : ∃ high middle low,
        compositeMeta (AbiType.staticArray element length).staticWords (AbiType.staticArray element length).nodeLength =
          [high, middle, low] := ⟨_, _, _, rfl⟩
    obtain ⟨lengthHigh, lengthLow, lengthBytes⟩ : ∃ lengthHigh lengthLow, be16 length = [lengthHigh, lengthLow] :=
      ⟨_, _, rfl⟩
    obtain ⟨span, checks⟩ := checks
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes, lengthBytes] at decodes checks
    simp only [List.cons_append, List.nil_append, List.append_assoc] at decodes checks
    obtain ⟨decoded, elementSpan, readHigh, readLow, tail, elementDecodes, lengthAt, sameType, -, metaRead⟩ :=
      decodeNode_staticArray decodes
    simp only [AbiType.staticArray.injEq] at sameType
    obtain ⟨rfl, lengthRead⟩ := sameType
    have elementSpanIs := (decode_reconstructs.1 _ _ _ elementDecodes).1
    subst elementSpanIs
    rw [decodeNode_encodeNode.drop_encodeNode] at lengthAt
    simp only [List.cons.injEq] at lengthAt
    obtain ⟨rfl, rfl, -⟩ := lengthAt
    obtain ⟨shallow, elementCheckSpan, checkedHigh, checkedLow, checkedTail, elementChecks, checkedAt, positive,
      bounded⟩ := checkNode_staticArray checks
    obtain ⟨elementFits, elementDeep⟩ := elementLimits (depth + 1) _ elementDecodes ⟨_, elementChecks⟩
    rw [checkNode_encodeNode element elementFits (depth + 1) elementDeep, Option.some.injEq] at elementChecks
    subst elementChecks
    rw [decodeNode_encodeNode.drop_encodeNode] at checkedAt
    simp only [List.cons.injEq] at checkedAt
    obtain ⟨rfl, rfl, -⟩ := checkedAt
    have metaFit := metaFits_of_metaFields metaRead
    rw [← lengthRead] at positive bounded
    simp [AbiType.fits, AbiType.withinDepth, positive, bounded, metaFit, elementFits, shallow, elementDeep]
  | dynamicArray element elementLimits =>
    obtain ⟨high, middle, low, metaBytes⟩ : ∃ high middle low, compositeMeta (AbiType.dynamicArray element).staticWords
        (AbiType.dynamicArray element).nodeLength = [high, middle, low] := ⟨_, _, _, rfl⟩
    obtain ⟨span, checks⟩ := checks
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes] at decodes checks
    simp only [List.cons_append, List.nil_append] at decodes checks
    obtain ⟨decoded, elementSpan, elementDecodes, sameType, -, metaRead⟩ := decodeNode_dynamicArray decodes
    simp only [AbiType.dynamicArray.injEq] at sameType
    subst sameType
    have elementSpanIs := (decode_reconstructs.1 _ _ _ elementDecodes).1
    subst elementSpanIs
    obtain ⟨shallow, elementCheckSpan, elementChecks⟩ := checkNode_dynamicArray checks
    obtain ⟨elementFits, elementDeep⟩ := elementLimits (depth + 1) _ elementDecodes ⟨_, elementChecks⟩
    have metaFit := metaFits_of_metaFields metaRead
    simp [AbiType.fits, AbiType.withinDepth, metaFit, elementFits, shallow, elementDeep]
  | tuple fields fieldsLimits =>
    obtain ⟨high, middle, low, metaBytes⟩ : ∃ high middle low, compositeMeta (AbiType.tuple fields).staticWords
        (AbiType.tuple fields).nodeLength = [high, middle, low] := ⟨_, _, _, rfl⟩
    obtain ⟨countHigh, countLow, countBytes⟩ : ∃ countHigh countLow, be16 fields.length = [countHigh, countLow] :=
      ⟨_, _, rfl⟩
    obtain ⟨span, checks⟩ := checks
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes, countBytes] at decodes checks
    simp only [List.cons_append, List.nil_append] at decodes checks
    obtain ⟨decoded, fieldsSpan, fieldsDecode, sameType, -, metaRead⟩ := decodeNode_tuple decodes
    simp only [AbiType.tuple.injEq] at sameType
    subst sameType
    have countRead := (decode_reconstructs.2 _ _ _ _ fieldsDecode).1
    rw [← countRead] at fieldsDecode
    obtain ⟨shallow, positive, bounded, fieldsCheckSpan, fieldsCheck⟩ := checkNode_tuple checks
    rw [← countRead] at positive bounded fieldsCheck
    obtain ⟨fieldsFit, fieldsDeep⟩ :=
      limits_of_checkNodes fields (depth + 1) rest fieldsLimits fieldsDecode ⟨_, fieldsCheck⟩
    have metaFit := metaFits_of_metaFields metaRead
    simp [AbiType.fits, AbiType.withinDepth, metaFit, fieldsFit, shallow, fieldsDeep, positive, bounded]
where
  limits_of_checkNodes (fields : List AbiType) (depth : Nat) (rest : Bytes)
      (limits : ∀ field ∈ fields, ∀ depth rest, decodeNode (field.encodeNode ++ rest) = some (field, field.nodeLength) →
        (∃ span, checkNode depth (field.encodeNode ++ rest) = some span) →
        field.fits = true ∧ field.withinDepth depth = true)
      {fieldsSpan : Nat}
      (decodes : decodeNodes fields.length (AbiType.encodeNodes fields ++ rest) = some (fields, fieldsSpan))
      (checks : ∃ span, checkNodes depth fields.length (AbiType.encodeNodes fields ++ rest) = some span) :
      AbiType.allFit fields = true ∧ AbiType.allWithinDepth depth fields = true := by
    induction fields generalizing fieldsSpan with
    | nil => simp [AbiType.allFit, AbiType.allWithinDepth]
    | cons field fields fieldsLimits =>
      obtain ⟨span, checks⟩ := checks
      rw [List.length_cons, AbiType.encodeNodes, List.append_assoc] at decodes checks
      obtain ⟨decoded, nodeSpan, others, othersSpan, fieldDecodes, othersDecode, sameTypes⟩ := decodeNodes_succ decodes
      simp only [List.cons.injEq] at sameTypes
      obtain ⟨rfl, rfl⟩ := sameTypes
      have nodeSpanIs := (decode_reconstructs.1 _ _ _ fieldDecodes).1
      subst nodeSpanIs
      rw [decodeNode_encodeNode.drop_encodeNode] at othersDecode
      obtain ⟨checkedSpan, othersCheckSpan, fieldChecks, othersCheck⟩ := checkNodes_succ checks
      obtain ⟨fieldFits, fieldDeep⟩ := limits field (by simp) depth _ fieldDecodes ⟨_, fieldChecks⟩
      rw [checkNode_encodeNode field fieldFits depth fieldDeep, Option.some.injEq] at fieldChecks
      subst fieldChecks
      rw [decodeNode_encodeNode.drop_encodeNode] at othersCheck
      obtain ⟨othersFit, othersDeep⟩ := fieldsLimits (fun other isMember => limits other (by simp [isMember]))
        othersDecode ⟨_, othersCheck⟩
      simp [AbiType.allFit, AbiType.allWithinDepth, fieldFits, fieldDeep, othersFit, othersDeep]

/-! ## Theorem 10 -/

/-- Theorem 10: the valid descriptors are exactly the encodings of type lists within limits. -/
theorem Descriptor.valid_iff_encoded (desc : Bytes) :
    valid desc = true ↔ ∃ types, withinLimits types = true ∧ encode types = desc := by
  constructor
  · intro isValid
    simp only [valid, Bool.and_eq_true, Option.isSome_iff_exists] at isValid
    obtain ⟨isWellFormed, types, decodes⟩ := isValid
    rcases desc with _ | ⟨version, _ | ⟨count, body⟩⟩
    · simp [wellFormed] at isWellFormed
    · simp [wellFormed] at isWellFormed
    simp only [wellFormed, Bool.and_eq_true, beq_iff_eq] at isWellFormed
    obtain ⟨rfl, checks⟩ := isWellFormed
    simp only [decode, ite_true] at decodes
    split at decodes
    · rename_i decoded span nodesDecode
      split at decodes
      · rename_i spansBody
        simp only [Option.some.injEq] at decodes
        subst decodes spansBody
        obtain ⟨countIs, -, bodyIs⟩ := decode_reconstructs.2 _ _ _ _ nodesDecode
        rw [List.drop_length, List.append_nil] at bodyIs
        rw [bodyIs, ← countIs] at nodesDecode checks
        rw [← List.append_nil (AbiType.encodeNodes decoded)] at nodesDecode checks
        obtain ⟨fit, deep⟩ := limits_of_checkNode.limits_of_checkNodes decoded 1 []
          (fun field _ depth rest decodes checks => limits_of_checkNode field depth rest decodes checks) nodesDecode
          ⟨_, by simpa using checks⟩
        refine ⟨decoded, (withinLimits_iff decoded).mpr ⟨?_, fit, deep⟩, ?_⟩
        · have := count.toNat_lt
          simp only [MAX_PARAMS]
          omega
        · rw [encode, bodyIs, countIs, UInt8.ofNat_toNat]
      · cases decodes
    · cases decodes
  · rintro ⟨types, limits, rfl⟩
    simp [valid, wellFormed_encode types limits, decode_encode types limits]

/-! ## Theorems 12 and 13 and head sizes -/

/-- Theorem 12: the builder accepts exactly the type lists within limits. -/
theorem Descriptor.encode?_isSome_iff (types : List AbiType) : (encode? types).isSome ↔ withinLimits types = true := by
  rw [withinLimits_iff]
  constructor
  · intro accepted
    simp only [encode?] at accepted
    split at accepted
    · rename_i checks
      obtain ⟨countFits, eachFits, isWellFormed⟩ := checks
      have fit : AbiType.allFit types = true := by simpa [AbiType.allFit_iff] using eachFits
      refine ⟨countFits, fit, ?_⟩
      simp only [MAX_PARAMS, Nat.reducePow] at countFits
      simp only [encode, wellFormed, Bool.and_eq_true, beq_iff_eq, UInt8.toNat_ofNat',
        Nat.mod_eq_of_lt (by omega : types.length < 2 ^ 8)] at isWellFormed
      have decodes := decodeNodes_encodeNodes types fit []
      rw [List.append_nil] at decodes
      exact (limits_of_checkNode.limits_of_checkNodes types 1 []
        (fun field _ depth rest decodes checks => limits_of_checkNode field depth rest decodes checks)
        (by rwa [List.append_nil]) ⟨_, by simpa using isWellFormed.2⟩).2
    · cases accepted
  · intro limits
    have isWellFormed := wellFormed_encode types ((withinLimits_iff types).mpr limits)
    obtain ⟨countFits, fit, -⟩ := limits
    simp [encode?, countFits, isWellFormed, ← AbiType.allFit_iff, fit]

/-- A fitting type's head size is zero exactly when the type is dynamic (DV-2). -/
theorem AbiType.staticWords_eq_zero_iff (abiType : AbiType) (fits : abiType.fits = true) :
    abiType.staticWords = 0 ↔ abiType.isDynamic = true := by
  induction abiType with
  | word => simp [AbiType.staticWords, AbiType.isDynamic]
  | bytes | string => simp [AbiType.staticWords, AbiType.isDynamic]
  | staticArray element length elementZero =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    have := elementZero fits.2
    by_cases dynamic : element.isDynamic = true
    · simp [AbiType.staticWords, AbiType.isDynamic, dynamic]
    · simp only [dynamic, Bool.false_eq_true, iff_false] at this
      simp [AbiType.staticWords, AbiType.isDynamic, dynamic, Nat.mul_eq_zero, this]
      omega
  | dynamicArray => simp [AbiType.staticWords, AbiType.isDynamic]
  | tuple fields fieldsZero =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq, AbiType.allFit_iff] at fits
    obtain ⟨⟨⟨nonempty, -⟩, -⟩, fieldsFit⟩ := fits
    simp only [AbiType.staticWords, AbiType.isDynamic]
    split
    · simp_all
    · rename_i staticFields
      simp only [staticFields, Bool.false_eq_true, iff_false]
      obtain ⟨field, others, rfl⟩ : ∃ field others, fields = field :: others := by
        cases fields with
        | nil => simp at nonempty
        | cons field others => exact ⟨field, others, rfl⟩
      simp only [AbiType.anyDynamic, Bool.or_eq_true, not_or] at staticFields
      have fieldNonzero : field.staticWords ≠ 0 := fun zero =>
        staticFields.1 ((fieldsZero field (by simp) (fieldsFit field (by simp))).mp zero)
      simp only [AbiType.sumStaticWords]
      omega

/-- Theorem 13: a node's `staticWords` is its type's head size in words, zero when the type is dynamic. -/
theorem Descriptor.nodeStaticWords_encodeNode (abiType : AbiType) (fits : abiType.fits = true) (rest : Bytes) :
    nodeStaticWords (abiType.encodeNode ++ rest) = some abiType.staticWords := by
  cases abiType with
  | word wordType => simp [AbiType.encodeNode, nodeStaticWords, WordType.ofCode?_code, AbiType.staticWords]
  | bytes => simp [AbiType.encodeNode, nodeStaticWords, AbiType.staticWords]
  | string => simp [AbiType.encodeNode, nodeStaticWords, AbiType.staticWords]
  | staticArray element length =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads fits.1.2.2 fits.1.2.1
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes]
    simp [nodeStaticWords, metaRead]
  | dynamicArray element =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads fits.1.2 fits.1.1
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes]
    simp [nodeStaticWords, metaRead]
  | tuple fields =>
    simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
    obtain ⟨high, middle, low, metaBytes, metaRead⟩ := compositeMeta_reads fits.1.2.2 fits.1.2.1
    rw [AbiType.encodeNode, AbiType.compositeHeader, metaBytes]
    simp [nodeStaticWords, metaRead]

/-! ## Theorem 14 -/

theorem AbiType.encodeNodes_append (types others : List AbiType) :
    AbiType.encodeNodes (types ++ others) = AbiType.encodeNodes types ++ AbiType.encodeNodes others := by
  induction types <;> simp [AbiType.encodeNodes, *]

theorem AbiType.allFit_append (types others : List AbiType) :
    AbiType.allFit (types ++ others) = (AbiType.allFit types && AbiType.allFit others) := by
  induction types <;> simp [AbiType.allFit, Bool.and_assoc, *]

/-- Walking the first `index` nodes of an encoding reads the first `index` types. -/
theorem Descriptor.decodeNodes_take (types : List AbiType) (fit : AbiType.allFit types = true) (index : Nat)
    (within : index ≤ types.length) (rest : Bytes) :
    decodeNodes index (AbiType.encodeNodes types ++ rest) =
      some (types.take index, AbiType.sumNodeLength (types.take index)) := by
  have split := List.take_append_drop index types
  rw [← split, AbiType.allFit_append, Bool.and_eq_true] at fit
  conv => lhs; rw [← split, AbiType.encodeNodes_append, List.append_assoc]
  have := decodeNodes_encodeNodes (types.take index) fit.1 (AbiType.encodeNodes (types.drop index) ++ rest)
  rwa [List.length_take_of_le within] at this

/-- On a valid descriptor, the structural walk reaches only the starts of encodings of fitting types. -/
theorem Descriptor.encodeNode_at {desc : Bytes} {offset : Nat} (isValid : valid desc = true)
    (reached : NodeAt desc offset) :
    ∃ (abiType : AbiType) (rest : Bytes), abiType.fits = true ∧ desc.drop offset = abiType.encodeNode ++ rest := by
  obtain ⟨types, limits, rfl⟩ := (valid_iff_encoded desc).mp isValid
  obtain ⟨countFits, fit, -⟩ := (withinLimits_iff types).mp limits
  induction reached with
  | param descIs below nodesDecode =>
    rename_i version count body index decoded span
    simp only [encode, List.cons.injEq] at descIs
    obtain ⟨-, countIs, rfl⟩ := descIs
    simp only [MAX_PARAMS, Nat.reducePow] at countFits
    rw [← countIs, UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega : types.length < 2 ^ 8)] at below
    have walked := decodeNodes_take types fit index (by omega) []
    rw [List.append_nil, nodesDecode, Option.some.injEq, Prod.mk.injEq] at walked
    obtain ⟨-, rfl⟩ := walked
    have split := List.take_append_drop index types
    obtain ⟨abiType, others, othersAre⟩ : ∃ abiType others, types.drop index = abiType :: others := by
      cases dropped : types.drop index with
      | nil => simp at dropped; omega
      | cons abiType others => exact ⟨abiType, others, rfl⟩
    refine ⟨abiType, AbiType.encodeNodes others, ?_, ?_⟩
    · have := (AbiType.allFit_iff types).mp fit abiType (by rw [← split, othersAre]; simp)
      exact this
    · rw [show 2 + AbiType.sumNodeLength (types.take index) = AbiType.sumNodeLength (types.take index) + 1 + 1 by omega]
      have encodedIs : AbiType.encodeNodes types =
          AbiType.encodeNodes (types.take index) ++ AbiType.encodeNodes (types.drop index) := by
        rw [← AbiType.encodeNodes_append, split]
      simp only [encode, List.drop_succ_cons]
      rw [encodedIs, ← AbiType.encodeNodes_length, List.drop_left, othersAre, AbiType.encodeNodes]
  | field reachedTuple tupleAt below nodesDecode tupleIs =>
    rename_i tupleOffset high middle low countHigh countLow fieldBytes index decoded span
    obtain ⟨abiType, rest, fits, atTuple⟩ := tupleIs
    rw [tupleAt] at atTuple
    cases abiType with
    | tuple fields =>
      simp only [AbiType.fits, AbiType.metaFits, Bool.and_eq_true, decide_eq_true_eq] at fits
      obtain ⟨⟨⟨-, countFits⟩, -, -⟩, fieldsFit⟩ := fits
      simp only [MAX_TUPLE_FIELDS, MAX_NODE_LENGTH, TUPLE_HEADER_SIZE] at countFits
      obtain ⟨encodedHigh, encodedLow, countBytes, countRead⟩ := be16_reads (by omega : fields.length < 2 ^ 16)
      rw [AbiType.encodeNode, AbiType.compositeHeader, countBytes] at atTuple
      simp only [compositeMeta, List.cons_append, List.nil_append, List.cons.injEq] at atTuple
      obtain ⟨-, -, -, -, rfl, rfl, rfl⟩ := atTuple
      rw [countRead] at below
      have walked := decodeNodes_take fields fieldsFit index (Nat.le_of_lt below) rest
      rw [nodesDecode, Option.some.injEq, Prod.mk.injEq] at walked
      obtain ⟨-, rfl⟩ := walked
      have split := List.take_append_drop index fields
      obtain ⟨field, others, othersAre⟩ : ∃ field others, fields.drop index = field :: others := by
        cases dropped : fields.drop index with
        | nil => simp at dropped; omega
        | cons field others => exact ⟨field, others, rfl⟩
      refine ⟨field, AbiType.encodeNodes others ++ rest,
        (AbiType.allFit_iff fields).mp fieldsFit field (by rw [← split, othersAre]; simp), ?_⟩
      have encodedIs : AbiType.encodeNodes fields =
          AbiType.encodeNodes (fields.take index) ++ AbiType.encodeNodes (fields.drop index) := by
        rw [← AbiType.encodeNodes_append, split]
      rw [Nat.add_assoc, ← List.drop_drop, tupleAt,
        show TUPLE_HEADER_SIZE + AbiType.sumNodeLength (fields.take index) =
          AbiType.sumNodeLength (fields.take index) + 1 + 1 + 1 + 1 + 1 + 1 by simp only [TUPLE_HEADER_SIZE]; omega]
      simp only [List.drop_succ_cons]
      rw [encodedIs, List.append_assoc, ← AbiType.encodeNodes_length, List.drop_left, othersAre, AbiType.encodeNodes,
        List.append_assoc]
    | _ => simp [AbiType.encodeNode, AbiType.compositeHeader, fun wordType => (WordType.code_ne_tuple wordType).symm,
        (TypeCode.staticArray_ne_tuple).symm, (TypeCode.dynamicArray_ne_tuple).symm] at atTuple
  | element reachedArray arrayAt isArray arrayIs =>
    rename_i arrayOffset code rest
    obtain ⟨abiType, rest, fits, atArray⟩ := arrayIs
    rw [arrayAt] at atArray
    cases abiType with
    | staticArray element length =>
      simp only [AbiType.fits, Bool.and_eq_true] at fits
      refine ⟨element, be16 length ++ rest, fits.2, ?_⟩
      rw [← List.drop_drop, arrayAt, atArray, AbiType.encodeNode, AbiType.compositeHeader]
      simp [compositeMeta, ARRAY_HEADER_SIZE]
    | dynamicArray element =>
      simp only [AbiType.fits, Bool.and_eq_true] at fits
      refine ⟨element, rest, fits.2, ?_⟩
      rw [← List.drop_drop, arrayAt, atArray, AbiType.encodeNode, AbiType.compositeHeader]
      simp [compositeMeta, ARRAY_HEADER_SIZE]
    | _ =>
      simp only [AbiType.encodeNode, AbiType.compositeHeader, List.cons_append, List.cons.injEq] at atArray
      rcases isArray with rfl | rfl <;>
        simp_all [fun wordType => (WordType.code_ne_staticArray wordType).symm,
          fun wordType => (WordType.code_ne_dynamicArray wordType).symm]

/-- Theorem 14: on a valid descriptor, skipping a node by its `nodeLength` and walking its children end at the same
byte. -/
theorem Descriptor.skipNode_eq_walkNode {desc : Bytes} {offset : Nat} (isValid : valid desc = true)
    (reached : NodeAt desc offset) : skipNode (desc.drop offset) = walkNode (desc.drop offset) := by
  obtain ⟨abiType, rest, fits, nodeIs⟩ := encodeNode_at isValid reached
  rw [nodeIs, skipNode_encodeNode abiType fits rest, walkNode, decodeNode_encodeNode abiType fits rest]
  rfl

end Callcium
