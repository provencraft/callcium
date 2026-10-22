import Callcium.Formula

/-!
# Joint binding

The tests of one `ANY` body read one element. Quantifying each rule on its own lets different elements meet different
conditions, which is the per-rule reading of `arg(0, ANY, 0).eq(T)` beside `arg(0, ANY, 1).gte(1000)`.

The policy below guards `f((address to, uint256 amount)[] transfers)`: some transfer pays the treasury at least 1000.
-/

namespace Callcium.JointBinding

/-- The treasury address. -/
def treasury : Word := 0x4e2b9a6f31c8d07e5a92b14f6d3c8e7a1b09f5c2

/-- Another address. -/
def recipient : Word := 0x91d04c7be3a25f68d1094e2ab7c35f80e6d21a4b

/-- The arguments of a call with these transfers. -/
def call (transfers : List (Word × Nat)) : Stack :=
  [⟨.list [.list (transfers.map fun (to, amount) => .list [.word to false, .word (BitVec.ofNat 256 amount) false])],
    none⟩]

/-- A call without context properties. -/
def noContext : Context := fun _ => none

/-- `to == treasury`. -/
def paysTreasury : Rule := .test [0] ⟨false, .eq, .constant [treasury]⟩

/-- `amount >= 1000`. -/
def atLeast1000 : Rule := .test [1] ⟨false, .gte, .constant [1000]⟩

/-- Both tests on one element. -/
def joint : Formula := [[.loop .any [0] [paysTreasury, atLeast1000]]]

/-- Each test quantified on its own: the per-rule reading of the two rules. -/
def perRule : Formula := [[.loop .any [0] [paysTreasury], .loop .any [0] [atLeast1000]]]

/-- One transfer pays the treasury nothing; another pays someone else 1000. -/
def decoy : Stack := call [(treasury, 0), (recipient, 1000)]

theorem perRule_accepts_decoy : perRule.holds noContext decoy = true := by decide

theorem joint_rejects_decoy : joint.holds noContext decoy = false := by decide

theorem joint_accepts_payment : joint.holds noContext (call [(recipient, 5), (treasury, 1000)]) = true := by decide

theorem joint_rejects_empty : joint.holds noContext (call []) = false := by decide

end Callcium.JointBinding
