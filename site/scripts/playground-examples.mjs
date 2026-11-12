// Select the gallery programs that can run in the browser playground.
// The site pages and the precompiled-program build share this selection.

// The browser has no host files, so programs that read input files cannot
// run there.
const needsHostFiles = /^(love\/files|power\/counting)$/;
// The wasm runtime has no threads, channels, dispatch, workers, or processes.
const needsHostRuntime =
  /\b(Thread|Channel|Dispatch|Job)\b|Pool\.start|File\.popen/;

// The reason a gallery program cannot run in the browser, if any.
export function nativeReason(entry, source) {
  if (!entry.example || entry.optional)
    return "This program needs a package, so it runs only with the native toolchain.";
  if (needsHostFiles.test(entry.example))
    return "This program reads files from disk, so it runs only with the native toolchain.";
  if (needsHostRuntime.test(source))
    return "This program uses threads, so it runs only with the native toolchain.";
  return undefined;
}

export function selectPlaygroundExamples(gallery, sourceFor) {
  return gallery.flatMap((entry) => {
    if (entry.language) return [];
    const source = entry.example && sourceFor(entry.example);
    if (!source || nativeReason(entry, source)) return [];
    return [{ id: entry.example, slide: entry.slide, source }];
  });
}

// A program that reads a directory under examples/data gets a copy of it in
// its in-memory filesystem. Gallery programs name it as example_data("dir").
export const embeddedData = (source) => [...new Set([
  ...(source.match(/examples\/data\/[\w-]+/g) ?? []),
  ...[...source.matchAll(/example_data\("([\w-]+)/g)]
    .map((match) => `examples/data/${match[1]}`),
])];
