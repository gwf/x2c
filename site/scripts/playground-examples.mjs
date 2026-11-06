// Select the gallery programs that can run in the browser playground.
// The site pages and the precompiled-program build share this selection.

// The browser has no host files, so programs that read input files cannot
// run there.
const needsHostFiles = /^(love\/files|power\/counting)$/;
// The wasm runtime has no threads, channels, dispatch, workers, or processes.
const needsHostRuntime =
  /\b(Thread|Channel|Dispatch|Job)\b|Pool\.start|File\.popen/;

export function selectPlaygroundExamples(gallery, sourceFor) {
  return gallery.flatMap((entry) => {
    if (!entry.example || entry.optional || entry.language) return [];
    const source = sourceFor(entry.example);
    if (!source || needsHostFiles.test(entry.example) ||
        needsHostRuntime.test(source)) return [];
    return [{ id: entry.example, slide: entry.slide, source }];
  });
}

// A program that reads a directory under examples/data gets a copy of it in
// its in-memory filesystem.
export const embeddedData = (source) =>
  [...new Set(source.match(/examples\/data\/[\w-]+/g) ?? [])];
