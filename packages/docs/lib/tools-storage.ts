import { addConstraint, addGroup, createSession, type BuilderSession, type ConstraintInput } from "./policy-builder";

///////////////////////////////////////////////////////////////////////////
// Session storage
///////////////////////////////////////////////////////////////////////////

const KEY_PREFIX = "tools:";
const BIGINT_TAG = "$bigint";

/** Read a JSON value from sessionStorage, or `fallback` when it is absent or storage is unavailable. */
export function loadState<T>(key: string, fallback: T): T {
  try {
    const raw = sessionStorage.getItem(KEY_PREFIX + key);
    if (raw === null) return fallback;
    return JSON.parse(raw, (_, value) => (value?.[BIGINT_TAG] !== undefined ? BigInt(value[BIGINT_TAG]) : value));
  } catch {
    return fallback;
  }
}

/** Write a JSON value to sessionStorage, with each bigint as a tagged string. */
export function saveState(key: string, value: unknown): void {
  try {
    sessionStorage.setItem(
      KEY_PREFIX + key,
      JSON.stringify(value, (_, item) => (typeof item === "bigint" ? { [BIGINT_TAG]: item.toString() } : item)),
    );
  } catch {
    // Without storage, such as in a private window that blocks it, the tools keep their state in memory only.
  }
}

/** Remove every sessionStorage entry under the tools key prefix. */
export function clearState(): void {
  try {
    const keys = Array.from({ length: sessionStorage.length }, (_, index) => sessionStorage.key(index));
    for (const key of keys) if (key?.startsWith(KEY_PREFIX)) sessionStorage.removeItem(key);
  } catch {
    // Without storage there is no saved state to remove.
  }
}

///////////////////////////////////////////////////////////////////////////
// Builder rules
///////////////////////////////////////////////////////////////////////////

/** Rebuild a session from its signature and the constraints of each group. */
export function fromRules(signature: string, selectorless: boolean, rules: ConstraintInput[][]): BuilderSession {
  let session = createSession(signature, { selectorless });
  rules.forEach((group, groupIndex) => {
    if (groupIndex > 0) session = addGroup(session);
    for (const constraint of group) session = addConstraint(session, groupIndex, constraint);
  });
  return session;
}
