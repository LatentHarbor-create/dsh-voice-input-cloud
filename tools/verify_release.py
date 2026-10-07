#!/usr/bin/env python3
"""Read-only release gate. Findings contain locations, never matched values."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FORBIDDEN_NAMES = {
    'config.json', 'state.json', 'voice-bridge.json', 'voice-bridge.json.tmp',
    'dsh-web.log', '.env', 'credentials.json', 'localstorage.json', 'paths.json',
}
FORBIDDEN_SUFFIXES = {
    '.exe', '.dll', '.log', '.wav', '.mp3', '.m4a', '.flac', '.ogg', '.webm',
    '.mp4', '.aac', '.opus', '.aiff', '.caf', '.pcm', '.srt', '.vtt', '.har',
    '.pem', '.key', '.p12', '.pfx', '.sqlite', '.sqlite3', '.db',
    '.png', '.jpg', '.jpeg', '.gif', '.pdf', '.docx', '.zip', '.tgz', '.gz', '.pyc',
}
PRIVATE_DIRS = {'recordings', 'transcripts', 'runtime', 'private', 'node_modules', 'target', 'artifacts'}
PATTERNS = {
    'vendor-key': re.compile(r'(?:gsk_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})'),
    'jwt': re.compile(r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'),
    'bearer-literal': re.compile(r'\bBearer\s+[A-Za-z0-9_.-]{20,}'),
    'private-key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'private-user-path': re.compile(r'(?:[A-Za-z]:[\\/]+Users[\\/]+(?!<|\{|Public\b|Default\b)[^\s\\/"\x27]+|/root/' + r'workspace/|/(?:home|Users)/(?!<|\{)[^\s/"\x27]+/)'),
    'url-credential': re.compile(r'https?://[^\s/:]+:[^\s/@]+@'),
    'url-secret-query': re.compile(r'[?&](?:api[_-]?key|token|access_token|secret)=[A-Za-z0-9_.-]{12,}', re.I),
    'large-base64': re.compile(r'[A-Za-z0-9+/]{2048,}={0,2}'),
}
LITERAL_SECRET = re.compile(r'["\x27]?(?:apiKey|api_key|access_token|client_secret|token)["\x27]?\s*[:=]\s*(["\x27])([^"\x27\r\n]*)\1')
LINK = re.compile(r'\[[^\]]*\]\(([^)]+)\)')

def placeholder(value):
    return not value or (value.startswith('<') and value.endswith('>')) or value in {'YOUR_KEY_HERE', 'REDACTED', '...'}

def inspect_bytes(location, data, check_name=True):
    findings = []
    path = pathlib.PurePosixPath(location.replace('\\', '/'))
    if check_name and (path.name in FORBIDDEN_NAMES or '.backup-' in path.name or path.name.startswith('.env') or
                       path.suffix.lower() in FORBIDDEN_SUFFIXES or any(p in PRIVATE_DIRS for p in path.parts)):
        findings.append({'location': location, 'category': 'private-or-runtime-artifact'})
    if b'\0' in data:
        findings.append({'location': location, 'category': 'unreviewed-binary'})
        return findings
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        findings.append({'location': location, 'category': 'non-utf8-content'})
        return findings
    for category, pattern in PATTERNS.items():
        for match in pattern.finditer(text):
            findings.append({'location': location, 'line': text.count('\n', 0, match.start()) + 1, 'category': category})
    for match in LITERAL_SECRET.finditer(text):
        # An interpolation expression is source code, not a literal credential.
        expression = re.fullmatch(r'\$\{[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*\}', match.group(2))
        if not placeholder(match.group(2)) and not expression:
            findings.append({'location': location, 'line': text.count('\n', 0, match.start()) + 1, 'category': 'literal-credential'})
    if path.suffix == '.json':
        try:
            parsed = json.loads(text)
        except ValueError:
            findings.append({'location': location, 'category': 'invalid-json'})
        else:
            def walk(value):
                if isinstance(value, dict):
                    for key, item in value.items():
                        if key.lower() in {'text', 'transcript', 'transcription', 'audiobase64', 'rawtext', 'polishedtext'} and isinstance(item, str) and item and not placeholder(item):
                            findings.append({'location': location, 'category': 'possible-capture-data'})
                        walk(item)
                elif isinstance(value, list):
                    for item in value:
                        walk(item)
            walk(parsed)
    return findings

def git(*args):
    p = subprocess.run(['git', '--no-optional-locks', '-C', str(ROOT), *args], capture_output=True)
    if p.returncode:
        raise RuntimeError('git verification failed')
    return p.stdout

def scan_tree():
    findings, files = [], []
    for path in sorted(ROOT.rglob('*')):
        if '.git' in path.relative_to(ROOT).parts:
            continue
        if path.is_symlink():
            findings.append({'location': path.relative_to(ROOT).as_posix(), 'category': 'unreviewed-symlink'})
        elif path.is_file():
            rel = path.relative_to(ROOT).as_posix()
            files.append(rel)
            findings.extend(inspect_bytes(rel, path.read_bytes()))
    return files, findings

def scan_history():
    findings, seen = [], set()
    commits = git('rev-list', '--all').decode().splitlines()
    for commit in commits:
        findings.extend(inspect_bytes('commit:' + commit, git('show', '-s', '--format=%an%n%ae%n%cn%n%ce%n%B', commit), check_name=False))
        for entry in git('ls-tree', '-rz', '--full-tree', commit).split(b'\0'):
            if not entry:
                continue
            meta, name = entry.split(b'\t', 1)
            mode, kind, oid = meta.split()
            rel = name.decode('utf-8')
            if kind != b'blob' or mode == b'120000':
                findings.append({'location': commit[:8] + ':' + rel, 'category': 'unreviewed-git-entry'})
            elif (oid, rel) not in seen:
                seen.add((oid, rel))
                findings.extend(inspect_bytes(commit[:8] + ':' + rel, git('cat-file', 'blob', oid.decode())))
    return len(commits), len(seen), findings

def check_archives(directory):
    results, findings = {}, []
    specifications = {
        'dsh-voice-bridge-0.1.0.tgz': ('bridge', {'package.json', 'README.md', 'README.zh-TW.md', 'LICENSE', 'bridge.mjs'}),
        'dsh-voice-input-cloud-0.1.0.tgz': ('dsh-plugin', {'package.json', 'README.md', 'README.zh-TW.md', 'LICENSE', 'cordis.patch.yml', 'lib/index.js', 'lib/client.js'}),
    }
    allowed = set(specifications) | {'dsh-voice-input-cloud-0.1.0-source.tar.gz', 'SHA256SUMS', 'release-validation.json'}
    for path in directory.rglob('*'):
        rel = path.relative_to(directory).as_posix()
        if path.is_symlink() or (path.is_file() and rel not in allowed):
            findings.append({'location': rel, 'category': 'unreviewed-artifact'})
        elif path.is_file() and rel in {'SHA256SUMS', 'release-validation.json'}:
            findings.extend(inspect_bytes(rel, path.read_bytes()))
    for name, (subdir, expected) in specifications.items():
        path = directory / name
        if not path.is_file():
            findings.append({'location': name, 'category': 'missing-package'})
            continue
        found = set()
        with tarfile.open(path, 'r:gz') as archive:
            for member in archive.getmembers():
                if member.isdir():
                    continue
                if not member.isfile() or not member.name.startswith('package/'):
                    findings.append({'location': name, 'category': 'unexpected-package-member'})
                    continue
                rel = member.name[len('package/'):]
                if rel in found or rel not in expected:
                    findings.append({'location': name + ':' + rel, 'category': 'unexpected-or-duplicate-package-file'})
                    continue
                found.add(rel)
                data = archive.extractfile(member).read()
                findings.extend(inspect_bytes(name + ':' + rel, data, check_name=False))
                if data != (ROOT / subdir / rel).read_bytes():
                    findings.append({'location': name + ':' + rel, 'category': 'package-source-mismatch'})
        if found != expected:
            findings.append({'location': name, 'category': 'package-file-set-mismatch'})
        results[name] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'files': len(found), 'bytes': path.stat().st_size}
    # The source archive is optional; when supplied it must match every current file.
    source = directory / 'dsh-voice-input-cloud-0.1.0-source.tar.gz'
    if source.exists():
        expected_files, _ = scan_tree()
        found = set()
        with tarfile.open(source, 'r:gz') as archive:
            for member in archive.getmembers():
                if member.isdir():
                    continue
                prefix = 'dsh-voice-input-cloud/'
                if not member.isfile() or not member.name.startswith(prefix):
                    findings.append({'location': source.name, 'category': 'unexpected-source-member'})
                    continue
                rel = member.name[len(prefix):]
                if rel not in expected_files or rel in found:
                    findings.append({'location': source.name + ':' + rel, 'category': 'unexpected-source-file'})
                    continue
                found.add(rel)
                data = archive.extractfile(member).read()
                findings.extend(inspect_bytes(source.name + ':' + rel, data, check_name=False))
                if data != (ROOT / rel).read_bytes():
                    findings.append({'location': source.name + ':' + rel, 'category': 'source-content-mismatch'})
        if found != set(expected_files):
            findings.append({'location': source.name, 'category': 'source-file-set-mismatch'})
        results[source.name] = {'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'files': len(found)}
    sums = directory / 'SHA256SUMS'
    if not sums.is_file():
        findings.append({'location': 'SHA256SUMS', 'category': 'missing-checksums'})
    else:
        entries = {}
        malformed = False
        for line in sums.read_text(encoding='utf-8').splitlines():
            match = re.fullmatch(r'([0-9a-f]{64})  ([^/\\]+)', line)
            if not match or match[2] in entries:
                malformed = True
                continue
            entries[match[2]] = match[1]
        if malformed or entries != {name: item['sha256'] for name, item in results.items()}:
            findings.append({'location': 'SHA256SUMS', 'category': 'checksum-set-or-value-mismatch'})
    return results, findings

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=pathlib.Path)
    args = parser.parse_args()
    files, findings = scan_tree()
    commits, blobs, historical = scan_history()
    findings.extend(historical)
    syntax = []
    for rel in ['bridge/bridge.mjs', 'dsh-plugin/lib/client.js', 'dsh-plugin/lib/index.js', 'launcher/launch-service.mjs']:
        result = subprocess.run(['node', '--check', str(ROOT / rel)], capture_output=True)
        syntax.append({'file': rel, 'ok': result.returncode == 0})
        if result.returncode:
            findings.append({'location': rel, 'category': 'syntax-error'})
    if sys.platform == 'win32':
        for rel in ['launcher/start-voice.ps1', 'tools/test_launcher.ps1']:
            env = dict(os.environ, DSH_RELEASE_PS1=str(ROOT / rel))
            code = '$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($env:DSH_RELEASE_PS1,[ref]$t,[ref]$e);if($e.Count){exit 1}'
            result = subprocess.run(['powershell.exe', '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', code], env=env, capture_output=True)
            syntax.append({'file': rel, 'ok': result.returncode == 0})
            if result.returncode:
                findings.append({'location': rel, 'category': 'syntax-error'})
    for rel in ['bridge/package.json', 'dsh-plugin/package.json']:
        if json.loads((ROOT / rel).read_text(encoding='utf-8')).get('os') != ['win32']:
            findings.append({'location': rel, 'category': 'missing-windows-platform-declaration'})
    checked_links = 0
    for rel in files:
        if not rel.endswith('.md'):
            continue
        path = ROOT / rel
        for target in LINK.findall(path.read_text(encoding='utf-8')):
            value = target.split('#')[0].strip()
            if not value or value.startswith(('https://', 'http://', 'mailto:')):
                continue
            checked_links += 1
            if not (path.parent / value).exists():
                findings.append({'location': rel, 'category': 'broken-relative-link'})
    artifacts = {}
    if args.artifacts:
        artifacts, packed_findings = check_archives(args.artifacts)
        findings.extend(packed_findings)
    for finding in findings:
        for pattern in PATTERNS.values():
            finding['location'] = pattern.sub('<redacted>', finding['location'])
    report = {'ok': not findings, 'current_files': len(files), 'history_commits': commits,
              'history_file_versions': blobs, 'relative_links': checked_links,
              'syntax': syntax, 'artifacts': artifacts, 'findings': findings}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['ok'] else 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception:
        # Exceptions can contain source data or absolute private paths.
        print(json.dumps({'ok': False, 'findings': [{'category': 'verification-error', 'location': 'verifier'}]}))
        sys.exit(2)
