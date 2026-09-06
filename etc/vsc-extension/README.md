# x2c Language Support

This VS Code extension provides the TextMate grammar and language
configuration for x2c source files (`.x`, `.xc`, `.xh`, `.x2c`, and
`.xmacro`) and compile-time Lisp files (`.xlisp`).

It highlights x2c list, array, map, string, Symbol, and SymbolSet literals,
including data-first Array and Map contents and their runtime unquotes;
pattern variables; runtime unquote and List splice forms; protocols; macros;
decorators; `with` blocks; List destructuring; imports; delegate fields;
`Self` method types; embedded and standalone compile-time Lisp; and the
C-compatible syntax used by the language.

This is a syntax-only extension. It does not install or run the x2c compiler,
execute workspace code, collect telemetry, or make network requests.

## Installation

Find **x2c Language Support** by **x2c** in the VS Code Extensions view,
or install a packaged VSIX with **Extensions: Install from VSIX**.

## Distinct x2c colors

The extension contributes scopes but does not override the active theme. To
use the colors shown below, copy either the dark or light setting into VS Code's
`settings.json`.

Dark backgrounds:

```json
"editor.tokenColorCustomizations": {
  "textMateRules": [
    {
      "scope": [
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
      ],
      "settings": { "foreground": "#FF4FD8", "fontStyle": "bold" }
    },
    {
      "scope": "support.type.prelude.x2c",
      "settings": { "foreground": "#29D3E2", "fontStyle": "" }
    },
    {
      "scope": [
        "storage.type.macro.result.x2c",
        "storage.type.macro.hole.x2c"
      ],
      "settings": { "foreground": "#FFB454", "fontStyle": "italic" }
    }
  ]
}
```

Light backgrounds:

```json
"editor.tokenColorCustomizations": {
  "textMateRules": [
    {
      "scope": [
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
      ],
      "settings": { "foreground": "#A626A4", "fontStyle": "bold" }
    },
    {
      "scope": "support.type.prelude.x2c",
      "settings": { "foreground": "#007C8A", "fontStyle": "" }
    },
    {
      "scope": [
        "storage.type.macro.result.x2c",
        "storage.type.macro.hole.x2c"
      ],
      "settings": { "foreground": "#A15C00", "fontStyle": "italic" }
    }
  ]
}
```

![Dark and light x2c highlighting](https://raw.githubusercontent.com/gwf/x2c/main/etc/vsc-extension/images/vscode-highlighting-sample.png)

The syntax scopes cover `in`, `try`, `catch`, `finally`, `defer`, `raise`,
`match`, `delegate`, `threaded`, `import`, `with`, `as`, `protocol`,
`associated`, `foreach`, `is not`, `Self`, `macro`, `keyword`, `using`, and
`=>`. Prelude types use `support.type.prelude.x2c`: `Array`, `Atom`, `Block`,
`Buffer`, `Bytes`, `Context`, `Error`, `ErrorHandler`, `File`, `Func`, `Iter`,
`Lambda`, `Lisp`, `List`, `Logger`, `LogSink`, `Map`, `Mutex`, `Pool`, `Scope`,
`Split`, `String`, `Symbol`, `SymbolSet`, `Thread`, `Token`, `Tokenizer`, and
`Var`. Macro result and hole kinds keep the
`storage.type.macro.result.x2c` and `storage.type.macro.hole.x2c` scopes.

For another background, keep the scope arrays and change only the three
`foreground` values. An empty `fontStyle` keeps prelude types upright. The
specific keyword and modifier scopes retain their broader parent scopes, so
existing theme rules continue to apply when these settings are absent.

## Development

Open this directory in VS Code and press F5 to launch an Extension Development
Host. Open an x2c source file and use **Developer: Inspect Editor Tokens and
Scopes** to inspect the grammar.

The most useful scopes are:

- `punctuation.definition.literal.*.x2c` for literal delimiters;
- `meta.literal.*.content.x2c` for collection contents;
- `constant.other.atom.x2c` for bare data names;
- `constant.other.symbol.x2c` for symbols;
- `variable.other.pattern.*.x2c` for pattern variables; and
- `variable.other.interpolation.*.x2c` for runtime unquote and splice forms;
- `meta.destructuring.*.x2c` and
  `variable.other.readwrite.destructuring.x2c` for List destructuring;
- `keyword.declaration.macro.x2c` and `entity.name.function.macro.x2c` for
  macro definitions and applications; and
- `meta.embedded.lisp.x2c` and `*.lisp.x2c` for compile-time Lisp.

Standard C strings retain the standard `string.quoted.double` and
`string.quoted.single` scopes for theme compatibility.

## Packaging

Install the pinned development dependencies, run the scope tests, then build
the VSIX:

```sh
npm ci
npm test
npm run build
```

The packaged VSIX is tracked with the extension source. Install it from
VS Code with **Extensions: Install from VSIX**.

When changing the grammar, keep x2c-specific rules ahead of competing C
operator, call, string, and angle-bracket rules. Add scope tests for both the
x2c form and the ordinary C syntax it could be confused with.

## Marketplace identity

The Marketplace publisher is `x2c-lang`, displayed as x2c. The extension ID is
`x2c-lang.x2c-syntax`. Version 0.1.23 retains the Preview label.

## License and support

The extension is licensed under the
[Apache License 2.0](LICENSE.md); its attribution notice is in
[NOTICE](NOTICE). x2c is experimental and has no support commitment. See
[SUPPORT.md](SUPPORT.md) for reporting bugs and getting help.
