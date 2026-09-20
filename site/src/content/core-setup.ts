import { destination } from "../../release-destination.mjs";

export const coreSetup = `git clone https://github.com/gwf/x2c.git
cd x2c${destination.sourceRef === "main" ? "" :
  `\ngit checkout --detach ${destination.sourceRef}`}
make build-safe`;

export const corePrerequisites =
  "You need a GCC- or Clang-compatible C compiler, ar, GNU Make, Python 3, and Bash.";
