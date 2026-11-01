"use client";

import { buttonVariants } from "fumadocs-ui/components/ui/button";
import { Popover, PopoverClose, PopoverContent, PopoverTrigger } from "fumadocs-ui/components/ui/popover";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "fumadocs-ui/components/ui/tabs";
import { useCopyButton } from "fumadocs-ui/utils/use-copy-button";
import { Check, ChevronDown, Copy, ScanSearch, ShieldCheck, Wrench } from "lucide-react";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { type Abi, isAddress, parseAbiItem } from "viem";
import { formatAbiItem } from "viem/utils";
import { abiPresets } from "./abi-presets";
import { Builder, humanizeError } from "./builder";
import { ChainPicker, chainName } from "./chain-picker";
import { Enforcer } from "./enforcer";
import { Inspector } from "./inspector";
import { ErrorBox } from "@/components/ui/error-box";
import { MonoInput } from "@/components/ui/mono-input";
import { MonoTextarea } from "@/components/ui/mono-textarea";
import { PillToggle } from "@/components/ui/pill-toggle";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { fetchAbi, lookup4byte, parseAbiFunctions } from "@/lib/abi";
import { formatError } from "@/lib/format-error";
import { createSession, type BuilderSession, type ConstraintInput } from "@/lib/policy-builder";
import { recoverSignature, tryDecode } from "@/lib/policy-inspector";
import { fromRules, loadState, saveState } from "@/lib/tools-storage";
import { useDebounce } from "@/lib/use-debounce";
import { cn } from "@/lib/utils";

type SavedWorkspace = {
  inputMode: "signature" | "abi";
  signature: string;
  isSelectorless: boolean;
  abiInput: string;
  rules: ConstraintInput[][];
  pastedHex: string;
};

const WORKSPACE_KEY = "workspace";

const CARD = "space-y-4 rounded-lg border border-fd-border bg-fd-card p-6";
const TOOL_HEADING = "flex items-center gap-2 font-mono text-sm font-semibold";

const TOOL_TABS = [
  { value: "builder", label: "Builder", Icon: Wrench },
  { value: "inspector", label: "Inspector", Icon: ScanSearch },
] as const;

///////////////////////////////////////////////////////////////////////////
// Main component
///////////////////////////////////////////////////////////////////////////

const subscribeNothing = () => () => {};

/** The tools workspace. It renders on the client only, because its first state comes from sessionStorage. */
export function Workspace() {
  const isClient = useSyncExternalStore(
    subscribeNothing,
    () => true,
    () => false,
  );
  return isClient ? <WorkspaceBody /> : null;
}

