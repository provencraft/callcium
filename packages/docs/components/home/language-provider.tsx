"use client";

import { createContext, useCallback, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";

export type Lang = "solidity" | "typescript";

// Shared with Fumadocs Tabs `groupId`: a docs code group using this id and
// `persist` picks up the visitor's landing choice from localStorage.
const STORAGE_KEY = "callcium-lang";

type LanguageContextValue = { lang: Lang; setLang: (lang: Lang) => void };

const LanguageContext = createContext<LanguageContextValue | null>(null);

function isLang(value: string | null): value is Lang {
  return value === "solidity" || value === "typescript";
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  // Default to Solidity for a deterministic SSR render; the stored choice is
  // applied after mount (a brief Solidity-first paint is acceptable).
  const [lang, setLangState] = useState<Lang>("solidity");

  useEffect(() => {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (isLang(stored)) setLangState(stored);

    const onStorage = (event: StorageEvent) => {
      if (event.key === STORAGE_KEY && isLang(event.newValue)) setLangState(event.newValue);
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  const setLang = useCallback((next: Lang) => {
    setLangState(next);
    localStorage.setItem(STORAGE_KEY, next);
  }, []);

  return <LanguageContext.Provider value={{ lang, setLang }}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error("useLanguage must be used within LanguageProvider.");
  return ctx;
}
