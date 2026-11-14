import manifest from "../../../examples/shootout/benchmarks.json";

const descriptions: Record<string, string> = {
  nbody: "Advance five bodies under mutual gravity, then report the system's energy.",
  spectralnorm: "Estimate an implicit matrix's spectral norm through repeated matrix-vector products.",
  fannkuchredux: "Enumerate permutations, reverse prefixes, and report the checksum and largest flip count.",
  mandelbrot: "Test points in the complex plane and write a binary PBM bitmap.",
  fasta: "Generate repeated and random DNA sequences with the prescribed probability distributions.",
  knucleotide: "Count DNA fragments in growing maps and report frequencies and requested fragment counts.",
  revcomp: "Read FASTA records and write each sequence's reverse complement.",
  binarytrees: "Allocate and check complete trees, including every leaf, at a range of depths.",
  regexredux: "Count regular-expression matches and apply an ordered chain of substitutions to DNA input.",
  pidigits: "Generate decimal digits of pi with the prescribed arbitrary-precision spigot algorithm.",
};

export const shootoutExamples = manifest.benchmarks.map(problem => ({
  name: problem.name,
  label: problem.title,
  anchor: problem.name,
  description: descriptions[problem.name],
  specification: problem.description_url,
  references: Object.keys(problem.references),
}));

export const shootoutNavigation = [
  { label: "Runtime by problem", anchor: "charts" },
  { label: "Data representation", anchor: "representation" },
  { label: "Buffered work", anchor: "buffers" },
  { label: "Source-size tradeoffs", anchor: "source-size" },
  { label: "Other languages", anchor: "languages" },
  { label: "Measurement scope", anchor: "method" },
  { label: "Complete programs", anchor: "programs" },
  ...shootoutExamples.map(({ label, anchor }) => ({ label, anchor })),
];
