import type { ThemeRegistration } from "shiki";

/**
 * Custom Shiki themes derived from the Callcium brand palette.
 *
 * Palette: #177E89 teal, #084C61 navy, #DB3A34 red, #FFC857 amber, #323031 charcoal.
 */

const callciumLight = {
  name: "callcium-light",
  type: "light",
  colors: {
    "editor.background": "#faf9f7",
    "editor.foreground": "#323031",
    "editorLineNumber.foreground": "#b0a8a0",
    "editor.selectionBackground": "#ffc85733",
    "editor.lineHighlightBackground": "#ffc85718",
  },
  settings: [
    { settings: { foreground: "#323031" } },
    {
      scope: ["comment", "punctuation.definition.comment"],
      settings: { foreground: "#9e9490", fontStyle: "italic" },
    },
    {
      scope: ["keyword", "storage.type", "storage.modifier"],
      settings: { foreground: "#177E89" },
    },
    {
      scope: ["entity.name.function", "support.function"],
      settings: { foreground: "#b52e29" },
    },
    {
      scope: ["string", "string.quoted"],
      settings: { foreground: "#a6841e" },
    },
    {
      scope: ["constant.numeric", "constant.language"],
      settings: { foreground: "#a6841e" },
    },
    {
      scope: ["variable", "variable.other", "variable.parameter"],
      settings: { foreground: "#323031" },
    },
    {
      scope: ["variable.language"],
      settings: { foreground: "#3a6894" },
    },
    {
      scope: ["entity.name.type", "entity.name.class"],
      settings: { foreground: "#6b4ea0" },
    },
    {
      scope: ["entity.name.type.interface", "entity.name.type.contract.extend"],
      settings: { foreground: "#323031" },
    },
    {
      scope: ["support.type"],
      settings: { foreground: "#3a6894" },
    },
    {
      scope: ["punctuation", "meta.brace"],
      settings: { foreground: "#6b6462" },
    },
    {
      scope: ["constant.other", "variable.other.constant"],
      settings: { foreground: "#a6841e" },
    },
    {
      scope: ["entity.name.tag"],
      settings: { foreground: "#177E89" },
    },
    {
      scope: ["entity.other.attribute-name"],
      settings: { foreground: "#DB3A34" },
    },
    {
      scope: ["keyword.operator", "keyword.operator.assignment"],
      settings: { foreground: "#6b6462" },
    },
  ],
};

const callciumDark = {
  name: "callcium-dark",
  type: "dark",
  colors: {
    "editor.background": "#1a1817",
    "editor.foreground": "#e8dfd6",
    "editorLineNumber.foreground": "#6b6260",
    "editor.selectionBackground": "#ffc85722",
    "editor.lineHighlightBackground": "#ffc85710",
  },
  settings: [
    { settings: { foreground: "#e8dfd6" } },
    {
      scope: ["comment", "punctuation.definition.comment"],
      settings: { foreground: "#7a706a", fontStyle: "italic" },
    },
    {
      scope: ["keyword", "storage.type", "storage.modifier"],
      settings: { foreground: "#4abcc7" },
    },
    {
      scope: ["entity.name.function", "support.function"],
      settings: { foreground: "#e8625e" },
    },
    {
      scope: ["string", "string.quoted"],
      settings: { foreground: "#FFC857" },
    },
    {
      scope: ["constant.numeric", "constant.language"],
      settings: { foreground: "#FFC857" },
    },
    {
      scope: ["variable", "variable.other", "variable.parameter"],
      settings: { foreground: "#e8dfd6" },
    },
    {
      scope: ["variable.language"],
      settings: { foreground: "#7aadcc" },
    },
    {
      scope: ["entity.name.type", "entity.name.class"],
      settings: { foreground: "#b09fdc" },
    },
    {
      scope: ["entity.name.type.interface", "entity.name.type.contract.extend"],
      settings: { foreground: "#e8dfd6" },
    },
    {
      scope: ["support.type"],
      settings: { foreground: "#7aadcc" },
    },
    {
      scope: ["punctuation", "meta.brace"],
      settings: { foreground: "#9e938d" },
    },
    {
      scope: ["constant.other", "variable.other.constant"],
      settings: { foreground: "#FFC857" },
    },
    {
      scope: ["entity.name.tag"],
      settings: { foreground: "#4abcc7" },
    },
    {
      scope: ["entity.other.attribute-name"],
      settings: { foreground: "#e8625e" },
    },
    {
      scope: ["keyword.operator", "keyword.operator.assignment"],
      settings: { foreground: "#9e938d" },
    },
  ],
};

export const shikiThemes: {
  light: ThemeRegistration;
  dark: ThemeRegistration;
} = {
  light: callciumLight as ThemeRegistration,
  dark: callciumDark as ThemeRegistration,
};
