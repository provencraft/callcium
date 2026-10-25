"use client";

import { useMediaQuery } from "fumadocs-core/utils/use-media-query";
import { Pause, Play } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

/** A muted loop of `public/motion/<name>.mp4` and its posters, started only when motion is allowed, with a pause control. */
export function Film({ name, label, className }: { name: string; label: string; className?: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  // `null` until hydration, so the film starts only once motion is known to be allowed.
  const reduceMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
  // Below the `sm` breakpoint the film is hidden and its video never loads: its code is unreadable at that width.
  const wide = useMediaQuery("(min-width: 40rem)");

  useEffect(() => {
    // The browser can refuse autoplay; the play button stays available.
    if (reduceMotion === false && wide) videoRef.current?.play().catch(() => {});
  }, [reduceMotion, wide]);

  const toggle = () => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) video.play().catch(() => {});
    else video.pause();
  };

  return (
    <div className={cn("relative hidden overflow-hidden rounded-lg border border-fd-border sm:block", className)}>
      <video
        ref={videoRef}
        src={`/motion/${name}.mp4`}
        // First frame: playback starts without a cut. Without motion, a still from mid-film tells the story.
        poster={`/motion/${name}-poster${reduceMotion ? "-still" : ""}.webp`}
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
