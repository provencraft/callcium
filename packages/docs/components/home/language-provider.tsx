"use client";

import { createContext, useCallback, useContext, useSyncExternalStore } from "react";
import type { ReactNode } from "react";

export type Lang = "solidity" | "typescript";

// Shared with Fumadocs Tabs `groupId`: a docs code group using this id and `persist` picks up the visitor's landing
// choice from localStorage.
const STORAGE_KEY = "callcium-lang";

type LanguageContextValue = { lang: Lang; setLang: (lang: Lang) => void };

const LanguageContext = createContext<LanguageContextValue | null>(null);

function isLang(value: string | null): value is Lang {
  return value === "solidity" || value === "typescript";
}

const listeners = new Set<() => void>();

// The storage event reaches other tabs only; listeners cover this one.
function subscribe(onChange: () => void) {
  listeners.add(onChange);
  window.addEventListener("storage", onChange);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener("storage", onChange);
  };
}

function readLang(): Lang {
  const stored = localStorage.getItem(STORAGE_KEY);
  return isLang(stored) ? stored : "solidity";
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  // The server snapshot is Solidity for a deterministic SSR render; the stored choice is applied after hydration (a
  // brief Solidity-first paint is acceptable).
  const lang = useSyncExternalStore(subscribe, readLang, (): Lang => "solidity");

  const setLang = useCallback((next: Lang) => {
    localStorage.setItem(STORAGE_KEY, next);
    for (const listener of listeners) listener();
  }, []);

  return <LanguageContext.Provider value={{ lang, setLang }}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error("useLanguage must be used within LanguageProvider.");
  return ctx;
}
