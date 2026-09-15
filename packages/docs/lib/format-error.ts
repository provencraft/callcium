import { CallciumError } from "@callcium/sdk";

/** Format a caught error into a user-facing message. */
export function formatError(error: unknown): string {
  if (error instanceof CallciumError) return `${error.code}: ${error.message}`;
  // abitype and viem close `message` with a version footer naming the library and split its
  // parts across blank lines. Drop the footer and return the remainder as one line.
  if (error instanceof Error) return error.message.replace(/\n*Version: \S+$/, "").replace(/\n+/g, " ");
  return "Unknown error.";
}
