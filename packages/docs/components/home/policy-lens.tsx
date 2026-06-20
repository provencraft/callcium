"use client";

import { useMemo, useState } from "react";
import type { Span } from "@callcium/sdk";
import type { ReactNode } from "react";
import type { LensData } from "./policy-lens-data";
import { HexDump } from "@/components/ui/hex-dump";
import { cn } from "@/lib/utils";

const sameSpan = (a: Span | null, b: Span | null) => !!a && !!b && a.start === b.start && a.end === b.end;

/** Shorten 20-byte addresses to `0x1234…5678`; leaves shorter values (uints, bools) intact. */
function shortenAddresses(value: string): string {
  return value.replace(/0x[0-9a-fA-F]{40}/g, (m) => `${m.slice(0, 6)}…${m.slice(-4)}`);
}

/**
 * Hero policy lens: the canonical blob beside the rules it decodes to. Hovering a
 * field (or its bytes) traces the link in both directions; tap pins it for touch.
 * Mirrors the Policy Inspector's color language so the two surfaces read as one.
 */
export function PolicyLens({ data }: { data: LensData }) {
  const [hovered, setHovered] = useState<Span | null>(null);
  const [pinned, setPinned] = useState<Span | null>(null);
  const active = hovered ?? pinned;

  const totalBytes = (data.hex.length - 2) / 2;
  const byteToSpan = useMemo(() => {
    const map: (Span | null)[] = Array.from<Span | null>({ length: totalBytes }).fill(null);
    const cover = (span: Span) => {
      for (let i = span.start; i < span.end && i < totalBytes; i++) map[i] = span;
    };
    cover(data.signatureSpan);
    for (const row of data.rows) cover(row.span);
    return map;
  }, [data, totalBytes]);

  const togglePin = (span: Span) => setPinned((current) => (sameSpan(current, span) ? null : span));

  return (
    <div>
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <span className="font-mono text-[0.7rem] text-fd-muted-foreground/50">a policy is just canonical bytes</span>
        <span className="font-mono text-[0.7rem] text-fd-muted-foreground/50">hover or tap a field</span>
      </div>

      <div className="overflow-hidden rounded-lg border border-fd-border bg-fd-card">
        <div className="border-b border-fd-border bg-fd-muted/30 px-4 py-3">
          <HexDump
            hex={data.hex}
            byteToSpan={byteToSpan}
            active={active}
            onHover={setHovered}
            onSelect={(span) => span && togglePin(span)}
          />
        </div>

        <div className="font-mono text-xs">
          <Row span={data.signatureSpan} active={active} onHover={setHovered} onToggle={togglePin}>
            <span className="min-w-0 truncate font-semibold text-fd-foreground group-[.is-active]:text-fd-info-foreground">
              {data.signature}
            </span>
            <span className="ml-auto shrink-0 text-fd-muted-foreground/60 group-[.is-active]:text-fd-info-foreground">
              {data.selector}
            </span>
          </Row>
          {data.rows.map((row) => (
            <Row key={row.span.start} span={row.span} active={active} onHover={setHovered} onToggle={togglePin}>
              <span className="shrink-0 text-fd-foreground group-[.is-active]:text-fd-info-foreground">{row.path}</span>
              <span className="shrink-0 text-fd-muted-foreground group-[.is-active]:text-fd-info-foreground">
                {row.operator}
              </span>
              <span className="min-w-0 flex-1 truncate text-fd-foreground group-[.is-active]:text-fd-info-foreground">
                {shortenAddresses(row.value)}
              </span>
              <span className="shrink-0 text-fd-muted-foreground group-[.is-active]:text-fd-info-foreground">
                : {row.type}
              </span>
            </Row>
          ))}
        </div>
      </div>
    </div>
  );
}

function Row({
  span,
  active,
  onHover,
  onToggle,
  children,
}: {
  span: Span;
  active: Span | null;
  onHover: (span: Span | null) => void;
  onToggle: (span: Span) => void;
  children: ReactNode;
}) {
  const isActive = sameSpan(active, span);

  return (
    <button
      type="button"
      aria-pressed={isActive}
      className={cn(
        "group flex w-full cursor-pointer items-baseline gap-2 border-b border-fd-border/30 px-4 py-2 text-left last:border-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-fd-ring",
        isActive && "is-active bg-fd-info",
      )}
      onMouseEnter={() => onHover(span)}
      onMouseLeave={() => onHover(null)}
      onFocus={() => onHover(span)}
      onBlur={() => onHover(null)}
      onClick={() => onToggle(span)}
    >
      {children}
    </button>
  );
}
