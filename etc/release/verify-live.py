#!/usr/bin/env python3
"""Verify one platform using immutable candidate metadata and live endpoints."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile


def download(url, path):
    subprocess.run(["curl", "-fsSL", "--retry", "3", url, "-o", str(path)], check=True)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--destination", choices=["staging", "production"], required=True)
    args = parser.parse_args()
    import re
    if not re.fullmatch(r"candidate-[0-9a-f]{40}-[0-9]+-[0-9]+", args.identity):
        parser.error("invalid candidate identity")
    candidate_url = f"https://github.com/gwf/x2c-staging/releases/download/{args.identity}"
    site = "https://staging.x2c-lang.dev" if args.destination == "staging" else "https://x2c-lang.dev"
    target = platform.system().lower() + "-" + platform.machine()
    with tempfile.TemporaryDirectory(prefix="x2c-live-") as directory:
        work = Path(directory)
        for name in ("candidate.json", f"site-{args.destination}.json",
                     f"site-{args.destination}.tar.gz"):
            download(f"{candidate_url}/{name}", work / name)
        manifest = json.loads((work / "candidate.json").read_text())
        receipt = json.loads((work / f"site-{args.destination}.json").read_text())
        assert manifest["identity"] == args.identity
        assert receipt["manifest_sha256"] == digest(work / "candidate.json")
        archive = work / f"site-{args.destination}.tar.gz"
        assert receipt["sha256"] == digest(archive)
        # Compare live pointers and installer with the retained exact site.
        with tarfile.open(archive) as tar:
            members = {m.name.removeprefix("./"): m for m in tar.getmembers() if m.isfile()}
            for name in ("install.sh", "x2c-version.txt", "packages/index.txt",
                         "release-candidate.json"):
                live = work / Path(name).name
                download(f"{site}/{name}", live)
                assert live.read_bytes() == tar.extractfile(members[name]).read(), name
        version = manifest["version"]
        tag = args.identity if args.destination == "staging" else "v" + version
        repo = "gwf/x2c-staging" if args.destination == "staging" else "gwf/x2c"
        releases = f"https://github.com/{repo}/releases/download"
        compiler_name = f"x2c-{version}-{target}.tar.gz"
        download(f"{releases}/{tag}/{compiler_name}", work / compiler_name)
        assert digest(work / compiler_name) == manifest["assets"][compiler_name]["sha256"]
        # The live index is byte-identical to the candidate variant. Every
        # selected URL/digest must also bind to the invariant asset manifest.
        for line in (work / "index.txt").read_text().splitlines():
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            name = fields[4].rsplit("/", 1)[-1]
            assert fields[4] == f"{releases}/{tag}/{name}"
            assert fields[5] == manifest["assets"][name]["sha256"]
        prefix = work / "prefix"
        env = dict(os.environ, X2C_PREFIX=str(prefix), X2C_VERSION="latest",
                   X2C_RELEASES=releases, X2C_VERSION_URL=f"{site}/x2c-version.txt",
                   X2C_RELEASE_TAG=tag)
        defaults = {key: value for key, value in os.environ.items()
                    if key not in ("X2C_RELEASES", "X2C_VERSION_URL", "X2C_RELEASE_TAG")}
        defaults.update(X2C_PREFIX=str(prefix), X2C_VERSION="latest")
        subprocess.run(["sh", str(work / "install.sh")], env=defaults, check=True)
        subprocess.run(["sh", str(work / "install.sh"), "--version", version],
                       env=env, check=True)
        x2c = str(prefix / "bin/x2c")
        reported = subprocess.check_output([x2c, "--version"], text=True).strip()
        assert reported == "x2c " + version
        smoke = prefix / "examples/foreach.x"
        subprocess.run([x2c, "run", str(smoke)], check=True, cwd=work)
        packages = [("pcre2", "parse-log.x")]
        if target in ("darwin-arm64", "linux-x86_64"):
            packages.append(("torch", "fit-line.x"))
        for package, example in packages:
            subprocess.run([x2c, "install", "-q", "--index",
                            f"{site}/packages/index.txt", package], check=True, cwd=work)
            source = work / example
            download(f"https://raw.githubusercontent.com/gwf/x2c/{manifest['source_sha']}"
                     f"/packages/{package}/examples/{example}", source)
            subprocess.run([x2c, "build", "-q", "--output", package, example],
                           check=True, cwd=work)
            subprocess.run([str(work / package)], check=True, cwd=work)
        print(f"verified {args.identity} {args.destination} {target}")


if __name__ == "__main__":
    main()
