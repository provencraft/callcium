import Image from "next/image";
import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";

// GitHub repository the docs link to.
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
          <Image src="/logo-horizontal.svg" alt="Callcium" width={118} height={34} className="dark:hidden" priority />
          <Image
            src="/logo-horizontal-dark.svg"
            alt="Callcium"
            width={118}
            height={34}
            className="hidden dark:block"
            priority
          />
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
        type: "menu",
        text: "Tools",
        items: [
          {
            text: "Policy Builder",
            url: "/policy-builder",
            description: "Visually construct a policy.",
          },
          {
            text: "Policy Inspector",
            url: "/policy-inspector",
            description: "Decode and explain a policy blob.",
          },
          {
            text: "Policy Enforcer",
            url: "/policy-enforcer",
            description: "Test calldata against a policy.",
          },
        ],
      },
    ],
    githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
  };
}
