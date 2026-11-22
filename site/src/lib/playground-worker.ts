type InputFile = { name: string; bytes: ArrayBuffer };
type Program = {
  loader: string;
  wasm: ArrayBuffer;
  files?: InputFile[];
  persistence?: string;
  profile?: "tasks";
};

type VirtualFS = {
  mkdirTree(path: string): void;
  mount(type: unknown, options: object, path: string): void;
  syncfs(populate: boolean, done: (error?: Error) => void): void;
  writeFile(path: string, data: Uint8Array): void;
  readFile(path: string): Uint8Array;
  readdir(path: string): string[];
  stat(path: string): { mode: number };
  isDir(mode: number): boolean;
};

type Runtime = {
  FS: VirtualFS;
  IDBFS: unknown;
  addRunDependency(name: string): void;
  removeRunDependency(name: string): void;
  noInitialRun?: boolean;
  x2cMainResult?: number;
  _emscripten_force_exit?: (status: number) => void;
};

const sync = (fs: VirtualFS, populate: boolean) =>
  new Promise<void>((resolve, reject) =>
    fs.syncfs(populate, (error) => error ? reject(error) : resolve()));

function outputs(fs: VirtualFS) {
  const found: { path: string; bytes: Uint8Array }[] = [];
  const visit = (path: string) => {
    for (const name of fs.readdir(path)) {
      if (name === "." || name === "..") continue;
      const child = `${path}/${name}`;
      if (fs.isDir(fs.stat(child).mode)) visit(child);
      else found.push({ path: child.slice("/output/".length),
        bytes: fs.readFile(child) });
    }
  };
  visit("/output");
  return found;
}

async function run(data: Program) {
  const loaderUrl = URL.createObjectURL(new Blob([data.loader], {
    type: "text/javascript",
  }));
  try {
    const { default: createModule } = await import(/* @vite-ignore */ loaderUrl);
    const wasmBinary = new Uint8Array(data.wasm);
    const files = data.files ?? [];
    if (files.some((file) => !file.name || file.name === "." ||
        file.name === ".." || /[\\/]/.test(file.name)))
      throw new Error("Invalid input filename.");
    const args = files.map((file, index) => `/input/${index}/${file.name}`);
    let loadError: Error | undefined;
    let exitStatus: number | undefined;
    const module = await createModule({
      ...(args.length ? { arguments: args } : {}),
      preRun: [(runtime: Runtime) => {
        const fs = runtime.FS;
        if (!fs) {
          if (files.length || data.persistence)
            throw new Error("This WebAssembly build has no filesystem.");
          return;
        }
        fs.mkdirTree("/output");
        files.forEach((file, index) => {
          fs.mkdirTree(`/input/${index}`);
          fs.writeFile(args[index], new Uint8Array(file.bytes));
        });
        if (data.persistence) {
          fs.mkdirTree(`/persistent/${data.persistence}`);
          fs.mount(runtime.IDBFS, {},
            `/persistent/${data.persistence}`);
          runtime.addRunDependency("persistent-files");
          fs.syncfs(true, (error) => {
            loadError = error;
            if (error) runtime.noInitialRun = true;
            runtime.removeRunDependency("persistent-files");
          });
        }
      }],
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
      onExit: (status: number) => { exitStatus = status; },
    }) as Runtime;
    if (loadError) throw loadError;
    if (data.profile === "tasks" &&
        !Number.isInteger(module.x2cMainResult))
      throw new Error("Task program returned without a main result.");
    if (module.x2cMainResult !== undefined && exitStatus === undefined) {
      try {
        module._emscripten_force_exit!(module.x2cMainResult);
      } catch (error) {
        if (!error || typeof error !== "object" || !("name" in error) ||
            error.name !== "ExitStatus") throw error;
      }
    }
    const filesOut = module.FS ? outputs(module.FS) : [];
    const status = exitStatus ?? module.x2cMainResult ?? 0;
    if (data.persistence && status === 0) await sync(module.FS, false);
    self.postMessage({ kind: "exit", status, files: filesOut });
  } catch (error) {
    if (error && typeof error === "object" && "name" in error && error.name === "ExitStatus") {
      const status = (error as { status: number }).status;
      self.postMessage({ kind: "exit", status });
    } else {
      self.postMessage({ kind: "error", text: String(error) });
    }
  } finally {
    URL.revokeObjectURL(loaderUrl);
  }
}

self.onmessage = ({ data }: MessageEvent<Program>) => {
  if (!data.persistence) {
    void run(data);
    return;
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(data.persistence) || !navigator.locks) {
    self.postMessage({ kind: "error", text: "Persistent storage is unavailable." });
    return;
  }
  void navigator.locks.request(`x2c-files-${data.persistence}`,
    { mode: "exclusive" }, () => run(data))
    .catch((error) =>
      self.postMessage({ kind: "error", text: String(error) }));
};
