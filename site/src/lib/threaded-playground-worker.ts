// Import the published loader by URL so Emscripten's pthread workers can
// import the same module and share its WebAssembly memory.
self.onmessage = async ({ data }: MessageEvent<{ url: string }>) => {
  if (!crossOriginIsolated) {
    self.postMessage({ kind: "error",
      text: "Threads require a cross-origin-isolated page (COOP and COEP headers)." });
    return;
  }
  try {
    const url = new URL(data.url, self.location.href);
    const { default: createModule } = await import(/* @vite-ignore */ url.href);
    await createModule({
      print: (text: string) => self.postMessage({ kind: "stdout", text }),
      printErr: (text: string) => self.postMessage({ kind: "stderr", text }),
      onExit: (status: number) => self.postMessage({ kind: "exit", status }),
      onAbort: (reason: string) => self.postMessage({ kind: "error", text: reason }),
    });
  } catch (error) {
    if (error && typeof error === "object" && "name" in error &&
      error.name === "ExitStatus")
      self.postMessage({ kind: "exit", status: (error as { status: number }).status });
    else self.postMessage({ kind: "error", text: String(error) });
  }
};