function WorkspaceBody() {
  const [saved] = useState(() =>
    loadState<SavedWorkspace>(WORKSPACE_KEY, {
      inputMode: "signature",
      signature: "",
      isSelectorless: false,
      abiInput: "",
      rules: [],
      pastedHex: "",
    }),
  );
  const [inputMode, setInputMode] = useState(saved.inputMode);
  const [signatureInput, setSignatureInput] = useState(saved.signature);
  const [isSelectorless, setIsSelectorless] = useState(saved.isSelectorless);
  const [abiInput, setAbiInput] = useState(saved.abiInput);
  const [chainId, setChainId] = useState(1);
  const [contractAddress, setContractAddress] = useState("");
  const [abiFetch, setAbiFetch] = useState<"idle" | "fetching" | "unverified" | "failed">("idle");
  // Only the latest fetch may write its result, so a preset picked during a fetch is not overwritten.
  const fetchRequest = useRef(0);
  const isContractAddress = isAddress(contractAddress);
  const [session, setSession] = useState<BuilderSession | null>(() =>
    saved.signature.trim() ? fromRules(saved.signature.trim(), saved.isSelectorless, saved.rules) : null,
  );
  const [pastedHex, setPastedHex] = useState(saved.pastedHex);
  const [lookup, setLookup] = useState<{ selector: string; name: string | null } | null>(null);

  const parsedAbi = useMemo(() => parseAbiFunctions(abiInput), [abiInput]);
  const abiFunctions = useMemo(() => (parsedAbi instanceof Error ? [] : parsedAbi), [parsedAbi]);
  const functionSignatures = useMemo(
    () => abiFunctions.map((abiFunction) => formatAbiItem(abiFunction, { includeName: true })),
    [abiFunctions],
  );
  // The select names the function in the Function input, which the ABI may not contain.
  const activeFunctionLabel = signatureInput.trim()
    ? isSelectorless
      ? `Selectorless (${signatureInput.trim()})`
      : signatureInput.trim()
    : "Select function";

  // The signature and its flag settle together, so a session never pairs one with the other's stale value.
  const signatureSource = useMemo(
    () => ({ signature: signatureInput, isSelectorless }),
    [signatureInput, isSelectorless],
  );
  const { signature: debouncedSignature, isSelectorless: debouncedSelectorless } = useDebounce(signatureSource, 300);

  // The session follows the debounced signature.
  const sessionKey = `${debouncedSignature}\n${debouncedSelectorless}`;
  const [syncedKey, setSyncedKey] = useState(sessionKey);
  if (sessionKey !== syncedKey) {
    setSyncedKey(sessionKey);
    const signature = debouncedSignature.trim();
    setSession(signature ? createSession(signature, { selectorless: debouncedSelectorless }) : null);
  }

  // The blob is the builder's output while it has rules, and the pasted input otherwise.
  const hasRules = session?.groups.some((group) => group.constraints.length > 0) ?? false;
  const debouncedPastedHex = useDebounce(pastedHex, 300);
  const policyHex = hasRules ? (session?.hex ?? "") : debouncedPastedHex;

  // The Function field names the parameters of a policy with a selector, for the Inspector and the Enforcer.
  const abi = useMemo((): Abi | undefined => {
    if (inputMode === "abi") return abiFunctions;
    const signature = debouncedSignature.trim();
    if (debouncedSelectorless || !signature) return undefined;
    try {
      return [parseAbiItem(`function ${signature}`)];
    } catch {
      return undefined;
    }
  }, [inputMode, abiFunctions, debouncedSignature, debouncedSelectorless]);

  const result = useMemo(() => tryDecode(policyHex, abi), [policyHex, abi]);

  // 4byte lookup when the policy has a selector without an ABI-resolved name.
  const lookupSelector =
    result?.ok && !result.explained.functionName && !result.explained.isSelectorless ? result.explained.selector : null;

  useEffect(() => {
    if (!lookupSelector) return;
    const controller = new AbortController();
    void lookup4byte(lookupSelector, controller.signal).then((name) => {
      if (!controller.signal.aborted) setLookup({ selector: lookupSelector, name });
    });
    return () => controller.abort();
  }, [lookupSelector]);

  const lookupSettled = lookup?.selector === lookupSelector;
  const lookedUpName = lookupSettled ? lookup.name : null;
  const lookingUp = lookupSelector !== null && !lookupSettled;
  const functionName = (result?.ok ? result.explained.functionName : null) ?? lookedUpName;

  // A pasted policy hands the builder its signature.
  const pastedSignature = result?.ok && !hasRules ? recoverSignature(result, abi, functionName) : null;

  useEffect(() => {
    saveState(WORKSPACE_KEY, {
      inputMode,
      // The rules belong to the debounced signature, so it is the one saved.
      signature: debouncedSignature,
      isSelectorless: debouncedSelectorless,
      abiInput,
      rules: session?.groups.map((group) => group.constraints) ?? [],
      pastedHex,
    } satisfies SavedWorkspace);
  }, [inputMode, debouncedSignature, debouncedSelectorless, abiInput, session, pastedHex]);

  // The Enforcer card mounts with the workspace, after the browser looked for the hash target.
  useEffect(() => {
    if (window.location.hash === "#enforce") document.getElementById("enforce")?.scrollIntoView();
  }, []);

  function handleChangeInputMode(mode: "signature" | "abi") {
    setInputMode(mode);
    // A signature that failed to parse is only reachable from the field that produced it.
    if (session?.error !== undefined) {
      setSignatureInput("");
      setSession(null);
    }
  }

  function handleSelectPreset(presetAbi: Abi) {
    handleChangeInputMode("abi");
    setAbiInput(JSON.stringify(presetAbi, null, 2));
    setContractAddress("");
    setAbiFetch("idle");
    fetchRequest.current++;
  }

  async function handleFetchAbi(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const request = ++fetchRequest.current;
    setAbiFetch("fetching");
    try {
      const fetched = await fetchAbi(chainId, contractAddress);
      if (request !== fetchRequest.current) return;
      if (fetched) setAbiInput(JSON.stringify(fetched, null, 2));
      setAbiFetch(fetched ? "idle" : "unverified");
    } catch {
      if (request === fetchRequest.current) setAbiFetch("failed");
    }
  }

  function handleClear() {
    setSignatureInput("");
    setIsSelectorless(false);
    setSession(null);
  }

  function handlePaste(event: React.ClipboardEvent<HTMLTextAreaElement>) {
    const pasted = event.clipboardData.getData("text");
    if (pasted.trim()) {
      setPastedHex(pasted);
      event.preventDefault();
    }
  }

  function handleStartFromSignature() {
    if (!pastedSignature || !result?.ok) return;
    setPastedHex("");
    setInputMode("signature");
    setSignatureInput(pastedSignature);
    setIsSelectorless(result.explained.isSelectorless);
  }

  const [copied, handleCopy] = useCopyButton(() => navigator.clipboard.writeText(session?.hex ?? ""));

  return (
    <div className="flex flex-col gap-12">
      <div className="space-y-4">
        {/* Function */}
        <div>
          <div className="mb-2 flex items-center justify-between">
            <PillToggle
              value={inputMode}
              options={[
                { value: "signature", label: "Signature" },
                { value: "abi", label: "ABI" },
              ]}
              onChange={handleChangeInputMode}
            />

            <Popover>
              <PopoverTrigger className="group flex items-center gap-1 text-sm text-fd-muted-foreground hover:text-fd-foreground transition-colors">
                ABI presets
                <ChevronDown className="size-3.5 transition-transform group-data-[state=open]:rotate-180" />
              </PopoverTrigger>
              <PopoverContent align="end" className="w-48 min-w-0 p-1">
                {abiPresets.map((preset) => (
                  <PopoverClose
                    key={preset.name}
                    className="w-full rounded-md px-3 py-1.5 text-left text-sm text-fd-muted-foreground transition-colors hover:bg-fd-accent hover:text-fd-accent-foreground"
                    onClick={() => handleSelectPreset(preset.abi)}
                  >
                    {preset.name}
                  </PopoverClose>
                ))}
              </PopoverContent>
            </Popover>
          </div>

          {inputMode === "signature" ? (
            <div className="space-y-2">
              <MonoTextarea
                id="signature-input"
                rows={3}
                className={cn(session?.error && "border-red-500/50")}
                placeholder={isSelectorless ? "address,uint256" : "transfer(address to, uint256 amount)"}
                value={signatureInput}
                onChange={(event) => setSignatureInput(event.target.value.replace(/\n/g, ""))}
              />
              <label className="flex items-center gap-1.5 text-sm text-fd-muted-foreground">
                <input
                  type="checkbox"
                  checked={isSelectorless}
                  onChange={(event) => setIsSelectorless(event.target.checked)}
                  className="size-3.5 accent-fd-primary"
                />
                Selectorless
              </label>
            </div>
          ) : (
            <div className="space-y-2">
              <form onSubmit={handleFetchAbi}>
                <fieldset
                  disabled={abiFetch === "fetching"}
                  className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-end"
                >
                  <div className="flex flex-col gap-1">
                    <label htmlFor="abi-chain" className="text-xs text-fd-muted-foreground">
                      chain
                    </label>
                    <ChainPicker
                      id="abi-chain"
                      value={chainId}
                      onChange={(id) => {
                        setChainId(id);
                        setAbiFetch("idle");
                      }}
                    />
                  </div>
                  <div className="flex min-w-0 flex-col gap-1 sm:flex-1">
                    <label htmlFor="abi-contract-address" className="text-xs text-fd-muted-foreground">
                      contract address
                    </label>
                    <MonoInput
                      id="abi-contract-address"
                      placeholder="0x…"
                      className={cn(contractAddress && !isContractAddress && "border-red-500/50")}
                      value={contractAddress}
                      onChange={(event) => {
                        setContractAddress(event.target.value.trim());
                        setAbiFetch("idle");
                      }}
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={!isContractAddress}
                    className={cn(buttonVariants({ variant: "outline" }), "h-9 shrink-0 px-3")}
                  >
                    {abiFetch === "fetching" ? "Fetching…" : "Fetch ABI"}
                  </button>
                </fieldset>
                <div aria-live="polite">
                  {abiFetch === "unverified" && (
                    <p className="mt-2 text-sm text-fd-muted-foreground">
                      Sourcify has no verified contract at this address on {chainName(chainId)}. Paste the ABI below.
                    </p>
                  )}
                  {abiFetch === "failed" && (
                    <ErrorBox className="mt-2">
                      The request to Sourcify failed. Fetch again, or paste the ABI below.
                    </ErrorBox>
                  )}
                </div>
              </form>

              <MonoTextarea
                rows={4}
                readOnly={abiFetch === "fetching"}
                placeholder='[{"type":"function","name":"approve","inputs":[...]}]'
                value={abiInput}
                onChange={(event) => setAbiInput(event.target.value)}
              />

              <Select
                value={!isSelectorless && functionSignatures.includes(signatureInput) ? signatureInput : ""}
                onValueChange={(signature) => {
                  setIsSelectorless(false);
                  setSignatureInput(signature);
                }}
                disabled={functionSignatures.length === 0}
              >
                <SelectTrigger
                  className={cn("w-full font-mono", signatureInput.trim() && "data-[placeholder]:text-fd-foreground")}
                >
                  <SelectValue placeholder={activeFunctionLabel} />
                </SelectTrigger>
                <SelectContent className="font-mono">
                  {functionSignatures.map((signature) => (
                    <SelectItem key={signature} value={signature}>
                      {signature}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>

              {parsedAbi instanceof Error ? (
                <ErrorBox>Invalid ABI: {formatError(parsedAbi)}</ErrorBox>
              ) : (
                abiInput.trim() && parsedAbi.length === 0 && <ErrorBox>No functions found in ABI.</ErrorBox>
              )}
            </div>
          )}

          {session?.error && <ErrorBox className="mt-1.5">{humanizeError(session.error)}</ErrorBox>}
        </div>

        {/* Policy Blob */}
        <div>
          <div className="mb-1.5 flex items-center gap-3">
            <label htmlFor="policy-hex" className="text-sm font-medium text-fd-foreground">
              Policy Blob
            </label>
            {hasRules && (
              <button
                type="button"
                className={buttonVariants({ variant: "outline", size: "sm" })}
                onClick={handleClear}
              >
                Clear
              </button>
            )}
          </div>
          {hasRules ? (
            <div className="relative">
              <MonoTextarea id="policy-hex" className="resize-none pr-9" rows={3} value={session?.hex ?? ""} readOnly />
              {session?.hex && (
                <button
                  type="button"
                  aria-label="Copy policy blob"
                  className="absolute top-2 right-3 rounded-md p-1 text-fd-muted-foreground hover:text-fd-foreground transition-colors"
                  onClick={handleCopy}
                >
                  {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
                </button>
              )}
            </div>
          ) : (
            <>
              <MonoTextarea
                id="policy-hex"
                className={cn(result && !result.ok && "border-red-500/50")}
                rows={3}
                placeholder="0x60095ea7b3..."
                value={pastedHex}
                onChange={(event) => setPastedHex(event.target.value)}
                onPaste={handlePaste}
              />
              {result && !result.ok && <ErrorBox className="mt-1.5">{result.error}</ErrorBox>}
            </>
          )}
        </div>
      </div>

      {/* Builder and Inspector */}
      <Tabs defaultValue="builder" className={CARD}>
        <TabsList className="flex items-center gap-8">
          {TOOL_TABS.map(({ value, label, Icon }) => (
            <TabsTrigger
              key={value}
              value={value}
              className={cn(
                TOOL_HEADING,
                "group text-fd-muted-foreground transition-colors hover:text-fd-foreground data-[state=active]:text-fd-foreground",
              )}
            >
              <Icon className="size-6 group-data-[state=active]:text-fd-primary" aria-hidden="true" />
              {label}
            </TabsTrigger>
          ))}
        </TabsList>
        <TabsContent value="builder" id="build" forceMount className="data-[state=inactive]:hidden">
          {pastedHex.trim() ? (
            <div className="space-y-3">
              <p className="text-sm text-fd-muted-foreground">Rules cannot be recovered from a policy blob.</p>
              <button
                type="button"
                className={buttonVariants({ variant: "outline", size: "sm" })}
                disabled={!pastedSignature}
                onClick={handleStartFromSignature}
              >
                Start from this signature
              </button>
              {result?.ok && !pastedSignature && !lookingUp && (
                <p className="text-xs text-fd-muted-foreground">Type the signature in Function.</p>
              )}
            </div>
          ) : session && !session.error ? (
            <Builder session={session} onChange={setSession} />
          ) : (
            <p className="text-sm text-fd-muted-foreground">Enter a function to add constraints.</p>
          )}
        </TabsContent>
        <TabsContent value="inspector" id="inspect" forceMount className="data-[state=inactive]:hidden">
          {result?.ok ? (
            <Inspector result={result} functionName={functionName} lookingUp={lookingUp} />
          ) : (
            <p className="text-sm text-fd-muted-foreground">Build or paste a policy to inspect it.</p>
          )}
        </TabsContent>
      </Tabs>

      {/* Enforcer */}
      <section id="enforce" aria-labelledby="enforcer-heading" className={CARD}>
        <h2 id="enforcer-heading" className={TOOL_HEADING}>
          <ShieldCheck className="size-6 text-fd-primary" aria-hidden="true" />
          Enforcer
        </h2>
        <Enforcer policyHex={result?.ok ? result.hex : null} abi={abi} />
      </section>
    </div>
  );
}
