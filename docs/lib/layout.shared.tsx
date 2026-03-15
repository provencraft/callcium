import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import Image from "next/image";

// fill this with your actual GitHub info, for example:
export const gitConfig = {
  user: "provencraft",
  repo: "callcium",
  branch: "main",
};

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <>
          <Image src="/icon.svg" alt="Callcium Logo" width={28} height={28} />
          <span
            style={{
              fontSize: "1.2rem",
              fontWeight: 600,
              fontFamily: "var(--font-mono)",
            }}
          >
            Callcium
          </span>
        </>
      ),
    },
    searchToggle: { enabled: false },
    links: [
      {
        text: "Docs",
        url: "/docs",
        active: "nested-url",
      },
      {
        text: "Policy Inspector",
        url: "/policy-inspector",
      },
    ],
    githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
  };
}
