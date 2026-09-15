"use client";

import { useCallback, useEffect, useMemo, useRef } from "react";
import type React from "react";
import { cn } from "@/lib/utils";

interface FlickeringGridProps extends React.HTMLAttributes<HTMLDivElement> {
  squareSize?: number;
  gridGap?: number;
  flickerChance?: number;
  color?: string;
  width?: number;
  height?: number;
  className?: string;
  maxOpacity?: number;
}

/** Upper bound on a frame's delta, so returning to a backgrounded tab rerolls a frame's worth of squares. */
const MAX_DELTA_SECONDS = 0.1;

export const FlickeringGrid: React.FC<FlickeringGridProps> = ({
  squareSize = 4,
  gridGap = 6,
  flickerChance = 0.3,
  color = "rgb(0, 0, 0)",
  width,
  height,
  className,
  maxOpacity = 0.3,
  ...props
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const memoizedColor = useMemo(() => {
    if (typeof window === "undefined") return "rgb(0, 0, 0)";
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1;
    const ctx = canvas.getContext("2d");
    if (!ctx) return "rgb(255, 0, 0)";
    ctx.fillStyle = color;
    ctx.fillRect(0, 0, 1, 1);
    const [r, g, b] = Array.from(ctx.getImageData(0, 0, 1, 1).data);
    return `rgb(${r}, ${g}, ${b})`;
  }, [color]);

  const setupCanvas = useCallback(
    (canvas: HTMLCanvasElement, canvasWidth: number, canvasHeight: number) => {
      const dpr = window.devicePixelRatio || 1;
      canvas.width = canvasWidth * dpr;
      canvas.height = canvasHeight * dpr;
      canvas.style.width = `${canvasWidth}px`;
      canvas.style.height = `${canvasHeight}px`;
      const cols = Math.floor(canvasWidth / (squareSize + gridGap));
      const rows = Math.floor(canvasHeight / (squareSize + gridGap));

      const squares = new Float32Array(cols * rows);
      for (let i = 0; i < squares.length; i++) {
        squares[i] = Math.random() * maxOpacity;
      }

      return { cols, rows, squares, dpr };
    },
    [squareSize, gridGap, maxOpacity],
  );

  /** Repaint one square at its stored opacity. The caller owns `fillStyle`; opacity rides on `globalAlpha`. */
  const drawSquare = useCallback(
    (ctx: CanvasRenderingContext2D, squares: Float32Array, rows: number, dpr: number, index: number) => {
      const pitch = (squareSize + gridGap) * dpr;
      const size = squareSize * dpr;
      const x = Math.floor(index / rows) * pitch;
      const y = (index % rows) * pitch;

      // clearRect antialiases a fractional edge, so it leaves the previous fill's fringe behind and
      // repeated repaints ratchet the square to opaque. Clearing on integer bounds that contain the
      // fringe keeps the fill's own fractional geometry; the gap holds the box off its neighbours.
      const left = Math.floor(x);
      const top = Math.floor(y);
      ctx.clearRect(left, top, Math.ceil(x + size) - left, Math.ceil(y + size) - top);

      ctx.globalAlpha = squares[index];
      ctx.fillRect(x, y, size, size);
    },
    [squareSize, gridGap],
  );

  const drawGrid = useCallback(
    (ctx: CanvasRenderingContext2D, squares: Float32Array, rows: number, dpr: number) => {
      ctx.fillStyle = memoizedColor;
      for (let i = 0; i < squares.length; i++) drawSquare(ctx, squares, rows, dpr, i);
    },
    [memoizedColor, drawSquare],
  );

  /**
   * Reroll the squares the frame's delta selects and repaint those in place. A frame rerolls a
   * fraction of a percent of the grid, so the canvas carries the rest over from the frame before.
   */
  const updateSquares = useCallback(
    (ctx: CanvasRenderingContext2D, squares: Float32Array, rows: number, dpr: number, deltaTime: number) => {
      const chance = flickerChance * deltaTime;
      ctx.fillStyle = memoizedColor;
      for (let i = 0; i < squares.length; i++) {
        if (Math.random() < chance) {
          squares[i] = Math.random() * maxOpacity;
          drawSquare(ctx, squares, rows, dpr, i);
        }
      }
    },
    [flickerChance, maxOpacity, memoizedColor, drawSquare],
  );

  useEffect(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animationFrameId: number;
    let isInView = false;
    let gridParams: ReturnType<typeof setupCanvas>;
    // A client dimension is never negative, so the first measurement always counts as a change.
    let lastWidth = -1;
    let lastHeight = -1;

    // Reseeding and repainting the whole grid costs a frame, so only a real size change earns one.
    const updateCanvasSize = () => {
      const newWidth = width || container.clientWidth;
      const newHeight = height || container.clientHeight;
      if (newWidth === lastWidth && newHeight === lastHeight) return;
      lastWidth = newWidth;
      lastHeight = newHeight;

      gridParams = setupCanvas(canvas, newWidth, newHeight);
      drawGrid(ctx, gridParams.squares, gridParams.rows, gridParams.dpr);
    };

    updateCanvasSize();

    let lastTime = 0;
    const animate = (time: number) => {
      const deltaTime = lastTime ? Math.min((time - lastTime) / 1000, MAX_DELTA_SECONDS) : 0;
      lastTime = time;

      updateSquares(ctx, gridParams.squares, gridParams.rows, gridParams.dpr, deltaTime);
      animationFrameId = requestAnimationFrame(animate);
    };

    const resizeObserver = new ResizeObserver(updateCanvasSize);
    resizeObserver.observe(container);

    const intersectionObserver = new IntersectionObserver(
      (entries) => {
        // A callback can carry several records for one target; the last one holds the current state.
        const entry = entries[entries.length - 1];
        if (entry.isIntersecting === isInView) return;
        isInView = entry.isIntersecting;
        if (isInView) {
          lastTime = 0;
          animationFrameId = requestAnimationFrame(animate);
        } else {
          cancelAnimationFrame(animationFrameId);
        }
      },
      { threshold: 0 },
    );

    intersectionObserver.observe(canvas);

    return () => {
      cancelAnimationFrame(animationFrameId);
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
    };
  }, [setupCanvas, updateSquares, drawGrid, width, height]);

  return (
    <div ref={containerRef} className={cn("h-full w-full", className)} {...props}>
      <canvas ref={canvasRef} className="pointer-events-none" />
    </div>
  );
};
