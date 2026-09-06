// Astro and mdBook use these palettes with the VS Code extension grammar.

import { bundledThemes } from "shiki";

const paper = "#e9e5df";
const coral = "#ff715a";
const keyword = "#f0ada1";
const type = "#a6d9e5";
const number = "#a9c9f5";
const comment = "#8b857f";
const string = "#9edfb8";

const darkTheme = {
  name: "x2c-dark",
  type: "dark",
  colors: { "editor.background": "#101011", "editor.foreground": paper },
  tokenColors: [
    {
      scope: ["comment", "punctuation.definition.comment"],
      settings: { foreground: comment }
    },
    {
      scope: ["string", "constant.character.escape"],
      settings: { foreground: string }
    },
    { scope: ["constant.numeric"], settings: { foreground: number } },
    {
      scope: [
        "keyword.control",
        "keyword.declaration",
        "storage.modifier",
        "storage.type"
      ],
      settings: { foreground: keyword }
    },
    {
      scope: [
        "support.type",
        "entity.name.type",
        "storage.type.protocol",
        "storage.type.macro.result"
      ],
      settings: { foreground: type }
    },
    // The literal and macro sigils are the punctuation x2c adds to C.
    {
      scope: [
        "punctuation.definition.literal",
        "punctuation.definition.interpolation",
        "punctuation.definition.macro.sigil",
        "punctuation.definition.macro.splice",
        "punctuation.definition.embedded.lisp",
        "entity.name.function.macro",
        "entity.name.function.macro-alias"
      ],
      settings: { foreground: coral }
    },
    // Ordinary operators and identifiers stay the body colour.
    {
      scope: [
        "keyword.operator",
        "entity.name.function",
        "variable",
        "constant.language"
      ],
      settings: { foreground: paper }
    },
    // Terminal prompts match the hero window.
    {
      scope: [
        "punctuation.separator.prompt",
        "entity.name.prompt",
        "punctuation.definition.prompt"
      ],
      settings: { foreground: coral }
    }
  ]
};

const distinctScopes = [
  "keyword.control.in.x2c",
  "keyword.control.try.x2c",
  "keyword.control.catch.x2c",
  "keyword.control.finally.x2c",
  "keyword.control.defer.x2c",
  "keyword.control.raise.x2c",
  "keyword.control.match.x2c",
  "storage.modifier.delegate.x2c",
  "storage.modifier.threaded.x2c",
  "keyword.control.import.x2c",
  "keyword.control.with.x2c",
  "keyword.declaration.protocol.x2c",
  "keyword.control.foreach.x2c",
  "keyword.operator.is.x2c",
  "storage.type.self.x2c",
  "keyword.declaration.macro.x2c",
  "keyword.other.macro.using.x2c",
  "keyword.operator.arrow.x2c"
];

function withDistinctColors(theme, name, colors) {
  return {
    ...theme,
    name,
    tokenColors: [
      ...theme.tokenColors,
      {
        scope: distinctScopes,
        settings: {
          foreground: colors.keyword,
          fontStyle: "bold"
        }
      },
      {
        scope: "support.type.prelude.x2c",
        settings: {
          foreground: colors.prelude,
          fontStyle: ""
        }
      },
      {
        scope: [
          "storage.type.macro.result.x2c",
          "storage.type.macro.hole.x2c"
        ],
        settings: {
          foreground: colors.macroType,
          fontStyle: "italic"
        }
      }
    ]
  };
}

export const x2cDarkTheme = withDistinctColors(darkTheme, "x2c-dark", {
  keyword: "#FF4FD8",
  prelude: "#29D3E2",
  macroType: "#FFB454"
});

const githubLight = (await bundledThemes["github-light"]()).default;

export const x2cLightTheme = withDistinctColors(
  githubLight,
  "x2c-light",
  {
    keyword: "#A626A4",
    prelude: "#007C8A",
    macroType: "#A15C00"
  }
);
