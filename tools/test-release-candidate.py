#!/usr/bin/env python3
"""Focused, offline release transport checks. Not an ordinary build gate."""
import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'candidate', Path(__file__).with_name('release-candidate.py'))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


class Candidates(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.candidate = self.directory / 'candidate'
        self.candidate.mkdir()
        self.manifest = {
            'schema': 1, 'source_repository': 'gwf/x2c',
            'source_sha': 'a' * 40, 'workflow_sha': 'b' * 40,
            'version': '1.2.3', 'run_id': '123', 'attempt': '1',
            'identity': 'candidate-' + 'a' * 40 + '-123-1'}
        rows = ['# x2c package index for x2c 1.2.3',
                '# name version kind platform url sha256']
        for name in sorted(c.inventory('1.2.3')):
            path = self.candidate / name
            if not name.endswith('.sha256'):
                path.write_bytes(name.encode())
        for name in sorted(c.inventory('1.2.3')):
            path = self.candidate / name
            if name.endswith('.sha256'):
                archive = name.removesuffix('.sha256')
                path.write_text(c.digest(self.candidate / archive) + '  ' + archive + '\n')
            if name.endswith('-native.tar.gz'):
                pkg, platform = name.removesuffix('-native.tar.gz').split('-', 1)
                rows.append(f'{pkg} 1 bundle {platform} '
                            f'{c.base(self.manifest, "staging")}/{name} {c.digest(path)}')
        text = '\n'.join(rows) + '\n'
        (self.candidate / 'index-staging.txt').write_text(text)
        (self.candidate / 'index-production.txt').write_text(c.index_variant(
            text, c.base(self.manifest, 'staging'), c.base(self.manifest, 'production')))
        self.freeze()

    def freeze(self):
        self.manifest['assets'] = {
            p.name: {'sha256': c.digest(p), 'size': p.stat().st_size}
            for p in sorted(self.candidate.iterdir()) if p.name != 'candidate.json'}
        (self.candidate / 'candidate.json').write_text(json.dumps(self.manifest))

    def sites(self):
        for destination in c.SITES:
            site = self.directory / destination
            site.mkdir()
            (site / 'index.html').write_text('<html>selected source</html>')
            installer = Path(__file__).resolve().parents[1] / 'site/public/install.sh'
            (site / 'install.sh').write_text(installer.read_text())
            c.site(argparse.Namespace(candidate=self.candidate,
                                      destination=destination, site_dir=site))

    def test_complete_candidate_and_promotion_bytes(self):
        self.assertEqual(c.verify(self.candidate)['identity'], self.manifest['identity'])
        self.sites()
        c.receipt(argparse.Namespace(candidate=self.candidate, destination='staging',
                                    run_url='https://github.com/gwf/x2c/actions/runs/123'))
        _, files = c.assets(self.candidate, 'production')
        self.assertEqual(c.digest(files['x2c-1.2.3-linux-x86_64.tar.gz']),
                         self.manifest['assets']['x2c-1.2.3-linux-x86_64.tar.gz']['sha256'])
        self.assertIn('/v1.2.3/', files['index.txt'].read_text())
        staging = (self.directory / 'staging/install.sh').read_text()
        self.assertIn('${X2C_RELEASE_TAG:-' + self.manifest['identity'] + '}', staging)
        self.assertIn('gwf/x2c-staging/releases/download', staging)

    def test_missing_archive_blocks_promotion(self):
        (self.candidate / 'torch-linux-x86_64-native.tar.gz').unlink()
        with self.assertRaisesRegex(ValueError, 'missing regular asset'):
            c.verify(self.candidate)

    def test_same_version_changed_bytes_are_not_accepted(self):
        (self.candidate / 'x2c-1.2.3-linux-x86_64.tar.gz').write_bytes(b'other candidate')
        with self.assertRaisesRegex(ValueError, 'mismatch'):
            c.verify(self.candidate)

    def test_wrong_candidate_selection(self):
        with self.assertRaisesRegex(ValueError, 'selected candidate'):
            c.verify(self.candidate, expected_identity='candidate-' + 'a' * 40 + '-124-1')

    def test_production_fallback_index_rejected(self):
        path = self.candidate / 'index-staging.txt'
        path.write_text(path.read_text().replace('gwf/x2c-staging', 'gwf/x2c'))
        self.freeze()
        with self.assertRaisesRegex(ValueError, 'index URL'):
            c.verify(self.candidate)

    def test_missing_matrix_in_manifest_rejected(self):
        del self.manifest['assets']['blis-linux-aarch64-native.tar.gz']
        (self.candidate / 'candidate.json').write_text(json.dumps(self.manifest))
        with self.assertRaisesRegex(ValueError, 'complete release matrix'):
            c.verify(self.candidate)

    def test_unsafe_manifest_name_rejected(self):
        self.manifest['assets']['../escape'] = {'size': 0, 'sha256': ''}
        (self.candidate / 'candidate.json').write_text(json.dumps(self.manifest))
        with self.assertRaisesRegex(ValueError, 'unsafe asset'):
            c.verify(self.candidate)

    def test_site_cannot_be_replaced_after_verification(self):
        self.sites()
        with self.assertRaisesRegex(ValueError, 'already frozen'):
            c.site(argparse.Namespace(candidate=self.candidate,
                                      destination='staging', site_dir=self.directory / 'staging'))
        (self.candidate / 'site-staging.tar.gz').write_bytes(b'different site')
        with self.assertRaisesRegex(ValueError, 'site receipt mismatch'):
            c.verify(self.candidate)

    def test_promotion_requires_staging_verification(self):
        self.sites()
        with self.assertRaisesRegex(ValueError, 'no staging verification'):
            c.assets(self.candidate, 'production')

    def test_failed_verification_attempt_does_not_poison_retry(self):
        self.sites()
        for attempt in ('1', '2'):
            c.receipt(argparse.Namespace(candidate=self.candidate, destination='staging',
                run_url='https://github.com/gwf/x2c/actions/runs/456', attempt=attempt))
        self.assertEqual(len(c.receipts(self.candidate, 'staging')), 2)
        def metadata(*args):
            return json.dumps({'conclusion': 'success' if args[-1].endswith('/2') else 'failure',
                               'event': 'workflow_dispatch',
                               'path': '.github/workflows/stage.yml'})
        with patch.object(c, 'run', side_effect=metadata):
            c.proof(self.candidate, 'staging')
        with patch.object(c, 'run', return_value=json.dumps({
                'conclusion': 'failure', 'event': 'workflow_dispatch',
                'path': '.github/workflows/stage.yml'})):
            with self.assertRaisesRegex(ValueError, 'no successful staging'):
                c.proof(self.candidate, 'staging')

    def test_restore_proof_never_requires_or_changes_main(self):
        self.sites()
        c.receipt(argparse.Namespace(candidate=self.candidate, destination='production',
            run_url='https://github.com/gwf/x2c/actions/runs/789', attempt='1'))
        with patch.object(c, 'run', return_value=json.dumps({
                'conclusion': 'success', 'event': 'workflow_dispatch',
                'path': '.github/workflows/promote.yml'})) as run:
            c.proof(self.candidate, 'production')
        self.assertEqual(run.call_count, 1)
        self.assertIn('/actions/runs/789/attempts/1', run.call_args.args[-1])

    def test_conflicting_upload_is_never_clobbered(self):
        self.sites()
        name = 'x2c-1.2.3-darwin-arm64.tar.gz'
        calls = []
        def fake_run(*args, **kwargs):
            calls.append(args)
            if args[:3] == ('gh', 'release', 'view'):
                return json.dumps({'assets': [{'name': name}, {'name': 'candidate.json'}]})
            if args[:3] == ('gh', 'release', 'download'):
                selected = args[args.index('--pattern') + 1]
                if selected == 'candidate.json':
                    (Path(args[-1]) / selected).write_bytes(
                        (self.candidate / selected).read_bytes())
                else:
                    (Path(args[-1]) / selected).write_bytes(b'conflicting existing bytes')
            return ''
        with patch.object(c, 'run', side_effect=fake_run), \
                patch.object(c.subprocess, 'run') as probe:
            probe.return_value.returncode = 0
            with self.assertRaisesRegex(ValueError, 'refusing to replace published asset'):
                c.publish(argparse.Namespace(candidate=self.candidate,
                          repository='gwf/x2c-staging', destination='staging'))
        self.assertFalse(any('--clobber' in call for call in calls))
        self.assertFalse(any(call[:3] == ('gh', 'release', 'edit') for call in calls))


if __name__ == '__main__':
    unittest.main()
