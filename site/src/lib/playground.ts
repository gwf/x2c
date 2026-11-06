import { createHighlighterCore } from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import grammar from "../../../etc/vsc-extension/syntaxes/x2c.tmLanguage.json";

interface Example {
  id: string; source: string; visible: string; program: boolean;
}

export function setupPlayground() {
  const root = document.querySelector<HTMLElement>("[data-playground]");
  if (!root) return;
  const source = root.querySelector<HTMLTextAreaElement>("textarea")!;
  const select = root.querySelector<HTMLSelectElement>("select")!;
  const run = root.querySelector<HTMLButtonElement>("[data-run]")!;
  const stop = root.querySelector<HTMLButtonElement>("[data-stop]")!;
  const reset = root.querySelector<HTMLButtonElement>("[data-reset]")!;
  const output = root.querySelector<HTMLElement>("[data-output]")!;
  const status = root.querySelector<HTMLElement>("[data-status]")!;
  const highlight = root.querySelector<HTMLElement>("[data-highlight]")!;
  const examples: Example[] =
    JSON.parse(root.querySelector("[data-examples]")!.textContent!);
  const service = root.dataset.service?.replace(/\/$/, "");
  const programs = root.dataset.programs;
  const requested = new URL(location.href).searchParams.get("example");
  let example = examples.find((entry) => entry.id === requested) ?? examples[0];
  // A compile service needs the whole program; otherwise show the slide's code.
  const original = (entry: Example) => service ? entry.source : entry.visible;
  const edited = () => source.value !== original(example);
  select.value = example.id;
  source.value = original(example);
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

  let outputSize = 0;
  let worker: Worker | undefined;
  let request: AbortController | undefined;
  let timer: ReturnType<typeof setTimeout>;
  // A memory64 declaration with no instructions feature-detects the target.
  const memory64 = WebAssembly.validate(new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 4, 0,
  ]));
  // Without a service, only an unedited precompiled example can run.
  const ready = (message = "Ready.") => {
    if (!service && !programs) return;
    const blocked = !service && edited();
    run.disabled = !memory64 || blocked;
    reset.hidden = !blocked;
    status.textContent = !memory64
      ? "This browser does not support WebAssembly Memory64. Use a current Chrome or Firefox."
      : blocked ? "Edited programs cannot run without a compile service."
      : message;
  };
  const finish = (message: string) => {
    clearTimeout(timer);
    worker?.terminate();
    worker = undefined;
    request?.abort();
    request = undefined;
    stop.hidden = true;
    ready(message);
  };
  const load = () => {
    source.value = original(example);
    source.scrollTop = source.scrollLeft = 0;
    paint();
    if (!request && !worker) ready();
  };
  source.addEventListener("input", () => {
    paint();
    if (!request && !worker) ready();
  });
  source.addEventListener("scroll", () => {
    highlight.scrollTop = source.scrollTop;
    highlight.scrollLeft = source.scrollLeft;
  });
  select.addEventListener("change", () => {
    example = examples.find((entry) => entry.id === select.value)!;
    load();
    const url = new URL(location.href);
    url.searchParams.set("example", select.value);
    history.replaceState(null, "", url);
  });
  reset.addEventListener("click", load);
  stop.addEventListener("click", () => finish("Stopped."));
  addEventListener("pagehide", () => finish("Stopped."));
  ready();

  const write = (kind: string, text: string) => {
    outputSize += text.length + 1;
    if (outputSize > 1000000 || output.childElementCount >= 10000) {
      finish("Stopped: output limit reached.");
      return;
    }
    const line = document.createElement("span");
    line.className = kind;
    line.textContent = `${text}\n`;
    output.append(line);
    output.scrollTop = output.scrollHeight;
  };
  const fetchOk = async (url: string, signal: AbortSignal) => {
    const response = await fetch(url, { signal });
    if (!response.ok) throw new Error(`Unable to load ${url}.`);
    return response;
  };
  // A precompiled program runs the example as published.
  const fetchProgram = async (signal: AbortSignal) => {
    const url = `${programs}${example.id}`;
    const [loader, wasm] = await Promise.all([
      fetchOk(`${url}.js`, signal).then((response) => response.text()),
      fetchOk(`${url}.wasm`, signal).then((response) => response.arrayBuffer()),
    ]);
    return { loader, wasm };
  };
  // The service compiles the editor's text; diagnostics go to the output.
  const compile = async (signal: AbortSignal) => {
    const response = await fetch(`${service}/compile`, {
      method: "POST", body: source.value, headers: { "Content-Type": "text/plain" },
      signal,
    });
    const result = await response.json();
    if (response.ok) return result;
    for (const text of String(result.error || "").trimEnd().split("\n"))
      write("stderr", text);
    throw new Error("Compilation failed.");
  };
  run.addEventListener("click", async () => {
    run.disabled = true;
    stop.hidden = false;
    output.replaceChildren();
    outputSize = 0;
    const precompiled = Boolean(programs && example.program && !edited());
    status.textContent = precompiled ? "Loading..." : "Compiling...";
    request = new AbortController();
    const current = request;
    timer = setTimeout(() => finish(precompiled
      ? "Loading timed out." : "Compilation timed out."), 25000);
    try {
      const program = await (precompiled ? fetchProgram : compile)(current.signal);
      if (current !== request) return;
      clearTimeout(timer);
      status.textContent = "Running...";
      worker = new Worker(new URL("./playground-worker.ts", import.meta.url),
        { type: "module" });
      worker.onmessage = ({ data }) => {
        if (data.kind === "exit") finish(`Finished (exit ${data.status}).`);
        else if (data.kind === "error") finish(`Program failed: ${data.text}`);
        else write(data.kind, data.text);
      };
      worker.onerror = (event) => finish(`Program failed: ${event.message}`);
      timer = setTimeout(() => finish("Stopped after 10 seconds."), 10000);
      worker.postMessage(program,
        program.wasm instanceof ArrayBuffer ? [program.wasm] : []);
    } catch (error) {
      if (current === request)
        finish(error instanceof Error ? error.message : String(error));
    }
  });
}
