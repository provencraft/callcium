// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Constraint } from "./Constraint.sol";
import { Descriptor } from "./Descriptor.sol";
import { IssueCode } from "./IssueCode.sol";
import { OpCode } from "./OpCode.sol";
import { OpRule } from "./OpRule.sol";
import { Path } from "./Path.sol";
import { PolicyData } from "./PolicyCoder.sol";
import { PolicyFormat as PF } from "./PolicyFormat.sol";
import { TypeCode } from "./TypeCode.sol";
import { TypeRule } from "./TypeRule.sol";
import { Issue, ValidationIssue } from "./ValidationIssue.sol";

import { LibBytes } from "solady/utils/LibBytes.sol";

/// @title PolicyValidator
/// @notice Semantic validation for policies - checks for type mismatches, contradictions, and redundancies.
library PolicyValidator {
    /// @dev Maximum tracked neq exclusions (holes) per bound domain; exclusion tracking is best-effort beyond this.
    uint8 private constant MAX_HOLES = 8;

    /// @dev Maximum tracked notIn exclusions per set domain; exclusion tracking is best-effort beyond this.
    uint8 private constant MAX_NOT_IN = 8;

    /// @dev Internal struct to track bound state for numeric values or lengths.
    struct BoundDomain {
        /// True if the type is signed (always false for length domains).
        bool isSigned;
        /// Physical minimum of the domain.
        uint256 min;
        /// Physical maximum of the domain.
        uint256 max;
        /// True if an equality constraint is set.
        bool hasEq;
        /// The equality value.
        uint256 eq;
        /// True if a lower bound is set.
        bool hasLower;
        /// The lower bound value.
        uint256 lower;
        /// True if the lower bound is inclusive (>=).
        bool lowerInclusive;
        /// True if an upper bound is set.
        bool hasUpper;
        /// The upper bound value.
        uint256 upper;
        /// True if the upper bound is inclusive (<=).
        bool upperInclusive;
        /// Pragmatic hole tracking (neq values).
        uint256[MAX_HOLES] holes;
        /// Number of holes tracked.
        uint8 holeCount;
    }

    /// @dev Internal struct to track bitmask state.
    struct BitmaskDomain {
        /// Accumulated bits that must be set.
        uint256 mustBeOne;
        /// Accumulated bits that must be zero.
        uint256 mustBeZero;
    }

    /// @dev Internal struct to track set membership state.
    struct SetDomain {
        /// True if an isIn() constraint is set.
        bool hasIn;
        /// The current allowed values from isIn() intersections.
        uint256[] inValues;
        /// Excluded values from notIn()/neq() operators.
        uint256[MAX_NOT_IN] notInValues;
        /// Number of excluded values tracked.
        uint8 notInCount;
    }

    /// @dev Context for validating a single constraint or a set of constraints on the same path.
    struct ConstraintContext {
        /// The rule scope (context or calldata).
        uint8 scope;
        /// The encoded path for this context.
        bytes path;
        /// Type information at the resolved path.
        Descriptor.TypeInfo typeInfo;
        /// Numeric bounds domain.
        BoundDomain numeric;
        /// Bitmask domain.
        BitmaskDomain bitmask;
        /// Length bounds domain (isSigned=false, min=0, max=uint32.max).
        BoundDomain length;
        /// Set membership domain.
        SetDomain set;
    }

    /// @dev Mutable state for the validating pass.
    struct ValidationState {
        /// The policy data being validated.
        PolicyData data;
        /// Pre-allocated array for collecting issues.
        Issue[] tempIssues;
        /// Number of issues collected so far.
        uint256 issueCount;
    }

    /*/////////////////////////////////////////////////////////////////////////
                                        ERRORS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when validate finds errors and the caller wants to revert.
    /// @param issues The validate issues found.
    error ValidationError(Issue[] issues);

    /*/////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @notice Validates policy data for semantic issues.
    /// @param data The policy data to validate.
    /// @return issues All validation issues found.
    function validate(PolicyData memory data) internal pure returns (Issue[] memory issues) {
        // Estimate max issues (worst case: one per operator in all constraints).
        uint256 maxIssues = _countOperators(data);
        ValidationState memory state =
            ValidationState({ data: data, tempIssues: new Issue[](maxIssues), issueCount: 0 });

        uint256 groupCount = data.groups.length;
        for (uint32 groupIndex; groupIndex < groupCount; ++groupIndex) {
            if (data.groups[groupIndex].length == 0) {
                state.tempIssues[state.issueCount++] = ValidationIssue.emptyGroup(groupIndex);
                continue;
            }
            _validateGroup(state, groupIndex);
        }

        // Trim worst-case array to actual length.
        issues = state.tempIssues;
        uint256 issueCount = state.issueCount;
        assembly ("memory-safe") {
            mstore(issues, issueCount)
        }
    }

    /// @dev Validates all constraints in a single group for cross-constraint analysis.
    function _validateGroup(ValidationState memory state, uint32 groupIndex) private pure {
        Constraint[] memory constraints = state.data.groups[groupIndex];
        uint256 constraintCount = constraints.length;

        // Rules within a group are AND-ed, so constraints on the same path interact.
        // A ConstraintContext accumulates bound/set/bitmask state across all constraints
        // sharing a (scope, path) pair, enabling cross-constraint contradiction detection.
        ConstraintContext[] memory contexts = new ConstraintContext[](constraintCount);
        uint256 contextCount;

        for (uint32 constraintIndex; constraintIndex < constraintCount; ++constraintIndex) {
            Constraint memory constraint = constraints[constraintIndex];

            // Look up existing context for this (scope, path) pair.
            // ctxIdx == max signals no match found; a new context will be created.
            uint256 ctxIdx = type(uint256).max;
            for (uint256 i; i < contextCount; ++i) {
                if (contexts[i].scope == constraint.scope && LibBytes.eq(contexts[i].path, constraint.path)) {
                    ctxIdx = i;
                    break;
                }
            }

            // First constraint on this path: resolve its type and create a fresh context.
            ConstraintContext memory ctx;
            if (ctxIdx == type(uint256).max) {
                Descriptor.TypeInfo memory typeInfo;
                if (constraint.scope == PF.SCOPE_CALLDATA) {
                    // Compatibility warnings against the reference enforcer's limits (spec §9.1).
                    uint256 depth = constraint.path.length / 2;
                    if (depth > PF.MAX_PATH_DEPTH) {
                        // forgefmt: disable-next-item
                        state.tempIssues[state.issueCount++] = ValidationIssue.pathDepthExceeded(
                            groupIndex, constraintIndex, depth, PF.MAX_PATH_DEPTH
                        );
                    }
                    uint256 quantifiedLength;
                    (typeInfo, quantifiedLength) = Descriptor.walkPath(state.data.descriptor, constraint.path);
                    if (quantifiedLength > PF.MAX_QUANTIFIED_ARRAY_LENGTH) {
                        state.tempIssues[state.issueCount++] = ValidationIssue.quantifierOverStaticLimit(
                            groupIndex, constraintIndex, quantifiedLength, PF.MAX_QUANTIFIED_ARRAY_LENGTH
                        );
                    }
                } else {
                    uint16 ctxId = Path.atUnchecked(constraint.path, 0);
                    if (ctxId > PF.CTX_MAX) {
                        // forgefmt: disable-next-item
                        state.tempIssues[state.issueCount++] = ValidationIssue.unknownContextProperty(
                            groupIndex, constraintIndex, ctxId, PF.CTX_MAX
                        );
                    }
                    typeInfo = Descriptor.TypeInfo({
                        code: (ctxId == PF.CTX_MSG_SENDER || ctxId == PF.CTX_TX_ORIGIN)
                            ? TypeCode.ADDRESS
                            : TypeCode.UINT256,
                        isDynamic: false,
                        staticSize: 32
                    });
                }
                ctx = _initContext(constraint.scope, constraint.path, typeInfo);
                contexts[contextCount++] = ctx;
                ctxIdx = contextCount - 1;
            } else {
                ctx = contexts[ctxIdx];
            }

            // Validate operators and accumulate bound/set state into the context.
            // forgefmt: disable-next-item
            state.issueCount = _validateConstraint(
                ctx, constraint, groupIndex, constraintIndex, state.tempIssues, state.issueCount
            );

            // Fusible range detection.
            // forgefmt: disable-next-item
            state.issueCount = _checkFusibleRange(
                ctx, constraint.operators, groupIndex, constraintIndex, state.tempIssues, state.issueCount
            );

            // Write back so later constraints on the same path see accumulated state.
            contexts[ctxIdx] = ctx;
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                                 PRIVATE FUNCTIONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Validates a single constraint's operators and updates the path's context.
    function _validateConstraint(
        ConstraintContext memory ctx,
        Constraint memory constraint,
        uint32 groupIndex,
        uint32 constraintIndex,
        Issue[] memory issues,
        uint256 issueCount
    )
        private
        pure
        returns (uint256)
    {
        bytes[] memory operators = constraint.operators;
        uint256 operatorCount = operators.length;
        bool underAny = _hasAnyQuantifier(constraint);

        for (uint256 i; i < operatorCount; ++i) {
            bytes memory op = operators[i];
            uint8 opCode = uint8(op[0]);
            uint8 base = opCode & ~OpCode.NOT;
            bool isNegated = (opCode & OpCode.NOT) != 0;

            // An unassigned opcode or mismatched payload size has no defined semantics to analyze.
            uint256 dataLength = op.length - 1;
            // forge-lint: disable-next-line(unsafe-typecast) guarded by the preceding bound check.
            if (dataLength > type(uint16).max || !OpRule.isValidPayloadSize(base, uint16(dataLength))) {
                issues[issueCount++] = ValidationIssue.fromOpRule(
                    IssueCode.UNKNOWN_OPERATOR,
                    OpRule.compatibilityMessage(IssueCode.UNKNOWN_OPERATOR),
                    groupIndex,
                    constraintIndex,
                    opCode
                );
                continue;
            }

            // A negated operator under any() is satisfied by a single decoy element.
            if (underAny && isNegated) {
                issues[issueCount++] = ValidationIssue.negationUnderAny(groupIndex, constraintIndex, opCode);
            }

            // Type compatibility check (delegates to OpRule).
            // forgefmt: disable-next-item
            (bool compatible, bytes32 code) = OpRule.checkCompatibility(
                base, ctx.typeInfo.code, ctx.typeInfo.isDynamic, ctx.typeInfo.staticSize
            );

            if (!compatible) {
                issues[issueCount++] = ValidationIssue.fromOpRule(
                    code, OpRule.compatibilityMessage(code), groupIndex, constraintIndex, opCode
                );
                continue;
            }

            // Domain updates (contradiction, redundancy, and vacuity detection).
            if (OpRule.isValueOp(base)) {
                // A non-canonical operand can never equal a canonicalized runtime value (PC-1, spec section 4.5),
                // so the rule is unsatisfiable or vacuous; skip analyzing the garbage word.
                // Scoped to the left-aligned types: numeric, address, and bool operands
                // are already covered by the physical domain limits.
                uint8 typeCode = ctx.typeInfo.code;
                if (TypeRule.isLeftAligned(typeCode)) {
                    (bool nonCanonical, bytes32 word, bytes32 canonical) = _findNonCanonicalWord(op, typeCode);
                    if (nonCanonical) {
                        // forgefmt: disable-next-item
                        issues[issueCount++] = ValidationIssue.nonCanonicalOperand(
                            groupIndex, constraintIndex, word, canonical
                        );
                        continue;
                    }
                }

                if (base >= OpCode.EQ && base <= OpCode.BETWEEN) {
                    if (base == OpCode.BETWEEN) {
                        // A negated range is a disjunction (value < low OR value > high); the
                        // single-interval accumulator cannot represent it, so leave it un-analyzed
                        // rather than mismodel it as two AND-ed bounds, which falsely reports a
                        // contradiction. Positive between decomposes into a lower and an upper bound.
                        if (!isNegated) {
                            (uint256 low, uint256 high) = _readPair(op);
                            issueCount = _updateBound(
                                ctx.numeric,
                                OpCode.GTE,
                                false,
                                low,
                                false,
                                groupIndex,
                                constraintIndex,
                                issues,
                                issueCount
                            );
                            issueCount = _updateBound(
                                ctx.numeric,
                                OpCode.LTE,
                                false,
                                high,
                                false,
                                groupIndex,
                                constraintIndex,
                                issues,
                                issueCount
                            );
                        }
                    } else {
                        uint256 value = _readValue(op);
                        uint8 holesBefore = ctx.numeric.holeCount;
                        issueCount = _updateBound(
                            ctx.numeric, base, isNegated, value, false, groupIndex, constraintIndex, issues, issueCount
                        );
                        // Cross-domain: neq holes can empty the isIn set.
                        if (ctx.numeric.holeCount > holesBefore) {
                            issueCount = _checkSetEmpty(ctx, groupIndex, constraintIndex, issues, issueCount);
                        }
                    }
                } else if (OpRule.isBitmaskOp(base)) {
                    uint256 mask = _readValue(op);
                    // forgefmt: disable-next-item
                    issueCount = _updateBitmask(
                        ctx, base, isNegated, mask, groupIndex, constraintIndex, issues, issueCount
                    );
                } else if (base == OpCode.IN) {
                    uint256[] memory values = _unpackSet(op);
                    if (!_isStrictlyAscending(values)) {
                        issues[issueCount++] = ValidationIssue.unsortedInSet(groupIndex, constraintIndex);
                    } else {
                        issueCount = _updateSet(ctx, isNegated, values, groupIndex, constraintIndex, issues, issueCount);
                    }
                }
            } else if (OpRule.isLengthOp(base)) {
                if (base == OpCode.LENGTH_BETWEEN) {
                    // A negated length range is a disjunction; see the value-between note above.
                    if (!isNegated) {
                        (uint256 low, uint256 high) = _readPair(op);
                        issueCount = _updateBound(
                            ctx.length, OpCode.GTE, false, low, true, groupIndex, constraintIndex, issues, issueCount
                        );
                        issueCount = _updateBound(
                            ctx.length, OpCode.LTE, false, high, true, groupIndex, constraintIndex, issues, issueCount
                        );
                    }
                } else {
                    uint256 value = _readValue(op);
                    issueCount = _updateBound(
                        ctx.length,
                        _normalizeLengthOp(base),
                        isNegated,
                        value,
                        true,
                        groupIndex,
                        constraintIndex,
                        issues,
                        issueCount
                    );
                }
            }
        }

        // Duplicate operator detection.
        issueCount = _checkDuplicates(issues, issueCount, operators, groupIndex, constraintIndex);

        return issueCount;
    }

    /// @dev Reports a lone unnegated gte/lte pair (value or length domain) as fusible into the
    /// corresponding single range operator. Fires only for a satisfiable pair on a compatible
    /// type; contradictions and dominated bounds are already reported by the domain checks.
    function _checkFusibleRange(
        ConstraintContext memory ctx,
        bytes[] memory operators,
        uint32 groupIndex,
        uint32 constraintIndex,
        Issue[] memory issues,
        uint256 issueCount
    )
        private
        pure
        returns (uint256)
    {
        (bool hasPair, uint256 low, uint256 high) = _findLonePair(operators, OpCode.GTE, OpCode.LTE);
        (bool compatible,) =
            OpRule.checkCompatibility(OpCode.GTE, ctx.typeInfo.code, ctx.typeInfo.isDynamic, ctx.typeInfo.staticSize);
        if (hasPair && compatible && _isLte(low, high, ctx.numeric.isSigned)) {
            issues[issueCount++] = ValidationIssue.fusibleRange(false, groupIndex, constraintIndex, low, high);
        }

        (hasPair, low, high) = _findLonePair(operators, OpCode.LENGTH_GTE, OpCode.LENGTH_LTE);
        (compatible,) = OpRule.checkCompatibility(
            OpCode.LENGTH_GTE, ctx.typeInfo.code, ctx.typeInfo.isDynamic, ctx.typeInfo.staticSize
        );
        if (hasPair && compatible && low <= high) {
            issues[issueCount++] = ValidationIssue.fusibleRange(true, groupIndex, constraintIndex, low, high);
        }

        return issueCount;
    }

    /// @dev Returns whether the operators contain exactly one of each unnegated bound opcode,
    /// along with the two operand values.
    function _findLonePair(
        bytes[] memory operators,
        uint8 lowerOp,
        uint8 upperOp
    )
        private
        pure
        returns (bool hasPair, uint256 low, uint256 high)
    {
        uint256 lowerCount;
        uint256 upperCount;

        for (uint256 i; i < operators.length; ++i) {
            bytes memory op = operators[i];
            uint8 opCode = uint8(op[0]);
            // forge-lint: disable-next-line(unsafe-typecast) guarded by the payload size check.
            if (
                op.length - 1 > type(uint16).max
                    || !OpRule.isValidPayloadSize(opCode & ~OpCode.NOT, uint16(op.length - 1))
            ) continue;
            if (opCode == lowerOp) {
                ++lowerCount;
                low = _readValue(op);
            } else if (opCode == upperOp) {
                ++upperCount;
                high = _readValue(op);
            }
        }

        hasPair = lowerCount == 1 && upperCount == 1;
    }

    /// @dev Updates a bound domain with a new operator and detects contradictions/redundancies.
    /// Handles both numeric and length domains via the `isLength` flag for issue dispatch.
    function _updateBound(
        BoundDomain memory domain,
        uint8 base,
        bool isNegated,
        uint256 value,
        bool isLength,
        uint32 groupIndex,
        uint32 constraintIndex,
        Issue[] memory issues,
        uint256 issueCount
    )
        private
        pure
        returns (uint256)
    {
        bool changedEq = false;
        bool changedLower = false;
        bool changedUpper = false;

        // Negation handling.
        // Negated comparisons are converted to their positive equivalents: !gt(v) -> lte(v), etc.
        // Negated equality (neq) is handled separately as a hole.
        if (isNegated) {
            if (base == OpCode.EQ) {
                if (domain.hasEq && domain.eq == value) {
                    // forgefmt: disable-next-item
                    issues[issueCount++] = ValidationIssue.eqNeqContradiction(
                        isLength, groupIndex, constraintIndex, value
                    );
                }
                // Add to holes if not already present.
                bool alreadyHole = false;
                for (uint8 j; j < domain.holeCount; ++j) {
                    if (domain.holes[j] == value) {
                        alreadyHole = true;
                        break;
                    }
                }
                if (!alreadyHole && domain.holeCount < MAX_HOLES) domain.holes[domain.holeCount++] = value;
            } else {
                // Convert negated bound to positive equivalent and re-enter.
                return _updateBound(
                    domain,
                    _negateBoundOp(base),
                    false,
                    value,
                    isLength,
                    groupIndex,
                    constraintIndex,
                    issues,
                    issueCount
                );
            }
            return issueCount;
        }

        // Vacuity checks.
        if (base == OpCode.GTE && value == domain.min) {
            issues[issueCount++] = ValidationIssue.vacuousGte(isLength, groupIndex, constraintIndex, value);
        } else if (base == OpCode.LTE && value == domain.max) {
            issues[issueCount++] = ValidationIssue.vacuousLte(isLength, groupIndex, constraintIndex, value);
        }

        // Physical bounds and impossibility.
        if (_isLt(value, domain.min, domain.isSigned) || _isGt(value, domain.max, domain.isSigned)) {
            issues[issueCount++] = ValidationIssue.outOfPhysicalBounds(isLength, groupIndex, constraintIndex, value);
        } else if (base == OpCode.GT && value == domain.max) {
            issues[issueCount++] = ValidationIssue.impossibleGt(isLength, groupIndex, constraintIndex, value);
        } else if (base == OpCode.LT && value == domain.min) {
            issues[issueCount++] = ValidationIssue.impossibleLt(isLength, groupIndex, constraintIndex, value);
        }

        // Equality handling.
        if (base == OpCode.EQ) {
            if (!domain.hasEq || domain.eq != value) changedEq = true;
            if (domain.hasEq) {
                if (domain.eq != value) {
                    // forgefmt: disable-next-item
                    issues[issueCount++] = ValidationIssue.conflictingEquality(
                        isLength, groupIndex, constraintIndex, domain.eq, value
                    );
                }
            }
            for (uint8 j; j < domain.holeCount; ++j) {
                if (domain.holes[j] == value) {
                    // forgefmt: disable-next-item
                    issues[issueCount++] = ValidationIssue.eqNeqContradiction(
                        isLength, groupIndex, constraintIndex, value
                    );
                }
            }
            domain.hasEq = true;
            domain.eq = value;
        }
        // Lower bound handling.
        else if (base == OpCode.GT || base == OpCode.GTE) {
            bool inclusive = (base == OpCode.GTE);
            if (domain.hasLower) {
                // Determine if the new bound is redundant (weaker or equal) or strictly tighter.
                // At the same value, gt beats gte (stricter); gte after gt is silently looser.
                bool redundant = false;
                bool strictlyBetter = false;

                if (_isLt(value, domain.lower, domain.isSigned)) {
                    redundant = true;
                } else if (value == domain.lower) {
                    if (domain.lowerInclusive) {
                        if (!inclusive) strictlyBetter = true;
                        else redundant = true;
                    } else {
                        if (!inclusive) redundant = true;
                        // else inclusive: looser, ignore silently.
                    }
                } else {
                    strictlyBetter = true;
                }

                if (redundant) {
                    issues[issueCount++] = ValidationIssue.dominatedBound(isLength, groupIndex, constraintIndex, value);
                }

                if (strictlyBetter) {
                    // forgefmt: disable-next-item
                    issues[issueCount++] = ValidationIssue.dominatedBound(
                        isLength, groupIndex, constraintIndex, domain.lower
                    );
                    domain.lower = value;
                    domain.lowerInclusive = inclusive;
                    changedLower = true;
                }
            } else {
                domain.hasLower = true;
                domain.lower = value;
                domain.lowerInclusive = inclusive;
                changedLower = true;
            }
        }
        // Upper bound handling.
        else if (base == OpCode.LT || base == OpCode.LTE) {
            bool inclusive = (base == OpCode.LTE);
            if (domain.hasUpper) {
                // Mirror of lower-bound dominance: lt beats lte at the same value.
                bool redundant = false;
                bool strictlyBetter = false;

                if (_isGt(value, domain.upper, domain.isSigned)) {
                    redundant = true;
                } else if (value == domain.upper) {
                    if (domain.upperInclusive) {
                        if (!inclusive) strictlyBetter = true;
                        else redundant = true;
                    } else {
                        if (!inclusive) redundant = true;
                        // else inclusive: looser, ignore silently.
                    }
                } else {
                    strictlyBetter = true;
                }

                if (redundant) {
                    issues[issueCount++] = ValidationIssue.dominatedBound(isLength, groupIndex, constraintIndex, value);
                }

                if (strictlyBetter) {
                    // forgefmt: disable-next-item
                    issues[issueCount++] = ValidationIssue.dominatedBound(
                        isLength, groupIndex, constraintIndex, domain.upper
                    );
                    domain.upper = value;
                    domain.upperInclusive = inclusive;
                    changedUpper = true;
                }
            } else {
                domain.hasUpper = true;
                domain.upper = value;
                domain.upperInclusive = inclusive;
                changedUpper = true;
            }
        }

        // Cross-checks: equality vs bounds.
        // When both eq and a bound exist, exactly one of two issues applies: either eq is
        // excluded by the bound (contradiction), or the bound is redundant because eq pins the value.
        // forgefmt: disable-next-item
        if (changedEq || changedLower) {
            if (domain.hasEq && domain.hasLower) {
                bool contradiction = domain.lowerInclusive
                    ? _isLt(domain.eq, domain.lower, domain.isSigned)
                    : _isLte(domain.eq, domain.lower, domain.isSigned);
                if (contradiction) {
                    issues[issueCount++] = ValidationIssue.boundsExcludeEquality(
                        isLength, groupIndex, constraintIndex, domain.eq, domain.lower
                    );
                } else {
                    issues[issueCount++] = ValidationIssue.redundantBound(
                        isLength, groupIndex, constraintIndex, domain.lower, domain.eq
                    );
                }
            }
        }

        // forgefmt: disable-next-item
        if (changedEq || changedUpper) {
            if (domain.hasEq && domain.hasUpper) {
                bool contradiction = domain.upperInclusive
                    ? _isGt(domain.eq, domain.upper, domain.isSigned)
                    : _isGte(domain.eq, domain.upper, domain.isSigned);
                if (contradiction) {
                    issues[issueCount++] = ValidationIssue.boundsExcludeEquality(
                        isLength, groupIndex, constraintIndex, domain.eq, domain.upper
                    );
                } else {
                    issues[issueCount++] = ValidationIssue.redundantBound(
                        isLength, groupIndex, constraintIndex, domain.upper, domain.eq
                    );
                }
            }
        }

        // Cross-check: lower vs upper bound.
        // forgefmt: disable-next-item
        if (changedLower || changedUpper) {
            if (domain.hasLower && domain.hasUpper) {
                // A range where lower == upper is only satisfiable if both bounds are inclusive.
                bool impossible = _isGt(domain.lower, domain.upper, domain.isSigned)
                    || (domain.lower == domain.upper && (!domain.lowerInclusive || !domain.upperInclusive));
                if (impossible) {
                    issues[issueCount++] = ValidationIssue.impossibleRange(
                        isLength, groupIndex, constraintIndex, domain.lower, domain.upper
                    );
                }
            }
        }

        return issueCount;
    }

    /// @dev Updates the set membership domain with new values and detects contradictions/redundancies.
    function _updateSet(
        ConstraintContext memory ctx,
        bool isNegated,
        uint256[] memory values,
        uint32 groupIndex,
        uint32 constraintIndex,
        Issue[] memory issues,
        uint256 issueCount
    )
        private
        pure
        returns (uint256)
    {
        if (isNegated) {
            for (uint256 i; i < values.length; ++i) {
                uint256 value = values[i];
                if (ctx.numeric.hasEq && ctx.numeric.eq == value) {
                    issues[issueCount++] = ValidationIssue.setExcludesEquality(groupIndex, constraintIndex, value);
                }

                if (ctx.set.hasIn) {
                    bool inSet = false;
                    for (uint256 j; j < ctx.set.inValues.length; ++j) {
                        if (ctx.set.inValues[j] == value) {
                            inSet = true;
                            break;
                        }
                    }
                    if (inSet) issues[issueCount++] = ValidationIssue.setReduction(groupIndex, constraintIndex, value);
                }

                if (ctx.set.notInCount < MAX_NOT_IN) ctx.set.notInValues[ctx.set.notInCount++] = value;
            }
            issueCount = _checkSetEmpty(ctx, groupIndex, constraintIndex, issues, issueCount);
        } else {
            if (ctx.numeric.hasEq) {
                bool found = false;
                for (uint256 i; i < values.length; ++i) {
                    if (values[i] == ctx.numeric.eq) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    // forgefmt: disable-next-item
                    issues[issueCount++] = ValidationIssue.setExcludesEquality(
                        groupIndex, constraintIndex, ctx.numeric.eq
                    );
                }
            }

            if (ctx.set.hasIn) {
                // Multiple isIn() on the same path narrow the allowed set to their intersection.
                // Allocate worst-case, fill matching elements, then trim via assembly.
                uint256[] memory intersection = new uint256[](ctx.set.inValues.length);
                uint256 intersectionCount;
                for (uint256 j; j < ctx.set.inValues.length; ++j) {
                    for (uint256 i; i < values.length; ++i) {
                        if (ctx.set.inValues[j] == values[i]) {
                            intersection[intersectionCount++] = ctx.set.inValues[j];
                            break;
                        }
                    }
                }
                // Trim the over-allocated array to its actual length.
                assembly ("memory-safe") {
                    mstore(intersection, intersectionCount)
                }

                if (intersectionCount == 0) {
                    issues[issueCount++] = ValidationIssue.emptySetIntersection(groupIndex, constraintIndex);
                } else if (intersectionCount < values.length || intersectionCount < ctx.set.inValues.length) {
                    issues[issueCount++] = ValidationIssue.setRedundancy(groupIndex, constraintIndex, intersectionCount);
                }
                ctx.set.inValues = intersection;
            } else {
                ctx.set.hasIn = true;
                ctx.set.inValues = values;
            }

            issueCount = _checkSetEmpty(ctx, groupIndex, constraintIndex, issues, issueCount);
        }
        return issueCount;
    }

    /// @dev Checks if the isIn() set has been fully excluded by neq/notIn values.
    function _checkSetEmpty(
        ConstraintContext memory ctx,
        uint32 groupIndex,
        uint32 constraintIndex,
        Issue[] memory issues,
        uint256 issueCount
    )
        private
        pure
        returns (uint256)
    {
        if (!ctx.set.hasIn) return issueCount;

        // Count isIn members not excluded by neq (holes) or notIn values.
        // Both sources exclude independently, so holes are checked first as a fast path.
        uint256 possibleCount = 0;
        uint256 inCount = ctx.set.inValues.length;
        for (uint256 i; i < inCount; ++i) {
            uint256 value = ctx.set.inValues[i];
            bool forbidden = false;
            for (uint8 k; k < ctx.numeric.holeCount; ++k) {
                if (ctx.numeric.holes[k] == value) {
                    forbidden = true;
                    break;
                }
            }
            if (!forbidden) {
                for (uint8 k; k < ctx.set.notInCount; ++k) {
                    if (ctx.set.notInValues[k] == value) {
                        forbidden = true;
                        break;
                    }
                }
            }
            if (!forbidden) possibleCount++;
        }

        // Zero survivors is a contradiction (error); partial exclusion is a warning.
        if (possibleCount == 0) {
            issues[issueCount++] = ValidationIssue.setFullyExcluded(groupIndex, constraintIndex);
        } else if (possibleCount < inCount) {
            // forgefmt: disable-next-item
            issues[issueCount++] = ValidationIssue.setPartiallyExcluded(
                groupIndex, constraintIndex, inCount - possibleCount
            );
        }
        return issueCount;
    }

    /// @dev Unpacks an IN operator's payload into an array of uint256 values.
    function _unpackSet(bytes memory op) private pure returns (uint256[] memory values) {
        uint256 dataLength = op.length - 1;
        uint256 count = dataLength / 32;
        values = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            uint256 value;
            assembly ("memory-safe") {
                value := mload(add(add(op, 33), mul(i, 32)))
            }
            values[i] = value;
        }
    }

    /// @dev Returns true if the array is strictly ascending (sorted, no duplicates).
    function _isStrictlyAscending(uint256[] memory values) private pure returns (bool) {
        for (uint256 i = 1; i < values.length; ++i) {
            if (values[i] <= values[i - 1]) return false;
        }
        return true;
    }

    /// @dev Updates the bitmask domain with a new operator and detects contradictions/redundancies.
    function _updateBitmask(
        ConstraintContext memory ctx,
        uint8 base,
        bool isNegated,
        uint256 mask,
        uint32 groupIndex,
        uint32 constraintIndex,
        Issue[] memory issues,
        uint256 issueCount
    )
        private
        pure
        returns (uint256)
    {
        if (isNegated) return issueCount;

        // forgefmt: disable-next-item
        if (base == OpCode.BITMASK_ALL) {
            if ((ctx.bitmask.mustBeZero & mask) != 0) {
                issues[issueCount++] = ValidationIssue.bitmaskContradiction(
                    groupIndex, constraintIndex, mask, ctx.bitmask.mustBeZero
                );
            }
            if ((ctx.bitmask.mustBeOne & mask) == mask) {
                issues[issueCount++] = ValidationIssue.redundantBitmask(
                    groupIndex, constraintIndex, mask, ctx.bitmask.mustBeOne
                );
            }
            ctx.bitmask.mustBeOne |= mask;
        } else if (base == OpCode.BITMASK_NONE) {
            if ((ctx.bitmask.mustBeOne & mask) != 0) {
                issues[issueCount++] = ValidationIssue.bitmaskContradiction(
                    groupIndex, constraintIndex, mask, ctx.bitmask.mustBeOne
                );
            }
            if ((ctx.bitmask.mustBeZero & mask) == mask) {
                issues[issueCount++] = ValidationIssue.redundantBitmask(
                    groupIndex, constraintIndex, mask, ctx.bitmask.mustBeZero
                );
            }
            ctx.bitmask.mustBeZero |= mask;
        } else if (base == OpCode.BITMASK_ANY) {
            if (mask != 0 && (ctx.bitmask.mustBeZero & mask) == mask) {
                issues[issueCount++] = ValidationIssue.bitmaskAnyImpossible(
                    groupIndex, constraintIndex, mask, ctx.bitmask.mustBeZero
                );
            }
            if ((ctx.bitmask.mustBeOne & mask) != 0) {
                issues[issueCount++] = ValidationIssue.redundantBitmask(
                    groupIndex, constraintIndex, mask, ctx.bitmask.mustBeOne
                );
            }
        }
        return issueCount;
    }

    /// @dev Checks for duplicate operators in a constraint.
    function _checkDuplicates(
        Issue[] memory issues,
        uint256 issueCount,
        bytes[] memory operators,
        uint32 groupIndex,
        uint32 constraintIndex
    )
        private
        pure
        returns (uint256)
    {
        uint256 operatorCount = operators.length;
        for (uint256 i; i < operatorCount; ++i) {
            for (uint256 j = i + 1; j < operatorCount; ++j) {
                if (LibBytes.eq(operators[i], operators[j])) {
                    issues[issueCount++] = ValidationIssue.duplicateConstraint(groupIndex, constraintIndex);
                    return issueCount;
                }
            }
        }
        return issueCount;
    }

    /// @dev Returns true if a calldata constraint's path contains the existential quantifier.
    function _hasAnyQuantifier(Constraint memory constraint) private pure returns (bool) {
        if (constraint.scope != PF.SCOPE_CALLDATA) return false;
        uint256 depth = constraint.path.length / 2;
        for (uint256 i; i < depth; ++i) {
            if (Path.atUnchecked(constraint.path, i) == Path.ANY) return true;
        }
        return false;
    }

    /// @dev Counts total operators across all constraints in the policy data.
    function _countOperators(PolicyData memory data) private pure returns (uint256 count) {
        uint256 groupCount = data.groups.length;
        for (uint256 i; i < groupCount; ++i) {
            Constraint[] memory constraints = data.groups[i];
            uint256 constraintCount = constraints.length;
            for (uint256 j; j < constraintCount; ++j) {
                count += constraints[j].operators.length;
            }
        }
        // Each operator can trigger multiple issues (contradiction, redundancy, vacuity, negation-
        // under-any), plus cross-constraint issues, decompositions (e.g., BETWEEN -> GTE + LTE),
        // per-path compatibility warnings, per-constraint fusible-range warnings (bounded by the
        // operator count), and empty groups.
        count = count * 6 + 20 + data.groups.length;
    }

    /// @dev Initializes a constraint context with domain limits for the given type.
    function _initContext(
        uint8 scope,
        bytes memory path,
        Descriptor.TypeInfo memory typeInfo
    )
        private
        pure
        returns (ConstraintContext memory ctx)
    {
        ctx.scope = scope;
        ctx.path = path;
        ctx.typeInfo = typeInfo;

        ctx.numeric.isSigned = TypeRule.isSigned(typeInfo.code);
        (ctx.numeric.min, ctx.numeric.max) = TypeRule.getDomainLimits(typeInfo.code);

        ctx.length.min = 0;
        ctx.length.max = type(uint32).max;
    }

    /*/////////////////////////////////////////////////////////////////////////
                              PAYLOAD READING HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Reads a single uint256 value from an operator's payload.
    function _readValue(bytes memory op) private pure returns (uint256 value) {
        assembly {
            value := mload(add(op, 33))
        }
    }

    /// @dev Reads a pair of uint256 values from an operator's payload (for BETWEEN operators).
    function _readPair(bytes memory op) private pure returns (uint256 low, uint256 high) {
        assembly {
            low := mload(add(op, 33))
            high := mload(add(op, 65))
        }
    }

    /// @dev Scans the operator's 32-byte payload words for one that deviates from the
    /// canonical encoding of the declared type. Trailing partial words are not scanned.
    function _findNonCanonicalWord(
        bytes memory op,
        uint8 typeCode
    )
        private
        pure
        returns (bool nonCanonical, bytes32 word, bytes32 canonical)
    {
        for (uint256 offset = 1; offset + 32 <= op.length; offset += 32) {
            bytes32 candidate = LibBytes.load(op, offset);
            bytes32 canonicalized = TypeRule.canonicalize(candidate, typeCode);
            if (canonicalized != candidate) return (true, candidate, canonicalized);
        }
    }

    /*/////////////////////////////////////////////////////////////////////////
                           OPCODE NORMALIZATION HELPERS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Converts a LENGTH_* opcode to its core comparison equivalent.
    function _normalizeLengthOp(uint8 base) private pure returns (uint8) {
        if (base == OpCode.LENGTH_EQ) return OpCode.EQ;
        if (base == OpCode.LENGTH_GT) return OpCode.GT;
        if (base == OpCode.LENGTH_LT) return OpCode.LT;
        if (base == OpCode.LENGTH_GTE) return OpCode.GTE;
        if (base == OpCode.LENGTH_LTE) return OpCode.LTE;
        return base;
    }

    /// @dev Returns the positive form of a negated bound opcode: !gt(v) -> lte(v), etc.
    function _negateBoundOp(uint8 base) private pure returns (uint8) {
        if (base == OpCode.GT) return OpCode.LTE;
        if (base == OpCode.GTE) return OpCode.LT;
        if (base == OpCode.LT) return OpCode.GTE;
        if (base == OpCode.LTE) return OpCode.GT;
        return base;
    }

    /*/////////////////////////////////////////////////////////////////////////
                            SIGNED-AWARE COMPARISONS
    /////////////////////////////////////////////////////////////////////////*/

    /// @dev Signed-aware greater-than comparison.
    function _isGt(uint256 a, uint256 b, bool isSigned) private pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast) intentional uint256->int256 reinterpret.
        return isSigned ? int256(a) > int256(b) : a > b;
    }

    /// @dev Signed-aware greater-than-or-equal comparison.
    function _isGte(uint256 a, uint256 b, bool isSigned) private pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast) intentional uint256->int256 reinterpret.
        return isSigned ? int256(a) >= int256(b) : a >= b;
    }

    /// @dev Signed-aware less-than comparison.
    function _isLt(uint256 a, uint256 b, bool isSigned) private pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast) intentional uint256->int256 reinterpret.
        return isSigned ? int256(a) < int256(b) : a < b;
    }

    /// @dev Signed-aware less-than-or-equal comparison.
    function _isLte(uint256 a, uint256 b, bool isSigned) private pure returns (bool) {
        // forge-lint: disable-next-line(unsafe-typecast) intentional uint256->int256 reinterpret.
        return isSigned ? int256(a) <= int256(b) : a <= b;
    }
}
