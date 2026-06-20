import type { Span } from "@callcium/sdk";
import { cn } from "@/lib/utils";

/**
 * Byte-by-byte hex renderer with span highlighting.
 *
 * Bytes belonging to the active span glow; bytes mapped to any span read at full
 * contrast; unmapped framing bytes recede. Hover resolves the owning span via an
 * event-delegated `data-idx`; an optional `onSelect` pins a span on click (tap).
 */
export function HexDump({
  hex,
  byteToSpan,
  active,
  onHover,
  onSelect,
}: {
  hex: string;
  byteToSpan: (Span | null)[];
  active: Span | null;
  onHover: (span: Span | null) => void;
  onSelect?: (span: Span | null) => void;
}) {
  const cleanHex = hex.startsWith("0x") ? hex.slice(2) : hex;
  const totalBytes = cleanHex.length / 2;

  const spanAt = (target: EventTarget): Span | null => {
    const idx = Number((target as HTMLElement).dataset.idx);
    return Number.isNaN(idx) ? null : (byteToSpan[idx] ?? null);
  };

  return (
    // oxlint-disable-next-line jsx-a11y/no-static-element-interactions -- hex dump uses event delegation for hover.
    <div
      className="flex flex-wrap gap-x-0.5 gap-y-0.5 font-mono text-xs leading-relaxed"
      onMouseMove={(e) => {
        const span = spanAt(e.target);
        if (span) onHover(span);
      }}
      onMouseLeave={() => onHover(null)}
      onClick={onSelect ? (e) => onSelect(spanAt(e.target)) : undefined}
    >
      {Array.from({ length: totalBytes }, (_, byteIndex) => {
        const byteHex = cleanHex.slice(byteIndex * 2, byteIndex * 2 + 2);
        const isHighlighted = active && byteIndex >= active.start && byteIndex < active.end;
        const isCovered = byteToSpan[byteIndex] !== null;

        return (
          <span
            key={byteIndex}
            data-idx={byteIndex}
            className={cn(
              "rounded-sm px-0.5 cursor-default",
              isHighlighted
                ? "bg-fd-info text-fd-info-foreground ring-1 ring-fd-info-foreground/30"
                : isCovered
                  ? "text-fd-foreground"
                  : "text-fd-muted-foreground/50",
            )}
          >
            {byteHex}
          </span>
        );
      })}
    </div>
  );
}
