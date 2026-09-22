#!/usr/bin/env python3
"""Assemble and transport immutable release candidates; never build at promotion.

The inactive workflows in etc/release/ own authorization and verification jobs.
This helper owns archive identity, destination metadata and immutable uploads.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

PLATFORMS = ('darwin-arm64', 'darwin-x86_64', 'linux-x86_64', 'linux-aarch64')
PACKAGES = ('pcre2', 'yyjson', 'libcurl', 'termbox2', 'libuv', 'blis')
REPOSITORIES = {'staging': 'gwf/x2c-staging', 'production': 'gwf/x2c'}
SITES = {'staging': 'https://staging.x2c-lang.dev',
         'production': 'https://x2c-lang.dev'}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True,
                          **kwargs).stdout.strip()


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    data = json.dumps(value, indent=2, sort_keys=True) + '\n'
    path = Path(path)
    if path.exists() and path.read_text() != data:
        raise ValueError(f'refusing to replace {path}')
    path.write_text(data)


def sha(value):
    if not re.fullmatch(r'[0-9a-f]{40}', value):
        raise ValueError('source and workflow revisions must be full Git SHAs')
    return value


def identity(value):
    if not re.fullmatch(r'candidate-[0-9a-f]{40}-[0-9]+-[0-9]+', value):
        raise ValueError('invalid candidate identity')
    return value


def base(manifest, destination):
    tag = (manifest['identity'] if destination == 'staging'
           else 'v' + manifest['version'])
    return f'https://github.com/{REPOSITORIES[destination]}/releases/download/{tag}'


def inventory(version):
    names = {f'x2c-{version}-{p}.tar.gz' for p in PLATFORMS}
    names |= {name + '.sha256' for name in names}
    names |= {f'{pkg}-{p}-native.tar.gz'
              for pkg in PACKAGES for p in PLATFORMS}
    names |= {'torch-darwin-arm64-native.tar.gz',
              'torch-linux-x86_64-native.tar.gz'}
    return names


def index_variant(text, old_base, new_base):
    lines = []
    for line in text.splitlines():
        if not line or line.startswith('#'):
            lines.append(line)
            continue
        fields = line.split()
        if len(fields) != 6 or not fields[4].startswith(old_base + '/'):
            raise ValueError('index row outside candidate archive namespace')
        fields[4] = new_base + fields[4][len(old_base):]
        lines.append(' '.join(fields))
    return '\n'.join(lines) + '\n'


def assemble(args):
    sha(args.source_sha)
    sha(args.workflow_sha)
    source = Path(args.source).resolve()
    if run('git', '-C', str(source), 'rev-parse', 'HEAD') != args.source_sha:
        raise ValueError('source checkout does not match selected SHA')
    candidate = Path(args.output)
    candidate.mkdir(parents=True, exist_ok=False)
    built = Path(args.built)
    compilers = sorted(built.glob('compiler-*/x2c-*.tar.gz'))
    versions = set()
    for archive in compilers:
        match = re.fullmatch(r'x2c-([0-9]+\.[0-9]+\.[0-9]+)-(.+)\.tar\.gz',
                             archive.name)
        if not match or match[2] not in PLATFORMS:
            raise ValueError(f'unexpected compiler archive: {archive}')
        versions.add(match[1])
        for path in (archive, Path(str(archive) + '.sha256')):
            target = candidate / path.name
            if target.exists():
                raise ValueError(f'duplicate archive: {path.name}')
            shutil.copyfile(path, target)
    if len(compilers) != 4 or len(versions) != 1:
        raise ValueError('need all four compiler archives with one version')
    version = versions.pop()
    manifest = {'schema': 1, 'source_repository': 'gwf/x2c',
                'source_sha': args.source_sha, 'workflow_sha': args.workflow_sha,
                'version': version, 'run_id': args.run_id,
                'attempt': args.attempt,
                'identity': identity(f'candidate-{args.source_sha}-'
                                     f'{args.run_id}-{args.attempt}')}
    bundles = sorted(built.glob('bundle-*/*-native.tar.gz'))
    if len(bundles) != 26:
        raise ValueError('need all 26 package bundle artifacts')
    x2c = str(Path(args.x2c).resolve())
    if run(x2c, '--version') != f'x2c {version}':
        raise ValueError('index generator compiler version differs')
    run(x2c, 'script', str(source / 'tools/gen-package-index'),
        '--output', str(candidate.resolve()), '--base', base(manifest, 'staging'),
        '--x2c-version', f'x2c {version}',
        '--package-dir', str(source / 'examples/packages'),
        '--package-dir', str(source / 'packages'),
        *(str(p.resolve()) for p in bundles))
    (candidate / 'index.txt').rename(candidate / 'index-staging.txt')
    staging = (candidate / 'index-staging.txt').read_text()
    (candidate / 'index-production.txt').write_text(index_variant(
        staging, base(manifest, 'staging'), base(manifest, 'production')))
    missing = inventory(version) - {p.name for p in candidate.iterdir()}
    if missing:
        raise ValueError(f'missing matrix assets: {sorted(missing)}')
    manifest['assets'] = {p.name: {'sha256': digest(p), 'size': p.stat().st_size}
                          for p in sorted(candidate.iterdir())}
    write(candidate / 'candidate.json', manifest)
    verify(candidate)
    print(manifest['identity'])


def verify(candidate, expected_sha=None, expected_identity=None,
           require_staging=False):
    candidate = Path(candidate)
    manifest = read(candidate / 'candidate.json')
    sha(manifest['source_sha'])
    sha(manifest['workflow_sha'])
    identity(manifest['identity'])
    if manifest['source_repository'] != 'gwf/x2c' or manifest['schema'] != 1:
        raise ValueError('unexpected manifest source/schema')
    expected_id = (f"candidate-{manifest['source_sha']}-"
                   f"{manifest['run_id']}-{manifest['attempt']}")
    if manifest['identity'] != expected_id:
        raise ValueError('candidate identity does not match provenance')
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', manifest['version']):
        raise ValueError('invalid compiler version')
    if expected_sha and manifest['source_sha'] != expected_sha:
        raise ValueError('candidate source differs from selected source')
    if expected_identity and manifest['identity'] != expected_identity:
        raise ValueError('candidate identity differs from selected candidate')
    required = inventory(manifest['version']) | {'index-staging.txt', 'index-production.txt'}
    if not required <= manifest['assets'].keys():
        raise ValueError('candidate lacks the complete release matrix')
    for name, record in manifest['assets'].items():
        if Path(name).name != name or name.startswith('.'):
            raise ValueError('unsafe asset name')
        path = candidate / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'missing regular asset {name}')
        if path.stat().st_size != record['size'] or digest(path) != record['sha256']:
            raise ValueError(f'asset digest/size mismatch: {name}')
    for platform in PLATFORMS:
        name = f"x2c-{manifest['version']}-{platform}.tar.gz"
        checksum = (candidate / (name + '.sha256')).read_text().split()
        if len(checksum) != 2 or checksum[0] != digest(candidate / name) or \
                checksum[1].lstrip('*') != name:
            raise ValueError(f'compiler checksum sidecar mismatch: {name}')
    for destination, filename in [('staging', 'index-staging.txt'),
                                  ('production', 'index-production.txt')]:
        text = (candidate / filename).read_text()
        if text.splitlines()[0] != \
                f"# x2c package index for x2c {manifest['version']}":
            raise ValueError('index version differs from candidate')
        seen = set()
        for line in text.splitlines():
            if not line or line.startswith('#'):
                continue
            fields = line.split()
            if len(fields) != 6:
                raise ValueError('invalid index row')
            name = fields[4].removeprefix(base(manifest, destination) + '/')
            if name not in manifest['assets'] or fields[5] != \
                    manifest['assets'][name]['sha256']:
                raise ValueError('index URL/digest differs from candidate')
            if name in seen:
                raise ValueError('duplicate index archive')
            seen.add(name)
        packages = {n for n in manifest['assets']
                    if n.endswith(('-native.tar.gz', '-source.tar.gz'))}
        if seen != packages:
            raise ValueError('index does not cover every package archive')
    if index_variant((candidate / 'index-staging.txt').read_text(),
                     base(manifest, 'staging'), base(manifest, 'production')) != \
            (candidate / 'index-production.txt').read_text():
        raise ValueError('destination indexes differ beyond URLs')
    for destination in SITES:
        receipt = candidate / f'site-{destination}.json'
        if receipt.exists():
            data = read(receipt)
            if data['manifest_sha256'] != digest(candidate / 'candidate.json') or \
                    data['sha256'] != digest(candidate / f'site-{destination}.tar.gz'):
                raise ValueError(f'{destination} site receipt mismatch')
    if require_staging:
        receipts(candidate, 'staging')
    return manifest


def site(args):
    candidate = Path(args.candidate)
    manifest = verify(candidate)
    directory = Path(args.site_dir)
    if not (directory / 'index.html').is_file():
        raise ValueError('site directory must contain the built homepage')
    destination = args.destination
    archive = candidate / f'site-{destination}.tar.gz'
    if archive.exists():
        raise ValueError('site output already frozen; use a new candidate')
    (directory / 'packages').mkdir(exist_ok=True)
    shutil.copyfile(candidate / ('index-staging.txt' if destination == 'staging'
                                else 'index-production.txt'),
                    directory / 'packages/index.txt')
    (directory / 'x2c-version.txt').write_text(manifest['version'] + '\n')
    write(directory / 'release-candidate.json', {
        'identity': manifest['identity'], 'source_sha': manifest['source_sha'],
        'manifest_sha256': digest(candidate / 'candidate.json'),
        'destination': destination, 'version': manifest['version']})
    (directory / 'CNAME').write_text(SITES[destination].split('://')[1] + '\n')
    installer = directory / 'install.sh'
    text = installer.read_text()
    if destination == 'staging':
        text = text.replace('https://github.com/gwf/x2c/releases/download',
                            'https://github.com/gwf/x2c-staging/releases/download')
        text = text.replace('https://x2c-lang.dev', SITES['staging'])
        old = '${X2C_RELEASE_TAG:-v$version}'
        if text.count(old) != 1:
            raise ValueError('installer has no unique candidate tag default')
        text = text.replace(old, '${X2C_RELEASE_TAG:-' + manifest['identity'] + '}')
        installer.write_text(text)
    run('tar', '-czf', str(archive.resolve()), '-C', str(directory.resolve()), '.')
    write(candidate / f'site-{destination}.json', {
        'destination': destination, 'site_url': SITES[destination], 'site_base': '/',
        'manifest_sha256': digest(candidate / 'candidate.json'),
        'sha256': digest(archive)})


def receipts(candidate, destination):
    result = []
    for path in sorted(candidate.glob(f'verified-{destination}-*.json')):
        data = read(path)
        if data['manifest_sha256'] != digest(candidate / 'candidate.json') or \
                data['site_sha256'] != digest(candidate / f'site-{destination}.tar.gz') or \
                data['platforms'] != list(PLATFORMS):
            raise ValueError(f'incomplete or mismatched {destination} verification')
        match = re.fullmatch(r'https://github.com/gwf/x2c/actions/runs/([0-9]+)',
                             data['run_url'])
        if not match or not re.fullmatch(r'[0-9]+', str(data['attempt'])) or \
                path.name != f"verified-{destination}-{match[1]}-{data['attempt']}.json":
            raise ValueError('verification receipt does not identify its workflow attempt')
        result.append((path, data))
    if not result:
        raise ValueError(f'no {destination} verification receipts')
    return result


def receipt(args):
    candidate = Path(args.candidate)
    verify(candidate)
    match = re.fullmatch(r'https://github.com/gwf/x2c/actions/runs/([0-9]+)',
                         args.run_url)
    attempt = getattr(args, 'attempt', '1')
    if not match or not re.fullmatch(r'[0-9]+', str(attempt)):
        raise ValueError('receipt needs a source workflow run URL and attempt')
    # Only a successful matrix-dependent job calls this. A retry adds proof,
    # leaving receipts from interrupted publication attempts intact.
    write(candidate / f'verified-{args.destination}-{match[1]}-{attempt}.json', {
        'manifest_sha256': digest(candidate / 'candidate.json'),
        'site_sha256': digest(candidate / f'site-{args.destination}.tar.gz'),
        'platforms': list(PLATFORMS), 'run_url': args.run_url, 'attempt': str(attempt)})


def assets(candidate, destination):
    manifest = verify(candidate, require_staging=(destination == 'production'))
    result = {name: candidate / name for name in manifest['assets']}
    # Preserve both named index variants verbatim; index.txt is only an alias.
    # The same manifest therefore verifies assets at either destination.
    result['index.txt'] = candidate / f'index-{destination}.txt'
    result['candidate.json'] = candidate / 'candidate.json'
    for dest in SITES:
        for suffix in ('json', 'tar.gz'):
            name = f'site-{dest}.{suffix}'
            if not (candidate / name).is_file():
                raise ValueError('both destination sites must be retained before publishing')
            result[name] = candidate / name
        if list(candidate.glob(f'verified-{dest}-*.json')):
            for path, _ in receipts(candidate, dest):
                result[path.name] = path
    return manifest, result


def publish(args):
    candidate = Path(args.candidate)
    if args.repository != REPOSITORIES[args.destination]:
        raise ValueError('unexpected destination repository')
    manifest, files = assets(candidate, args.destination)
    tag = manifest['identity'] if args.destination == 'staging' else 'v' + manifest['version']
    if args.destination == 'production':
        guard(candidate)
    existing = subprocess.run(['gh', 'release', 'view', tag, '--repo', args.repository,
                               '--json', 'tagName'], capture_output=True, text=True)
    if existing.returncode:
        command = ['gh', 'release', 'create', tag, '--repo', args.repository,
                   '--draft', '--title', tag, '--notes',
                   f"Source gwf/x2c@{manifest['source_sha']}; candidate {manifest['identity']}."]
        if args.destination == 'staging':
            command.append('--prerelease')
        else:
            command.append('--verify-tag')
        run(*command)
    # Preflight all existing bytes before uploading anything. In particular a
    # reused version must not gain assets from a different candidate.
    remote = json.loads(run('gh', 'release', 'view', tag, '--repo', args.repository,
                            '--json', 'assets'))['assets']
    remote_names = {asset['name'] for asset in remote}
    if remote_names and 'candidate.json' not in remote_names:
        raise ValueError('existing release has no candidate provenance')
    with tempfile.TemporaryDirectory(prefix='x2c-assets-') as temp:
        for name in sorted(remote_names & files.keys()):
            run('gh', 'release', 'download', tag, '--repo', args.repository,
                '--pattern', name, '--dir', temp)
            if digest(Path(temp) / name) != digest(files[name]):
                raise ValueError(f'refusing to replace published asset {name}')
        # Manifest first makes even an interrupted first upload identifiable.
        ordered = ['candidate.json'] + sorted(files.keys() - {'candidate.json'})
        for name in ordered:
            if name in remote_names:
                continue
            path = files[name]
            target = Path(temp) / name
            shutil.copyfile(path, target)
            run('gh', 'release', 'upload', tag, str(target), '--repo', args.repository)
            target.unlink()
            run('gh', 'release', 'download', tag, '--repo', args.repository,
                '--pattern', name, '--dir', temp)
            if digest(target) != digest(path):
                raise ValueError(f'uploaded asset differs: {name}')
    if args.destination == 'staging':
        run('gh', 'release', 'edit', tag, '--repo', args.repository,
            '--draft=false', '--prerelease', '--latest=false')
    # Production visibility is the workflow's next explicit, recoverable step.
    print(tag)


def fetch(args):
    if args.repository != REPOSITORIES['staging']:
        raise ValueError('candidates are fetched from the staging repository')
    identity(args.identity)
    directory = Path(args.output)
    directory.mkdir(parents=True, exist_ok=False)
    run('gh', 'release', 'download', args.identity, '--repo', args.repository,
        '--dir', str(directory))
    verify(directory, expected_identity=args.identity)


def proof(candidate, destination):
    verify(candidate)
    successful = False
    workflow = 'stage' if destination == 'staging' else 'promote'
    for _, proof in receipts(candidate, destination):
        run_id = proof['run_url'].rsplit('/', 1)[-1]
        metadata = json.loads(run('gh', 'api',
            f"repos/gwf/x2c/actions/runs/{run_id}/attempts/{proof['attempt']}"))
        if metadata['conclusion'] == 'success' and \
                metadata['event'] == 'workflow_dispatch' and \
                metadata['path'] == f'.github/workflows/{workflow}.yml':
            successful = True
    if not successful:
        raise ValueError(f'no successful {destination} workflow attempt proves this candidate')


def guard(candidate):
    manifest = verify(candidate, require_staging=True)
    proof(candidate, 'staging')
    repo = 'repos/gwf/x2c'
    main = json.loads(run('gh', 'api', f'{repo}/git/ref/heads/main'))['object']['sha']
    obj = json.loads(run('gh', 'api', f"{repo}/git/ref/tags/v{manifest['version']}"))['object']
    while obj['type'] == 'tag':
        obj = json.loads(run('gh', 'api', f"{repo}/git/tags/{obj['sha']}"))['object']
    if main != manifest['source_sha'] or obj['type'] != 'commit' or obj['sha'] != main:
        raise ValueError('Gary must advance main and tag to the selected source before promotion')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    p = commands.add_parser('assemble')
    for name in ('built', 'source', 'output', 'source-sha', 'workflow-sha',
                 'run-id', 'attempt', 'x2c'):
        p.add_argument('--' + name, required=True)
    p = commands.add_parser('fetch')
    for name in ('repository', 'identity', 'output'):
        p.add_argument('--' + name, required=True)
    for name in ('verify', 'site', 'publish', 'receipt', 'guard', 'proof'):
        p = commands.add_parser(name)
        p.add_argument('--candidate', required=True)
        if name == 'verify':
            p.add_argument('--source-sha')
            p.add_argument('--identity')
            p.add_argument('--require-staging', action='store_true')
        if name in ('site', 'publish', 'receipt', 'proof'):
            p.add_argument('--destination', choices=SITES, required=True)
        if name == 'site':
            p.add_argument('--site-dir', required=True)
        if name == 'publish':
            p.add_argument('--repository', required=True)
        if name == 'receipt':
            p.add_argument('--run-url', required=True)
            p.add_argument('--attempt', default=os.environ.get('GITHUB_RUN_ATTEMPT', '1'))
    args = parser.parse_args()
    if args.command == 'verify':
        manifest = verify(args.candidate, args.source_sha, args.identity,
                          args.require_staging)
        print(manifest['identity'])
    elif args.command == 'guard':
        guard(Path(args.candidate))
    elif args.command == 'proof':
        proof(Path(args.candidate), args.destination)
    else:
        globals()[args.command](args)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f'release-candidate: {error}')
