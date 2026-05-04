"use client";

import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "fumadocs-ui/components/ui/collapsible";
import { ChevronDown, ArrowRight, ShieldCheck, ShieldX, ShieldQuestion } from "lucide-react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import type { Context, Hex } from "@callcium/sdk";
import { ErrorBox } from "@/components/ui/error-box";
import { MonoInput } from "@/components/ui/mono-input";
import { MonoTextarea } from "@/components/ui/mono-textarea";
import { formatViolation } from "@/lib/format-violation";
import { useDebounce } from "@/lib/use-debounce";
import { cn } from "@/lib/utils";
import { checkPolicy, type EnforceOutput } from "@/tools/policy-enforcer";

function tryParseBigInt(value: string): bigint | undefined {
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  try {
    return BigInt(trimmed);
  } catch {
    return undefined;
  }
}

///////////////////////////////////////////////////////////////////////////
// Main component
///////////////////////////////////////////////////////////////////////////

export function Enforcer() {
  const searchParams = useSearchParams();
  const [policyInput, setPolicyInput] = useState("");
  const [calldataInput, setCalldataInput] = useState("");
  const [contextOpen, setContextOpen] = useState(false);
  const [ctxMsgSender, setCtxMsgSender] = useState("");
  const [ctxMsgValue, setCtxMsgValue] = useState("");
  const [ctxBlockTimestamp, setCtxBlockTimestamp] = useState("");
  const [ctxBlockNumber, setCtxBlockNumber] = useState("");
  const [ctxChainId, setCtxChainId] = useState("");
  const [ctxTxOrigin, setCtxTxOrigin] = useState("");

  useEffect(() => {
    const policyHex = searchParams.get("policy");
    if (policyHex) setPolicyInput(policyHex);
  }, [searchParams]);

  const debouncedPolicy = useDebounce(policyInput, 300);
  const debouncedCalldata = useDebounce(calldataInput, 300);

  const context = useMemo((): Context | undefined => {
    const ctx: Context = {};
    if (ctxMsgSender.trim()) ctx.msgSender = ctxMsgSender.trim() as `0x${string}`;
    const msgValue = tryParseBigInt(ctxMsgValue);
    if (msgValue !== undefined) ctx.msgValue = msgValue;
    const blockTs = tryParseBigInt(ctxBlockTimestamp);
    if (blockTs !== undefined) ctx.blockTimestamp = blockTs;
    const blockNum = tryParseBigInt(ctxBlockNumber);
    if (blockNum !== undefined) ctx.blockNumber = blockNum;
    const chain = tryParseBigInt(ctxChainId);
    if (chain !== undefined) ctx.chainId = chain;
    if (ctxTxOrigin.trim()) ctx.txOrigin = ctxTxOrigin.trim() as `0x${string}`;
    return Object.keys(ctx).length > 0 ? ctx : undefined;
  }, [ctxMsgSender, ctxMsgValue, ctxBlockTimestamp, ctxBlockNumber, ctxChainId, ctxTxOrigin]);

  const result = useMemo((): EnforceOutput | null => {
    const policy = debouncedPolicy.trim();
    const calldata = debouncedCalldata.trim();
    if (!policy || !calldata) return null;
    return checkPolicy(policy as Hex, calldata as Hex, context);
  }, [debouncedPolicy, debouncedCalldata, context]);

  return (
    <div className="space-y-4">
      {/* Policy input */}
      <div>
        <div className="mb-1.5 flex items-center justify-between">
          <label htmlFor="enforcer-policy-hex" className="text-sm font-medium text-fd-foreground">
            Policy Blob
          </label>
          {policyInput.trim() && (
            <Link
              href={`/policy-inspector?policy=${encodeURIComponent(policyInput.trim())}`}
              className="text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors"
            >
              Inspector <ArrowRight className="inline size-3" />
            </Link>
          )}
        </div>
        <MonoTextarea
          id="enforcer-policy-hex"
          rows={3}
          placeholder="0x01095ea7b3..."
          value={policyInput}
          onChange={(e) => setPolicyInput(e.target.value)}
        />
      </div>

      {/* Calldata input */}
      <div>
        <label htmlFor="enforcer-calldata-hex" className="mb-1.5 block text-sm font-medium text-fd-foreground">
          Calldata
        </label>
        <MonoTextarea
          id="enforcer-calldata-hex"
          rows={3}
          placeholder="0x095ea7b3..."
          value={calldataInput}
          onChange={(e) => setCalldataInput(e.target.value)}
        />
      </div>

      {/* Context (collapsible) */}
      <Collapsible open={contextOpen} onOpenChange={setContextOpen}>
        <CollapsibleTrigger className="flex items-center gap-1.5 text-sm text-fd-muted-foreground transition-colors hover:text-fd-foreground">
          <ChevronDown className={cn("size-4 transition-transform", contextOpen && "rotate-180")} />
          Context (optional)
        </CollapsibleTrigger>
        <CollapsibleContent>
          <div className="mt-2 grid gap-3 sm:grid-cols-2">
            <ContextField label="msg.sender" placeholder="0x..." value={ctxMsgSender} onChange={setCtxMsgSender} />
            <ContextField label="msg.value" placeholder="wei amount" value={ctxMsgValue} onChange={setCtxMsgValue} />
            <ContextField
              label="block.timestamp"
              placeholder="unix timestamp"
              value={ctxBlockTimestamp}
              onChange={setCtxBlockTimestamp}
              action={{
                label: "Now",
                onClick: () => setCtxBlockTimestamp(String(Math.floor(Date.now() / 1000))),
              }}
            />
            <ContextField
              label="block.number"
              placeholder="block number"
              value={ctxBlockNumber}
              onChange={setCtxBlockNumber}
            />
            <ContextField label="chain.id" placeholder="chain ID" value={ctxChainId} onChange={setCtxChainId} />
            <ContextField label="tx.origin" placeholder="0x..." value={ctxTxOrigin} onChange={setCtxTxOrigin} />
          </div>
        </CollapsibleContent>
      </Collapsible>

      {/* Result */}
      {result && <ResultDisplay result={result} />}
    </div>
  );
}

