import { createHighlighterCore } from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import grammar from "../../../etc/vsc-extension/syntaxes/x2c.tmLanguage.json";

export function setupPlayground() {
  const root = document.querySelector<HTMLElement>("[data-playground]");
  if (!root) return;
  const source = root.querySelector<HTMLTextAreaElement>("textarea")!;
  const select = root.querySelector<HTMLSelectElement>("select")!;
  const run = root.querySelector<HTMLButtonElement>("[data-run]")!;
  const stop = root.querySelector<HTMLButtonElement>("[data-stop]")!;
  const output = root.querySelector<HTMLElement>("[data-output]")!;
  const status = root.querySelector<HTMLElement>("[data-status]")!;
  const highlight = root.querySelector<HTMLElement>("[data-highlight]")!;
  const examples = JSON.parse(root.querySelector("[data-examples]")!.textContent!);
  const requested = new URL(location.href).searchParams.get("example");
  const initial = examples.find((entry: { id: string }) => entry.id === requested)
    ?? examples[0];
  select.value = initial.id;
  source.value = initial.source;
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
  select.addEventListener("change", () => {
    source.value = examples.find((entry: { id: string }) => entry.id === select.value).source;
    source.scrollTop = source.scrollLeft = 0;
    paint();
    const url = new URL(location.href);
    url.searchParams.set("example", select.value);
    history.replaceState(null, "", url);
  });
  let outputSize = 0;
  let worker: Worker | undefined;
  let request: AbortController | undefined;
  let timer: ReturnType<typeof setTimeout>;
  const finish = (message: string) => {
    clearTimeout(timer);
    worker?.terminate();
    worker = undefined;
    request?.abort();
    request = undefined;
    run.disabled = false;
    stop.hidden = true;
    status.textContent = message;
  };
  stop.addEventListener("click", () => finish("Stopped."));
  addEventListener("pagehide", () => finish("Stopped."));
  // A memory64 declaration with no instructions feature-detects the target.
  const memory64 = WebAssembly.validate(new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 4, 0,
  ]));
  if (!memory64 && root.dataset.service) {
    run.disabled = true;
    status.textContent = "This browser does not support WebAssembly Memory64. Use a current Chrome or Firefox.";
  }
  run.addEventListener("click", async () => {
    run.disabled = true;
    stop.hidden = false;
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
