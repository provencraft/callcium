"use client";

import { Command } from "cmdk";
import { Popover, PopoverContent, PopoverTrigger } from "fumadocs-ui/components/ui/popover";
import { Check, ChevronDown } from "lucide-react";
import { useState } from "react";
import { FIELD_TRIGGER } from "@/components/ui/select";
import chains from "@/lib/sourcify-chains.json";
import { cn } from "@/lib/utils";

const POPULAR_CHAIN_IDS = [1, 8453, 42161, 10, 137, 56, 100, 43114, 11155111, 84532] as const;

const popularChains = POPULAR_CHAIN_IDS.flatMap((chainId) => chains.find((chain) => chain.id === chainId) ?? []);
const otherChains = chains.filter((chain) => !popularChains.includes(chain));
const popularFirst = [...popularChains, ...otherChains];

/** The name of a chain in the synced Sourcify list, or its ID when the list does not contain it. */
export function chainName(chainId: number): string {
  return chains.find((chain) => chain.id === chainId)?.name ?? String(chainId);
}

/** Match every word of the search anywhere in an item's name and chain ID, and rank an exact chain ID first. */
function matchChain(value: string, search: string): number {
  const text = value.toLowerCase();
  const words = search.toLowerCase().split(/\s+/);
  if (!words.every((word) => text.includes(word))) return 0;
  // An item's value ends with its chain ID.
  return words.some((word) => text.endsWith(` ${word}`)) ? 2 : 1;
}

/** Searchable picker over the chains Sourcify verifies contracts on, popular chains first. */
export function ChainPicker({
  id,
  value,
  onChange,
}: {
  id: string;
  value: number;
  onChange: (chainId: number) => void;
}) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");

  function handleOpenChange(isOpen: boolean) {
    setOpen(isOpen);
    setSearch("");
  }

  function renderChain(chain: (typeof chains)[number]) {
    return (
      <Command.Item
        key={chain.id}
        value={`${chain.name} ${chain.id}`}
        onSelect={() => {
          onChange(chain.id);
          handleOpenChange(false);
        }}
        className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 data-[selected=true]:bg-fd-accent data-[selected=true]:text-fd-accent-foreground"
      >
        <Check className={cn("size-3.5 shrink-0", chain.id !== value && "invisible")} />
        <span className="flex-1 truncate">{chain.name}</span>
        <span className="font-mono text-xs text-fd-muted-foreground">{chain.id}</span>
      </Command.Item>
    );
  }

  return (
    <Popover open={open} onOpenChange={handleOpenChange}>
      <PopoverTrigger
        id={id}
        aria-label={`Chain: ${chainName(value)}`}
        className={cn(FIELD_TRIGGER, "w-full shrink-0 sm:w-56")}
      >
        <span className="truncate">{chainName(value)}</span>
        <ChevronDown className="size-3.5 shrink-0 text-fd-muted-foreground" />
      </PopoverTrigger>
      <PopoverContent align="start" className="w-(--radix-popover-trigger-width) p-0 sm:w-80">
        <Command label="Chains" filter={matchChain} className="text-base sm:text-sm">
          <Command.Input
            value={search}
            onValueChange={setSearch}
            placeholder="Search by name or chain ID"
            className="h-9 w-full border-b border-fd-border bg-transparent px-3 outline-none placeholder:text-fd-muted-foreground/50"
          />
          <Command.List className="max-h-72 overflow-y-auto p-1 [&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:pt-2 [&_[cmdk-group-heading]]:pb-1 [&_[cmdk-group-heading]]:text-xs [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:text-fd-muted-foreground">
            <Command.Empty className="px-2 py-6 text-center text-fd-muted-foreground">No chain matches.</Command.Empty>
            {/* cmdk ranks items within a group but never moves the groups, so a search shows one ranked list. */}
            {search ? (
              popularFirst.map(renderChain)
            ) : (
              <>
                <Command.Group heading="Popular">{popularChains.map(renderChain)}</Command.Group>
                <Command.Group heading="Other chains">{otherChains.map(renderChain)}</Command.Group>
              </>
            )}
          </Command.List>
        </Command>
      </PopoverContent>
    </Popover>
  );
}
