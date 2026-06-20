import { highlight } from "fumadocs-core/highlight";
import { Pre } from "fumadocs-ui/components/codeblock";
import { shikiThemes } from "@/lib/shiki";

export type CodeLang = "solidity" | "typescript";

/** Server-side syntax highlight using the Callcium brand Shiki themes. */
export async function renderCode(code: string, lang: CodeLang) {
  return highlight(code, {
    lang,
    themes: shikiThemes,
    defaultColor: false,
    components: {
      pre: (props) => <Pre {...props} />,
    },
  });
}
