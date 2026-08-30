///////////////////////////////////////////////////////////////////////////
// Builder pipeline
///////////////////////////////////////////////////////////////////////////

export { PolicyBuilder } from "./policy-builder";
export { PolicyCoder } from "./policy-coder";
export { isQuantifier, lookupQuantifier, parsePathSteps, Quantifier } from "./path";
export type { QuantifierInfo } from "./path";
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
  PolicyFormat,
  Scope,
  ContextProperty,
  MAX_CONTEXT_PROPERTY_ID,
  lookupOp,
  lookupScope,
  lookupContextProperty,
} from "./constants";
export { isLengthOp, lookupTypeCode } from "./operators";
export type { TypeCodeInfo, TypeClassInfo, TypeClass } from "./operators";
export type { Operands, OpInfo, ScopeInfo, ContextPropertyInfo } from "./constants";

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
  IssueCode,
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
  NonCanonicalValueViolation,
  QuantifierLimitExceededViolation,
  QuantifierEmptyArrayViolation,
} from "./types";

///////////////////////////////////////////////////////////////////////////
// Errors
///////////////////////////////////////////////////////////////////////////

export { CallciumError, PolicyViolationError, ValidationError } from "./errors";
export type { CallciumErrorCode } from "./errors";