///////////////////////////////////////////////////////////////////////////
// Context field
///////////////////////////////////////////////////////////////////////////

function ContextField({
  label,
  placeholder,
  value,
  onChange,
  action,
}: {
  label: string;
  placeholder: string;
  value: string;
  onChange: (v: string) => void;
  action?: { label: string; onClick: () => void };
}) {
  return (
    <div>
      <div className="mb-1 flex items-center justify-between">
        <label className="text-xs font-medium text-fd-muted-foreground">{label}</label>
        {action && (
          <button
            type="button"
            className="text-xs text-fd-muted-foreground hover:text-fd-foreground transition-colors"
            onClick={action.onClick}
          >
            {action.label}
          </button>
        )}
      </div>
      <MonoInput placeholder={placeholder} value={value} onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}

///////////////////////////////////////////////////////////////////////////
// Result display
///////////////////////////////////////////////////////////////////////////

const STATUS_CONFIG = {
  pass: {
    icon: ShieldCheck,
    label: "Pass",
    className: "border-green-500/30 bg-green-500/10 text-green-700 dark:text-green-300",
    iconClass: "text-green-600 dark:text-green-400",
    divider: "divide-green-500/20",
  },
  fail: {
    icon: ShieldX,
    label: "Fail",
    className: "border-red-500/30 bg-red-500/10 text-red-700 dark:text-red-300",
    iconClass: "text-red-600 dark:text-red-400",
    divider: "divide-red-500/20",
  },
  inconclusive: {
    icon: ShieldQuestion,
    label: "Inconclusive",
    className: "border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300",
    iconClass: "text-amber-600 dark:text-amber-400",
    divider: "divide-amber-500/20",
  },
} as const;

function ResultDisplay({ result }: { result: EnforceOutput }) {
  if (result.status === "error") {
    return <ErrorBox>{result.errorMessage}</ErrorBox>;
  }

  const config = STATUS_CONFIG[result.status];
  const Icon = config.icon;
  const items = result.status === "inconclusive" ? result.skipped : result.violations;
  const isMultiGroup = items.length > 1 && items.every((v) => "group" in v);

  if (items.length <= 1) {
    return (
      <div className={cn("flex items-center gap-2 rounded-lg border px-4 py-3 text-sm", config.className)}>
        <Icon className={cn("size-5 shrink-0", config.iconClass)} />
        <span className="font-semibold">{config.label}</span>
        {result.matchedGroup !== undefined && <span>Matched group {result.matchedGroup + 1}</span>}
        {items[0] && <span>{formatViolation(items[0], result.params)}</span>}
      </div>
    );
  }

  return (
    <div className={cn("rounded-lg border px-4 py-3 text-sm", config.className)}>
      <div className="flex items-center gap-2">
        <Icon className={cn("size-5", config.iconClass)} />
        <span className="font-semibold">{config.label}</span>
      </div>
      <div className={cn("mt-2 divide-y", config.divider)}>
        {items.map((v, i) => (
          // oxlint-disable-next-line react/no-array-index-key
          <div key={i} className="py-1.5">
            {isMultiGroup && "group" in v && <span className="mr-2 font-semibold">Group {v.group + 1}</span>}
            <span>{formatViolation(v, result.params)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
