// Run the published WebAssembly program beside its complete source.
export function setupExampleRunner(root: HTMLElement) {
  const comparison = root.querySelector<HTMLElement>("[data-output-comparison]")!;
  const run = root.querySelector<HTMLButtonElement>("[data-run]")!;
  const stop = root.querySelector<HTMLButtonElement>("[data-stop]")!;
  const output = root.querySelector<HTMLElement>("[data-output]")!;
  const status = root.querySelector<HTMLElement>("[data-status]")!;
  const input = root.querySelector<HTMLInputElement>("[data-input-file]");
  const downloads = root.querySelector<HTMLElement>("[data-downloads]")!;
  const [example] = JSON.parse(root.querySelector("[data-examples]")!.textContent!);
  const programs = root.dataset.programs;
  const profile = root.dataset.profile;
  const persistence = root.dataset.persistence;
  let outputSize = 0;
  let worker: Worker | undefined;
  let request: AbortController | undefined;
  let timer: ReturnType<typeof setTimeout>;
  let downloadUrls: string[] = [];
  // A memory64 declaration with no instructions feature-detects the target.
  const memory64 = WebAssembly.validate(new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 4, 0,
  ]));
  // A build without precompiled programs keeps the local recipe.
  const ready = (message = "Ready.") => {
    const available = Boolean(programs && example.program);
    run.hidden = !available;
    if (!available) {
      status.textContent = "Running programs is unavailable in this build. Use the local recipe to run this example.";
      return;
    }
    run.disabled = !memory64 || (profile === "threads" && !crossOriginIsolated);
    status.textContent = !memory64
      ? "This browser does not support WebAssembly Memory64. Use a current Chrome or Firefox."
      : profile === "threads" && !crossOriginIsolated
      ? "Threads require a cross-origin-isolated page (COOP and COEP headers)."
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
  const showFiles = (files: { path: string; bytes: Uint8Array }[]) => {
    for (const url of downloadUrls) URL.revokeObjectURL(url);
    downloadUrls = [];
    downloads.replaceChildren();
    for (const file of files) {
      const url = URL.createObjectURL(new Blob([new Uint8Array(file.bytes)]));
      downloadUrls.push(url);
      const link = document.createElement("a");
      link.href = url;
      link.download = file.path.split("/").pop()!;
      link.textContent = `Download ${file.path}`;
      downloads.append(link);
    }
  };
  stop.addEventListener("click", () => finish("Stopped."));
  addEventListener("pagehide", () => {
    finish("Stopped.");
    showFiles([]);
  });
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
    if (profile === "threads") return { url: new URL(`${url}.js`, location.href).href };
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
    showFiles([]);
    outputSize = 0;
    status.textContent = "Loading...";
    request = new AbortController();
    const current = request;
    timer = setTimeout(() => finish("Loading timed out."), 25000);
    try {
      const [program, files] = await Promise.all([
        fetchProgram(current.signal),
        Promise.all(Array.from(input?.files ?? [], async (file) =>
          ({ name: file.name, bytes: await file.arrayBuffer() }))),
      ]);
      if (current !== request) return;
      clearTimeout(timer);
      status.textContent = "Running...";
      worker = profile === "threads"
        ? new Worker(new URL("./threaded-playground-worker.ts", import.meta.url),
            { type: "module" })
        : new Worker(new URL("./playground-worker.ts", import.meta.url),
            { type: "module" });
      worker.onmessage = ({ data }) => {
        if (data.kind === "exit") {
          showFiles(data.files ?? []);
          finish(`Finished (exit ${data.status}).`);
        }
        else if (data.kind === "error") finish(`Program failed: ${data.text}`);
        else write(data.kind, data.text);
      };
      worker.onerror = (event) => finish(`Program failed: ${event.message}`);
      timer = setTimeout(() => finish("Stopped after 10 seconds."), 10000);
      if ("url" in program) worker.postMessage(program);
      else worker.postMessage({ ...program, files, persistence },
        [program.wasm, ...files.map((file) => file.bytes)]);
    } catch (error) {
      if (current === request)
        finish(error instanceof Error ? error.message : String(error));
    }
  });
}
