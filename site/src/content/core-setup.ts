import { destination } from "../../release-destination.mjs";

export const coreSetup = `git clone https://github.com/gwf/x2c.git
cd x2c
git checkout ${destination.releaseRef === "main" ? "main" :
  `--detach ${destination.releaseRef}`}
make build-safe`;

export const corePrerequisites =
  "You need Git, a GCC- or Clang-compatible C compiler, ar, GNU Make, and Bash.";
