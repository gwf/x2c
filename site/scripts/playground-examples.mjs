// Select the gallery programs that can run in the browser playground.
// The site pages and the precompiled-program build share this selection.

// The default wasm profile cannot start threads or native processes.
const needsHostRuntime =
  /\b(Thread|Channel|Dispatch|Job)\b|Pool\.start|File\.popen/;
const threadedIds = new Set([
  "power/threads", "power/channels",
  "tours/essentials/threads", "tours/language/threads",
]);

// Source-backed examples inside examples/ use the same IDs as generated ones.
export function galleryExampleId(entry) {
  return entry.example ?? entry.source?.match(/^examples\/(.+)\.x$/)?.[1];
}

// The reason a gallery program cannot run in the browser, if any.
export function nativeReason(entry, source) {
  const id = galleryExampleId(entry);
  if (!id || entry.optional)
    return "This program needs a package, so it runs only with the native toolchain.";
  if (needsHostRuntime.test(source))
    return "This program uses threads, so it runs only with the native toolchain.";
  return undefined;
}

export function selectPlaygroundExamples(gallery, sourceFor, profile = "default") {
  return gallery.flatMap((entry) => {
    if (entry.language) return [];
    const id = galleryExampleId(entry);
    const source = id && sourceFor(id);
    if (!source) return [];
    if (profile === "threads" ? !threadedIds.has(id) : nativeReason(entry, source))
      return [];
    return [{ id, slide: entry.slide, source }];
  });
}

// A program that reads a directory under examples/data gets a copy of it in
// its in-memory filesystem. Gallery programs name it as example_data("dir").
export const embeddedData = (source) => [...new Set([
  ...(source.match(/examples\/data\/[\w-]+/g) ?? []),
  ...[...source.matchAll(/example_data\("([\w-]+)/g)]
    .map((match) => `examples/data/${match[1]}`),
])];
