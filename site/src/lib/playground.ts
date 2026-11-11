import { createHighlighterCore } from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import grammar from "../../../etc/vsc-extension/syntaxes/x2c.tmLanguage.json";

interface Example {
  id: string; source: string; visible: string; program: boolean;
  path?: string; runnable?: boolean; output?: string;
}

export function setupPlayground() {
  const root = document.querySelector<HTMLElement>("[data-playground]");
  if (!root) return;
  const source = root.querySelector<HTMLTextAreaElement>("textarea")!;
  const select = root.querySelector<HTMLSelectElement>("select");
  const links = [...root.querySelectorAll<HTMLAnchorElement>("[data-example-list] a[data-example]")];
  const notes = [...root.querySelectorAll<HTMLElement>("[data-about]")];
  const sourceName = root.querySelector<HTMLElement>("[data-source-name]");
  const outputTitle = root.querySelector<HTMLElement>("[data-output-title]");
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
  if (select) select.value = example.id;
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
    const available = example.runnable !== false && Boolean(service || example.program);
    run.hidden = !available;
    if (!available) {
      reset.hidden = true;
      status.textContent = example.runnable === false
        ? "This example needs the native toolchain. Use its local recipe."
        : "Running programs is unavailable in this build. You can still read and edit the examples.";
      return;
    }
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
    if (sourceName) sourceName.textContent = example.path ?? example.id;
    for (const link of links) {
      if (link.dataset.example === example.id) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    }
    for (const note of notes) note.hidden = note.dataset.about !== example.id;
    if (outputTitle) {
      outputTitle.textContent = example.output ? "Expected output" : "Output";
      output.textContent = example.output ?? "";
      root.querySelector("[data-about-body]")!.scrollTop = 0;
    }
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
  const choose = (id: string) => {
    finish("Stopped.");
    example = examples.find(entry => entry.id === id)!;
    load();
    const url = new URL(location.href);
    url.searchParams.set("example", id);
    history.replaceState(null, "", url);
  };
  select?.addEventListener("change", () => choose(select.value));
  for (const link of links) link.addEventListener("click", event => {
    event.preventDefault();
    choose(link.dataset.example!);
  });
  reset.addEventListener("click", load);
  stop.addEventListener("click", () => finish("Stopped."));
  addEventListener("pagehide", () => finish("Stopped."));
  load();

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
    if (outputTitle) outputTitle.textContent = "Output";
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
