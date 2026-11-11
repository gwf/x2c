#pragma once

/*  code.x -- the gallery's Code page */

#include "state.x"

void page_code(Ui ui, Gallery g) {
  section(ui, "Code block", "Highlighting for C, C++, JavaScript, "
                            "TypeScript, Python, Rust, Go, JSON and shell.");
  ui.code_block("c-sample",
    "#include <cui/cui.h>\n"
    "\n"
    "/* A counter with a button */\n"
    "static int clicks = 0;\n"
    "\n"
    "void frame(cui_ctx *ui) {\n"
    "    if (cui_button(ui, \"Click me\", .variant = CUI_BUTTON_PRIMARY)) "
    "clicks++;\n"
    "    cui_textf(ui, \"Clicked %d times\", clicks);\n"
    "    float ratio = clicks / 10.0f;   // grows with each click\n"
    "}\n",
    lang: "c", title: "counter.c", line_numbers: true,
    highlight_from: 7);
  $cui.row(ui, { .gap = 16, .align = CUI_ALIGN_START, .width = CUI_FILL }) {
    $cui.box(ui, { .width = CUI_GROW(1) })
      ui.code_block("py",
        "def fib(n: int) -> int:\n"
        "    # the slow way, on purpose\n"
        "    if n < 2:\n"
        "        return n\n"
        "    return fib(n - 1) + fib(n - 2)\n"
        "\n"
        "print([fib(k) for k in range(10)])\n",
        lang: "python", title: "fib.py");
    $cui.box(ui, { .width = CUI_GROW(1) })
      ui.code_block("sh",
        "git clone https://github.com/yappologistic/CUI.git\n"
        "cmake -S CUI -B build\n"
        "cmake --build build\n"
        "./build/examples/gallery  # run it\n",
        lang: "shell");
  }
  section(ui, "JSON viewer", "Collapsible, with counts. Click a brace to "
                             "fold it.");
  ui.json_view("json",
    "{\"name\": \"cui\", \"version\": \"1.1.0\", \"private\": false, "
    "\"downloads\": 128400,\n"
    " \"platforms\": [\"windows\", \"macos\", \"linux\"],\n"
    " \"renderer\": {\"backend\": \"opengl\", \"fallback\": \"software\", "
    "\"vsync\": true, \"msaa\": null},\n"
    " \"authors\": [{\"name\": \"Maya\", \"commits\": 412}, "
    "{\"name\": \"Jonas\", \"commits\": 388}]}",
    expand_depth: 2);
  ui.json_view("broken", "{\"ok\": true, \"oops\": [1, 2,}");
}
