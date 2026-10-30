import { createHighlighterCore } from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import grammar from "../../../etc/vsc-extension/syntaxes/x2c.tmLanguage.json";

type Example = {
  id: string; path: string; source: string; runnable: boolean; output?: string;
};

export function setupPlayground() {
  const root = document.querySelector<HTMLElement>("[data-playground]");
  if (!root) return;
  const source = root.querySelector<HTMLTextAreaElement>("textarea")!;
  const list = root.querySelector<HTMLElement>("[data-example-list]")!;
  const links = [...list.querySelectorAll<HTMLAnchorElement>("a[data-example]")];
  const notes = [...root.querySelectorAll<HTMLElement>("[data-about]")];
  const about = root.querySelector<HTMLElement>("[data-about-body]")!;
  const sourceName = root.querySelector<HTMLElement>("[data-source-name]")!;
  const run = root.querySelector<HTMLButtonElement>("[data-run]")!;
  const stop = root.querySelector<HTMLButtonElement>("[data-stop]")!;
  const output = root.querySelector<HTMLElement>("[data-output]")!;
  const outputTitle = root.querySelector<HTMLElement>("[data-output-title]")!;
  const status = root.querySelector<HTMLElement>("[data-status]")!;
  const highlight = root.querySelector<HTMLElement>("[data-highlight]")!;
  const examples: Example[] = JSON.parse(root.querySelector("[data-examples]")!.textContent!);
  const dark = JSON.parse(root.querySelector("[data-theme]")!.textContent!);
  let highlighter: Awaited<ReturnType<typeof createHighlighterCore>>;
  const paint = () => {
    if (!highlighter) return;
    highlight.innerHTML = highlighter.codeToHtml(source.value + "\n", {
      lang: "x2c", theme: "x2c-dark",
    });
  };
  createHighlighterCore({
    themes: [dark], langs: [{ ...grammar, name: "x2c" }],
    engine: createJavaScriptRegexEngine(),
  }).then((value) => {
    highlighter = value;
    paint();
    root.classList.remove("plain-editor");
  }).catch(() => {
    root.classList.add("plain-editor");
  });
  source.addEventListener("input", paint);
  source.addEventListener("scroll", () => {
    highlight.scrollTop = source.scrollTop;
    highlight.scrollLeft = source.scrollLeft;
  });

  // A memory64 declaration with no instructions feature-detects the target.
  const memory64 = WebAssembly.validate(new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 4, 0,
  ]));
  let selected = examples[0];
  let outputSize = 0;
  let worker: Worker | undefined;
  let request: AbortController | undefined;
  let timer: ReturnType<typeof setTimeout>;
  const halt = () => {
    clearTimeout(timer);
    worker?.terminate();
    worker = undefined;
    request?.abort();
    request = undefined;
    stop.hidden = true;
  };
  const finish = (message: string) => {
    halt();
    run.disabled = !memory64 || !selected.runnable;
    status.textContent = message;
  };
  // Without a compile service the page keeps its rendered status.
  const ready = () => {
    if (!root.dataset.service) return;
    if (!selected.runnable)
      finish("This one needs the native toolchain. The recipe is on the right.");
    else if (!memory64)
      finish("This browser does not support WebAssembly Memory64. Use a current Chrome or Firefox.");
    else finish("Ready.");
  };
  const choose = (example: Example) => {
    halt();
    selected = example;
    for (const link of links) {
      if (link.dataset.example === example.id) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    }
    for (const note of notes) note.hidden = note.dataset.about !== example.id;
    about.scrollTop = 0;
    sourceName.textContent = example.path;
    source.value = example.source;
    source.scrollTop = source.scrollLeft = 0;
    paint();
    outputTitle.textContent = example.output ? "Expected output" : "Output";
    output.textContent = example.output ?? "";
    output.scrollTop = 0;
    ready();
  };
  // Center the chosen entry in whichever list box scrolls at this width.
  const reveal = (link: HTMLElement) => {
    for (const box of [list, link.closest("ul")!]) {
      const outer = box.getBoundingClientRect(), inner = link.getBoundingClientRect();
      box.scrollTop += inner.top - outer.top - (outer.height - inner.height) / 2;
      box.scrollLeft += inner.left - outer.left - (outer.width - inner.width) / 2;
    }
  };
  const requested = new URL(location.href).searchParams.get("example");
  choose(examples.find((entry) => entry.id === requested) ?? examples[0]);
  const initial = links.find((link) => link.dataset.example === selected.id);
  if (initial) reveal(initial);
  for (const link of links) link.addEventListener("click", (event) => {
    event.preventDefault();
    choose(examples.find((entry) => entry.id === link.dataset.example)!);
    const url = new URL(location.href);
    url.searchParams.set("example", selected.id);
    history.replaceState(null, "", url);
  });

  stop.addEventListener("click", () => finish("Stopped."));
  addEventListener("pagehide", () => {
    if (worker || request) finish("Stopped.");
  });
  run.addEventListener("click", async () => {
    run.disabled = true;
    stop.hidden = false;
    outputTitle.textContent = "Output";
    output.replaceChildren();
    outputSize = 0;
    status.textContent = "Compiling...";
    request = new AbortController();
    const current = request;
    timer = setTimeout(() => finish("Compilation timed out."), 25000);
    try {
      const response = await fetch(`${root.dataset.service!.replace(/\/$/, "")}/compile`, {
        method: "POST", body: source.value, headers: { "Content-Type": "text/plain" },
        signal: current.signal,
      });
      const result = await response.json();
      if (current !== request) return;
      if (!response.ok) throw new Error(result.error || "Compilation failed.");
      clearTimeout(timer);
      status.textContent = "Running...";
      worker = new Worker(new URL("./playground-worker.ts", import.meta.url), { type: "module" });
      worker.onmessage = ({ data }) => {
        if (data.kind === "exit") finish(`Finished (exit ${data.status}).`);
        else if (data.kind === "error") finish(`Program failed: ${data.text}`);
        else {
          outputSize += data.text.length + 1;
          if (outputSize > 1000000 || output.childElementCount >= 10000) {
            finish("Stopped: output limit reached.");
            return;
          }
          const line = document.createElement("span");
          line.className = data.kind;
          line.textContent = `${data.text}\n`;
          output.append(line);
          output.scrollTop = output.scrollHeight;
        }
      };
      worker.onerror = (event) => finish(`Program failed: ${event.message}`);
      timer = setTimeout(() => finish("Stopped after 10 seconds."), 10000);
      worker.postMessage(result);
    } catch (error) {
      if (current === request) finish(String(error));
    }
  });
}
