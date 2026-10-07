"""Synthetic release-gate tests. No real keys, recordings or transcripts."""
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
import sys
import tarfile
import hashlib
import io

spec = importlib.util.spec_from_file_location('release_gate', pathlib.Path(__file__).with_name('verify_release.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

class ReleaseGateTests(unittest.TestCase):
    def test_secret_locations_without_values(self):
        fake = 'sk' + '-' + 'x' * 30
        content = json.dumps({'apiKey': fake}).encode()
        findings = gate.inspect_bytes('example.json', content)
        self.assertTrue(findings)
        self.assertNotIn(fake, json.dumps(findings))
        for suffix in ['.log', '.wav', '.png']:
            self.assertTrue(gate.inspect_bytes('capture' + suffix, b''))
        self.assertTrue(gate.inspect_bytes('config.json', b'{}'))
        self.assertTrue(gate.inspect_bytes('paths.json', b'{}'))
        self.assertTrue(gate.inspect_bytes('settings.json.backup-synthetic', b'{}'))
        self.assertTrue(gate.inspect_bytes('private/notes.md', b'private'))
        self.assertTrue(gate.inspect_bytes('recording-owners/synthetic.json', b'{}'))

    def test_examples_and_interpolation_are_allowed(self):
        for value in ['', '<YOUR_API_KEY>', '...', '${cfg.token}']:
            content = ('apiKey: ' + repr(value)).encode()
            self.assertEqual(gate.inspect_bytes('example.js', content), [])

    def test_private_paths_and_capture_fields(self):
        path = 'C:' + '\\Users\\' + 'SYNTHETIC_ACCOUNT' + '\\config'
        self.assertTrue(gate.inspect_bytes('notes.md', path.encode()))
        self.assertTrue(gate.inspect_bytes('evidence.json', json.dumps({'transcript': 'SYNTHETIC_TEST_ONLY'}).encode()))

    def test_deleted_historical_key_is_still_found(self):
        original = gate.ROOT
        with tempfile.TemporaryDirectory(prefix='synthetic-release-gate-') as directory:
            gate.ROOT = pathlib.Path(directory)
            def git(*args):
                subprocess.run(['git', '-C', directory, '-c', 'user.name=Synthetic fixture',
                                '-c', 'user.email=fixture@example.invalid', *args],
                               check=True, capture_output=True)
            try:
                git('init')
                fake = 'gsk' + '_' + 'x' * 30
                path = gate.ROOT / 'notes.md'
                path.write_text(fake)
                git('add', 'notes.md')
                git('commit', '-m', 'Synthetic contaminated history')
                path.write_text('safe current content')
                git('add', 'notes.md')
                git('commit', '-m', 'Remove synthetic key from current file')
                self.assertEqual(gate.scan_tree()[1], [])
                count, blobs, findings = gate.scan_history()
                self.assertEqual(count, 2)
                self.assertTrue(findings)
                self.assertNotIn(fake, json.dumps(findings))
            finally:
                gate.ROOT = original

    def test_archive_checksums_cannot_be_stale_or_duplicated(self):
        original = gate.ROOT
        with tempfile.TemporaryDirectory(prefix='synthetic-archive-gate-') as directory:
            root = pathlib.Path(directory)
            gate.ROOT = root / 'source'
            artifacts = root / 'packed'
            artifacts.mkdir()
            specifications = {
                'dsh-voice-bridge-0.1.1.tgz': ('bridge', ['package.json','README.md','README.zh-TW.md','LICENSE','bridge.mjs','recording-history.mjs']),
                'dsh-voice-input-cloud-0.1.1.tgz': ('dsh-plugin', ['package.json','README.md','README.zh-TW.md','LICENSE','cordis.patch.yml','lib/index.js','lib/client.js'])}
            try:
                rows = []
                for name, (subdir, files) in specifications.items():
                    with tarfile.open(artifacts / name, 'w:gz') as archive:
                        for relative in files:
                            content = json.dumps({'version': '0.1.1'}).encode() if relative.endswith('.json') else b'synthetic reviewed source'
                            target = gate.ROOT / subdir / relative
                            target.parent.mkdir(parents=True, exist_ok=True)
                            target.write_bytes(content)
                            info = tarfile.TarInfo('package/' + relative)
                            info.size = len(content)
                            archive.addfile(info, io.BytesIO(content))
                    rows.append(hashlib.sha256((artifacts / name).read_bytes()).hexdigest() + '  ' + name)
                sums = artifacts / 'SHA256SUMS'
                sums.write_text('\n'.join(rows) + '\n', encoding='utf-8')
                self.assertEqual(gate.check_archives(artifacts)[1], [])
                sums.write_text('0' * 64 + rows[0][64:] + '\n' + rows[1] + '\n', encoding='utf-8')
                self.assertIn('checksum-set-or-value-mismatch', [finding['category'] for finding in gate.check_archives(artifacts)[1]])
                sums.write_text('\n'.join(rows + [rows[0]]) + '\n', encoding='utf-8')
                self.assertIn('checksum-set-or-value-mismatch', [finding['category'] for finding in gate.check_archives(artifacts)[1]])
            finally:
                gate.ROOT = original

if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ReleaseGateTests)
    result = unittest.TestResult()
    suite.run(result)
    # Assertion tracebacks may include synthetic credentials or local paths.
    print(json.dumps({'ok': result.wasSuccessful(), 'tests': result.testsRun,
                      'failed_tests': [test.id().split('.')[-1] for test, _ in result.failures + result.errors]}))
    sys.exit(0 if result.wasSuccessful() else 1)
