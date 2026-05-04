///////////////////////////////////////////////////////////////////////////
// Builder pipeline
///////////////////////////////////////////////////////////////////////////

export { PolicyBuilder } from "./policy-builder";
export { PolicyCoder, parsePathSteps } from "./policy-coder";
export { isOpAllowed, PolicyValidator } from "./policy-validator";
export { arg, msgSender, msgValue, blockTimestamp, blockNumber, chainId, txOrigin } from "./constraint";
export type { ConstraintBuilder, ScalarValue } from "./constraint";

///////////////////////////////////////////////////////////////////////////
// Enforcement
///////////////////////////////////////////////////////////////////////////

export { PolicyEnforcer } from "./policy-enforcer";

///////////////////////////////////////////////////////////////////////////
// Utilities
///////////////////////////////////////////////////////////////////////////

export { toAddress, hexToBytes, bytesToHex } from "./bytes";
export { Descriptor } from "./descriptor";
export { DescriptorCoder } from "./descriptor-coder";
export type { TypeInfo } from "./descriptor";

///////////////////////////////////////////////////////////////////////////
// Constants
///////////////////////////////////////////////////////////////////////////

export {
  Op,
  TypeCode,
  Quantifier,
  Scope,
  ContextProperty,
  Limits,
  lookupOp,
  lookupScope,
  lookupContextProperty,
  lookupQuantifier,
  lookupTypeCode,
  isQuantifier,
} from "./constants";
export { isLengthOp } from "./operators";
export type {
  Operands,
  OpInfo,
  ScopeInfo,
  ContextPropertyInfo,
  QuantifierInfo,
  TypeCodeInfo,
  TypeClassInfo,
  TypeClass,
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
  Constraint,
  DecodedPolicy,
  DecodedGroup,
  DecodedRule,
  DecodedParam,
  Issue,
  IssueSeverity,
  IssueCategory,
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
  QuantifierLimitExceededViolation,
  QuantifierEmptyArrayViolation,
} from "./types";

///////////////////////////////////////////////////////////////////////////
// Errors
///////////////////////////////////////////////////////////////////////////

export { CallciumError, PolicyViolationError } from "./errors";
export type { CallciumErrorCode } from "./errors";
