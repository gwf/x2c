self.onmessage = async ({ data }) => {
  const loaderUrl = URL.createObjectURL(new Blob([data.loader], {
    type: "text/javascript",
  }));
  try {
    const { default: createModule } = await import(/* @vite-ignore */ loaderUrl);
    const wasmBinary = Uint8Array.from(atob(data.wasm), (c) => c.charCodeAt(0));
    await createModule({
      instantiateWasm: (imports: WebAssembly.Imports,
        receive: (instance: WebAssembly.Instance, module: WebAssembly.Module) => void) => {
        WebAssembly.instantiate(wasmBinary, imports).then(({ instance, module }) =>
          receive(instance, module), (error) =>
          self.postMessage({ kind: "error", text: String(error) }));
        return {};
      },
      locateFile: (path: string) => path,
      print: (text: string) => self.postMessage({ kind: "stdout", text }),
      printErr: (text: string) => self.postMessage({ kind: "stderr", text }),
      onExit: (status: number) => self.postMessage({ kind: "exit", status }),
      onAbort: (reason: string) => self.postMessage({ kind: "error", text: reason }),
    });
  } catch (error) {
    if (error && typeof error === "object" && "name" in error && error.name === "ExitStatus")
      self.postMessage({ kind: "exit", status: (error as { status: number }).status });
    else self.postMessage({ kind: "error", text: String(error) });
  } finally {
    URL.revokeObjectURL(loaderUrl);
  }
};
