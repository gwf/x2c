// A package import installs the packs its sources export in the order
// its include walk reaches them, so a pack may use what a pack an earlier
// include exports defines.
import "ordered";

int z = $ordered.z();
int a = $ordered.a();
