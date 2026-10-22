///////////////////////////////////////////////////////////////////////////
// Builder pipeline
///////////////////////////////////////////////////////////////////////////

export { PolicyBuilder } from "./policy-builder";
export { PolicyCoder } from "./policy-coder";
export { parsePathSteps, Quantifier } from "./path";
export { isOpAllowed, PolicyValidator } from "./policy-validator";
export {
  arg,
  msgSender,
  msgValue,
  blockTimestamp,
  blockNumber,
  chainId,
  txOrigin,
  baseFee,
  gasPrice,
} from "./constraint";
export type { ConstraintBuilder, ScalarValue } from "./constraint";

///////////////////////////////////////////////////////////////////////////
// Enforcement
///////////////////////////////////////////////////////////////////////////

export { PolicyEnforcer } from "./policy-enforcer";

///////////////////////////////////////////////////////////////////////////
// Utilities
///////////////////////////////////////////////////////////////////////////

export { hexToBytes, bytesToHex } from "./bytes";
export { DescriptorCoder } from "./descriptor-coder";

///////////////////////////////////////////////////////////////////////////
// Constants
///////////////////////////////////////////////////////////////////////////

export {
  Op,
  Source,
  TypeCode,
  Scope,
  LoopQuantifier,
  ContextProperty,
  lookupOp,
  lookupScope,
  lookupQuantifier,
  lookupContextProperty,
} from "./constants";
export { lookupTypeCode } from "./operators";
export type { TypeCodeInfo, TypeClassInfo, TypeClass } from "./operators";
export type {
  Operands,
  OpInfo,
  ScopeInfo,
  QuantifierInfo,
  ContextPropertyInfo,
  ComparisonCode,
  ScopeCode,
  QuantifierCode,
} from "./constants";

///////////////////////////////////////////////////////////////////////////
// Types
///////////////////////////////////////////////////////////////////////////

export type {
  Hex,
  Address,
  Span,
  Field,
  PolicyData,
  Rule,
  BodyRule,
  LoopRule,
  Constraint,
  DecodedPolicy,
  DecodedGroup,
  DecodedRule,
  DecodedTest,
  DecodedLoop,
  DecodedHint,
  DecodedFrameHint,
  DecodedHop,
  ArrayMeta,
  DecodedOperator,
  DecodedDescriptor,
  DecodedNode,
  Issue,
  IssueCode,
  IssueSeverity,
  IssueCategory,
  RuleLocation,
  Context,
  EnforceResult,
  Violation,
  ViolationCode,
  NavigationViolationCode,
  MissingSelectorViolation,
  SelectorMismatchViolation,
  MissingContextViolation,
  ValueMismatchViolation,
  CalldataNavigationViolation,
  NonCanonicalValueViolation,
  QuantifierLimitExceededViolation,
  QuantifierNoMatchViolation,
} from "./types";

///////////////////////////////////////////////////////////////////////////
// Errors
///////////////////////////////////////////////////////////////////////////

export { CallciumError, PolicyViolationError, ValidationError } from "./errors";
export type { CallciumErrorCode } from "./errors";
