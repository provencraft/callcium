export { decodePolicy, decodeDescriptor, parsePathSteps } from "./decoder";
export { check, enforce } from "./enforcer";
export { toAddress, hexToBytes, bytesToHex } from "./hex";

export type {
  Hex,
  Address,
  Span,
  Field,
  DecodedPolicy,
  DecodedGroup,
  DecodedRule,
  DecodedParam,
  DecodedDescriptor,
  EnforceResult,
  Violation,
  ViolationCode,
  Context,
} from "./types";

export { CallciumError, PolicyViolationError } from "./errors";
export type { CallciumErrorCode } from "./errors";

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
