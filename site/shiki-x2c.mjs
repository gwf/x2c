// The site highlights x2c with the same TextMate grammar the VS Code
// extension ships, so a sample on the website and the same sample in the
// editor are coloured by one description of the language.
//
// The dark theme maps that grammar's scopes onto the site palette in
// site/src/styles/global.css. The book also uses a light theme for its
// selectable light backgrounds.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  x2cDarkTheme,
  x2cLightTheme
} from "./shiki-x2c-theme.mjs";

export { x2cDarkTheme, x2cLightTheme };

const read = (path) =>
  JSON.parse(readFileSync(fileURLToPath(new URL(path, import.meta.url)), "utf8"));

export const x2cLang = {
  ...read("../etc/vsc-extension/syntaxes/x2c.tmLanguage.json"),
  name: "x2c"
};

export const x2cLispLang = {
  ...read("../etc/vsc-extension/syntaxes/x2c-lisp.tmLanguage.json"),
  name: "x2c-lisp"
};
