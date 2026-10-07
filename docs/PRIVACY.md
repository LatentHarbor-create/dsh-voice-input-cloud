# Publication privacy

Only reviewed source, public documentation, licenses, patches and synthetic tests belong in
this repository or its packages. Private runtime material stays outside the release tree.

## Credentials and data

| Material | Publication rule |
|---|---|
| Speech-to-text API key (`transcription.apiKey`) | Empty in public examples; enter locally after installation |
| Optional text-polish API key (`transformation.apiKey`) | Empty in public examples; enter locally after installation |
| Local pairing token and Epicenter per-launch token | Use placeholders in examples; never include a real pairing page or discovery file |
| Recorded WAV, other audio and raw or polished transcripts | Exclude real captures; demonstrations use invented sentences and synthetic fixtures |
| Runtime config, state, logs and browser storage | Exclude; do not attach full exports to an issue |
| Screenshots, recordings, reports and shell output | Review for keys, tokens, transcripts, paths, names and account information before sharing |
| Personal paths, private hostnames, private email and account identifiers | Replace with portable placeholders unless explicitly approved for publication |

The speech-to-text provider receives the WAV. When polish is enabled and a polish key exists,
the second provider receives the raw transcript and system prompt. The optional polish key
does not enable audio transcription by itself. A provider or model shown as a software default
does not disclose a maintainer's private configuration.

Epicenter owns the recording files and can persist WAV blobs in its data directory. This plugin
does not automatically remove those host recordings. Keep that directory out of release and
support bundles even though the Node bridge only forwards audio in memory.

Do not copy `%APPDATA%\dsh-voice-bridge\config.json`, `state.json`, Epicenter's `voice-bridge.json`,
browser localStorage, recorded blobs or installed-process logs into this repository. The
ignored-file list is a convenience; the release verifier checks files and package contents
independently, including ignored or untracked files in the release tree.

## Verification and its limits

Run `python tools/verify_release.py --artifacts <output-directory>` before sharing a source
archive or npm tarball. It checks current files, reachable git commit contents and metadata,
credential patterns, forbidden runtime artifacts, selected private paths, package contents,
syntax and relative links. Findings report locations and categories without matched values.
Failure returns a nonzero exit code. The verifier does not modify or redact source files.

Automated patterns cannot recognize every private sentence or unknown credential format.
Manual review is required for public prose and every screenshot or demonstration. A clean scan
is evidence about these rules, not a guarantee that all possible sensitive information is absent.

The git scan covers reachable commit content and commit metadata, not private `.git` config,
reflogs or unreachable objects. Never publish a zip of a working checkout with `.git` included.
Use the verified source archive; a future git push should contain only the reviewed commits.

Build logs and real acceptance evidence stay in a private workspace. Publish only a separately
written summary containing versions, test names and pass/fail outcomes, without transcript
contents, local account paths or credentials. Never publish this chat or the original private
handoff/report bundle wholesale.

If a real credential is discovered, stop release preparation, keep its value out of outputs,
and identify the affected files and history before producing a clean candidate. Replacing a
value in the current file does not remove it from git history or an older archive.
