// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IssueCode
/// @notice Machine-readable codes for policy validation issues.
library IssueCode {
    /*/////////////////////////////////////////////////////////////////////////
                                  TYPE MISMATCH
    /////////////////////////////////////////////////////////////////////////*/

    /// Descriptor whose composite node metadata disagrees with the node's children.
    bytes32 internal constant INVALID_DESCRIPTOR = "INVALID_DESCRIPTOR";

    /// Path that does not navigate the descriptor.
    bytes32 internal constant UNNAVIGABLE_PATH = "UNNAVIGABLE_PATH";

    /// Loop path that does not end at an array.
    bytes32 internal constant QUANTIFIER_ON_NON_ARRAY = "QUANTIFIER_ON_NON_ARRAY";

    /// Hint other than the compilation of its path against the descriptor.
    bytes32 internal constant HINT_MISMATCH = "HINT_MISMATCH";

    /// Ordering comparison on a type that is neither `uintN` nor `intN`.
    bytes32 internal constant NUMERIC_OP_ON_NON_NUMERIC = "NUMERIC_OP_ON_NON_NUMERIC";

    /// Bitmask comparison on a `bool` or `function`.
    bytes32 internal constant BITMASK_ON_INVALID = "BITMASK_ON_INVALID";

    /// IN on a `bool`.
    bytes32 internal constant IN_ON_BOOL = "IN_ON_BOOL";

    /// Context operand whose property type does not pair with the target type.
    bytes32 internal constant CONTEXT_TYPE_MISMATCH = "CONTEXT_TYPE_MISMATCH";

    /*/////////////////////////////////////////////////////////////////////////
                                  CONTRADICTION
    /////////////////////////////////////////////////////////////////////////*/

    /// Constant outside its type's values.
    bytes32 internal constant OUT_OF_PHYSICAL_BOUNDS = "OUT_OF_PHYSICAL_BOUNDS";

    /// Rule at which the rules on its subject stop being satisfiable together (PV-9).
    bytes32 internal constant CONTRADICTORY_RULE = "CONTRADICTORY_RULE";

    /*/////////////////////////////////////////////////////////////////////////
                                   REDUNDANCY
    /////////////////////////////////////////////////////////////////////////*/

    /// Rule the other rules on its subject imply (PV-9).
    bytes32 internal constant REDUNDANT_RULE = "REDUNDANT_RULE";

    /// Numeric bound is dominated by a stricter bound.
    bytes32 internal constant DOMINATED_BOUND = "DOMINATED_BOUND";

    /// Length bound is dominated by a stricter bound.
    bytes32 internal constant DOMINATED_LENGTH_BOUND = "DOMINATED_LENGTH_BOUND";

    /*/////////////////////////////////////////////////////////////////////////
                                     VACUITY
    /////////////////////////////////////////////////////////////////////////*/

    /// Rule that holds for every value and every context (PV-9).
    bytes32 internal constant VACUOUS_RULE = "VACUOUS_RULE";

    /*/////////////////////////////////////////////////////////////////////////
                                  COMPATIBILITY
    /////////////////////////////////////////////////////////////////////////*/

    /// Loop over a static array declared longer than `MAX_QUANTIFIED_ARRAY_LENGTH` (PV-7).
    bytes32 internal constant QUANTIFIER_OVER_STATIC_LIMIT = "QUANTIFIER_OVER_STATIC_LIMIT";

    /// Loop body that contains no test of the element (PV-8).
    bytes32 internal constant CONTEXT_ONLY_BODY = "CONTEXT_ONLY_BODY";
}
