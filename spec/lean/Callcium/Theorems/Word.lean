import Callcium.Word

/-!
# Word canonicity

Theorem 4: the enforcer's canonicity check accepts exactly the words Solidity's ABI decoder accepts.
-/

namespace Callcium

theorem ByteWidth.bits_le (width : ByteWidth) : width.bits ≤ 256 := by
  have := width.index.isLt
  simp only [ByteWidth.bits]
  omega

/-- A right-aligned value has no bits above its width exactly when the low mask keeps it. -/
theorem Word.ushiftRight_eq_zero_eq_and (word : Word) {bits : Nat} (fits : bits ≤ 256) :
    (word >>> bits == 0) = (word &&& BitVec.ofNat 256 (2 ^ bits - 1) == word) := by
  have maskFits : 2 ^ bits - 1 < 2 ^ 256 := by
    have := Nat.pow_le_pow_right (by decide : 0 < 2) fits
    have := Nat.one_le_two_pow (n := bits)
    omega
  apply Bool.eq_iff_iff.mpr
  simp only [beq_iff_eq, ← BitVec.toNat_inj, BitVec.toNat_ushiftRight, BitVec.toNat_and, BitVec.toNat_ofNat,
    Nat.mod_eq_of_lt maskFits, Nat.and_two_pow_sub_one_eq_mod, Nat.shiftRight_eq_div_pow]
  have powNonzero := Nat.pos_iff_ne_zero.mp (Nat.two_pow_pos bits)
  rw [show (0 : Word).toNat = 0 from rfl, Nat.div_eq_zero_iff, Nat.mod_eq_iff_lt powNonzero]
  simp only [powNonzero, false_or]

/-- A left-aligned value has no bits below its width exactly when the high mask keeps it. -/
theorem Word.shiftLeft_eq_zero_eq_and (word : Word) {bits : Nat} (fits : bits ≤ 256) :
    (word <<< bits == 0) = (word &&& (BitVec.allOnes 256 <<< (256 - bits)) == word) := by
  have lowBitsClear : (word <<< bits = 0) ↔ ∀ index < 256 - bits, word.getLsbD index = false := by
    constructor
    · intro isZero index below
      have := congrArg (·.getLsbD (index + bits)) isZero
      simp only [BitVec.getLsbD_shiftLeft] at this
      simpa [show index + bits < 256 by omega] using this
    · intro clear
      apply BitVec.eq_of_getLsbD_eq
      intro index below
      simp only [BitVec.getLsbD_shiftLeft]
      by_cases low : index < bits
      · simp [low]
      · simp [low, clear (index - bits) (by omega)]
  have maskKeeps : (word &&& (BitVec.allOnes 256 <<< (256 - bits)) = word) ↔
      ∀ index < 256 - bits, word.getLsbD index = false := by
    constructor
    · intro keeps index below
      have := congrArg (·.getLsbD index) keeps
      simp only [BitVec.getLsbD_and, BitVec.getLsbD_shiftLeft, BitVec.getLsbD_allOnes] at this
      simpa [below, show index < 256 by omega] using this.symm
    · intro clear
      apply BitVec.eq_of_getLsbD_eq
      intro index below
      simp only [BitVec.getLsbD_and, BitVec.getLsbD_shiftLeft, BitVec.getLsbD_allOnes]
      by_cases low : index < 256 - bits
      · simp [low, clear index low]
      · simp [low, below, show index - (256 - bits) < 256 by omega]
  apply Bool.eq_iff_iff.mpr
  simp only [beq_iff_eq]
  exact lowBitsClear.trans maskKeeps.symm

/-- A `bool` word has no bits above the lowest exactly when it is 0 or 1. -/
theorem Word.ushiftRight_one_eq_zero_eq (word : Word) :
    (word >>> 1 == 0) = ((if word == 0 then 0 else 1) == word) := by
  apply Bool.eq_iff_iff.mpr
  by_cases isZero : word = 0
  · simp [isZero]
  · have toNatNonzero : word.toNat ≠ 0 := by simpa [← BitVec.toNat_inj] using isZero
    simp only [isZero, beq_iff_eq, ← BitVec.toNat_inj, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
    simp
    omega

/-- Theorem 4: the enforcer's canonicity check accepts exactly the words Solidity's ABI decoder accepts. -/
theorem WordType.isCanonical_eq_solcAcceptsWord (wordType : WordType) (word : Word) :
    wordType.isCanonical word = wordType.solcAcceptsWord word := by
  cases wordType with
  | uint width => exact Word.ushiftRight_eq_zero_eq_and word width.bits_le
  | int width => rfl
  | address => exact Word.ushiftRight_eq_zero_eq_and word (by decide)
  | bool => exact Word.ushiftRight_one_eq_zero_eq word
  | function => exact Word.shiftLeft_eq_zero_eq_and word (bits := 192) (by decide)
  | fixedBytes width => exact Word.shiftLeft_eq_zero_eq_and word width.bits_le

end Callcium
