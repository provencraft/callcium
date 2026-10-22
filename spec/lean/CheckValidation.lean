import Corpus

/-!
# Validation differential check

Recomputes the PV-9 issues on every line of an implementation's validation corpus, by enumeration over the values of
each subject (`validationIssues?`), and compares them with the issues the implementation wrote (`Corpus.check`). From
`spec/lean`:

```
lake exe check-validation <generated corpus> <implementation corpus>
```
-/

open Callcium Callcium.Corpus

/-- The oracle's issues on a line's blob. -/
def issuesOf : List String → Option String
  | [blob] => do return issuesField (← validationIssues? (← Policy.parse (← parseHex blob)))
  | _ => none

def main : List String → IO UInt32 := check 3 issuesOf
