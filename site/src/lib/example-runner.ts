// Run the published WebAssembly program beside its complete source.
export function setupExampleRunner(root: HTMLElement) {
  const comparison = root.querySelector<HTMLElement>("[data-output-comparison]")!;
  const run = root.querySelector<HTMLButtonElement>("[data-run]")!;
  const stop = root.querySelector<HTMLButtonElement>("[data-stop]")!;
  const output = root.querySelector<HTMLElement>("[data-output]")!;
  const status = root.querySelector<HTMLElement>("[data-status]")!;
  const [example] = JSON.parse(root.querySelector("[data-examples]")!.textContent!);
  const programs = root.dataset.programs;
  let outputSize = 0;
  let worker: Worker | undefined;
  let request: AbortController | undefined;
  let timer: ReturnType<typeof setTimeout>;
  // A memory64 declaration with no instructions feature-detects the target.
  const memory64 = WebAssembly.validate(new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 4, 0,
  ]));
  // Native-only examples keep their local recipe and expected output.
  const ready = (message = "Ready.") => {
    const available = example.runnable !== false && Boolean(programs && example.program);
    run.hidden = !available;
    if (!available) {
      status.textContent = example.runnable === false
        ? "This example needs the native toolchain. Use its local recipe."
        : "Running programs is unavailable in this build. Use the local recipe to run this example.";
      return;
    }
    run.disabled = !memory64;
    status.textContent = !memory64
      ? "This browser does not support WebAssembly Memory64. Use a current Chrome or Firefox."
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
  run.addEventListener("click", async () => {
    run.disabled = true;
    stop.hidden = false;
    comparison.style.minHeight = `${comparison.getBoundingClientRect().height}px`;
    output.replaceChildren();
    outputSize = 0;
    status.textContent = "Loading...";
    request = new AbortController();
    const current = request;
    timer = setTimeout(() => finish("Loading timed out."), 25000);
    try {
      const program = await fetchProgram(current.signal);
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
