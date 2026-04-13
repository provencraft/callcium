import { CallciumError } from "@callcium/sdk";

/** Format a caught error into a user-facing message. */
export function formatError(error: unknown): string {
  if (error instanceof CallciumError) return `${error.code}: ${error.message}`;
  if (error instanceof Error) return error.message;
  return "Unknown error.";
}
