// A package import installs the macro imports the package's sources
// export; an import a source does not export stays in the package.
import "tally";

int six = $tally.six();
int hidden = $tally.hidden();
