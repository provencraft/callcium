"use client";

import { useMediaQuery } from "fumadocs-core/utils/use-media-query";
import { useTheme } from "fumadocs-ui/provider/base";
import { Pause, Play } from "lucide-react";
import { type CSSProperties, useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

/**
 * A muted loop of `public/motion/<name>.mp4` and its posters, started only when motion is allowed, with a pause control.
 * The light theme plays `<name>-light`, rendered from the same scenes.
 */
export function Film({ name, label, className }: { name: string; label: string; className?: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  // `null` until hydration, so the film starts only once motion is known to be allowed.
  const reduceMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
  // Below the `sm` breakpoint the film is hidden and its video never loads: its code is unreadable at that width.
  const wide = useMediaQuery("(min-width: 40rem)");
  const { resolvedTheme } = useTheme();
  // The server does not know the theme, so the file waits for hydration; the container background covers the gap.
  const file = reduceMotion === null ? undefined : resolvedTheme === "dark" ? name : `${name}-light`;

  useEffect(() => {
    // The browser can refuse autoplay; the play button stays available.
    if (reduceMotion === false && wide && file) videoRef.current?.play().catch(() => {});
  }, [reduceMotion, wide, file]);

  const toggle = () => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) video.play().catch(() => {});
    else video.pause();
  };

  return (
    <div
      // The theme class is on `<html>` before first paint, so the first frame matches the theme before hydration.
      style={
        {
          "--film-poster": `url(/motion/${name}-poster.webp)`,
          "--film-poster-light": `url(/motion/${name}-light-poster.webp)`,
        } as CSSProperties
      }
      className={cn(
        "relative hidden overflow-hidden rounded-lg border border-fd-border bg-cover bg-[image:var(--film-poster-light)] sm:block dark:bg-[image:var(--film-poster)]",
        className,
      )}
    >
      <video
        ref={videoRef}
        src={file && `/motion/${file}.mp4`}
        // First frame: playback starts without a cut. Without motion, a still from mid-film tells the story.
        poster={file && `/motion/${file}-poster${reduceMotion ? "-still" : ""}.webp`}
        width={1920}
        height={1080}
        muted
        loop
        playsInline
        preload={wide ? "metadata" : "none"}
        aria-label={label}
        className="block h-auto w-full"
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
      />
      <button
        type="button"
        onClick={toggle}
        aria-label={playing ? "Pause animation" : "Play animation"}
        className="absolute right-3 bottom-3 rounded-md border border-fd-border bg-fd-background/80 p-2 text-fd-muted-foreground transition-colors hover:text-fd-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-fd-ring"
      >
        {playing ? <Pause className="size-4" aria-hidden="true" /> : <Play className="size-4" aria-hidden="true" />}
      </button>
    </div>
  );
}
