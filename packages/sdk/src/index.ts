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
export { DescriptorBuilder } from "./descriptor-builder";
export type { TypeInfo } from "./descriptor";

///////////////////////////////////////////////////////////////////////////
// Constants
///////////////////////////////////////////////////////////////////////////

export {
  Op,
  TypeCode,
  Quantifier,
  PolicyFormat,
  DescriptorFormat,
  Scope,
  ContextProperty,
  Limits,
  lookupOp,
  lookupScope,
  lookupContextProperty,
  lookupQuantifier,
  lookupTypeCode,
} from "./constants";
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
  PolicyData,
  Constraint,
  Issue,
  IssueSeverity,
  IssueCategory,
  Context,
  EnforceResult,
  Violation,
  ViolationCode,
} from "./types";

///////////////////////////////////////////////////////////////////////////
// Errors
///////////////////////////////////////////////////////////////////////////

export { CallciumError, PolicyViolationError } from "./errors";
export type { CallciumErrorCode } from "./errors";
