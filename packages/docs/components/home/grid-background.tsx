"use client";

import { useTheme } from "next-themes";
import { FlickeringGrid } from "@/components/ui/flickering-grid";

/** Theme-aware flickering grid texture: signal red in light, amber in dark, masked to fade at the edges. */
export function GridBackground({ maxOpacity = 0.2 }: { maxOpacity?: number }) {
  const { resolvedTheme } = useTheme();

  return (
    <FlickeringGrid
      aria-hidden="true"
      className="absolute inset-0 [mask-image:radial-gradient(ellipse_at_50%_50%,white,transparent_80%)]"
      color={resolvedTheme === "dark" ? "#FFC857" : "#DB3A34"}
      maxOpacity={maxOpacity}
      flickerChance={0.2}
      squareSize={2}
      gridGap={6}
    />
  );
}
