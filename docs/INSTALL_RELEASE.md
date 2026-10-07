# Install the GitHub early release

**English** | [中文](INSTALL_RELEASE.zh-TW.md)

Windows only. This distribution is on [GitHub Releases](https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/tag/v0.1.0), not npm registry.
Downloading and installing the tarballs does not require an npm account. npm is still a useful
installation tool: it accepts a tarball URL or local file. Package-name install commands are
unavailable until a separate npm publication. This repository is a monorepo, so do not use
`npm install github:LatentHarbor-create/dsh-voice-input-cloud` as a root package installation.

## Recommended: full source

1. Download `dsh-voice-input-cloud-0.1.0-source.tar.gz` and `SHA256SUMS`. Check the SHA-256
   of the downloaded file with `Get-FileHash -Algorithm SHA256`, then extract it.
2. Follow the root README to build the patched Epicenter host at the pinned upstream commit.
   Install Node >= 18, Bun and DSH >= 0.1.7-rc.2. No host executable or installer is supplied.
3. In DSH plugin center, add the extracted `dsh-plugin` directory by absolute path and enable it.
4. Double-click `launcher/start-voice.bat`. The wizard guides paths, the required speech key,
   optional polish key and one prompt. Keys remain in local bridge config, outside source.
5. Pair the DSH tab once as instructed; reload the tab after inserting localStorage settings.
   Startup is manual. No boot task or service is registered.

## Optional: install the Release tarballs with npm

```powershell
npm install -g --ignore-scripts "https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/download/v0.1.0/dsh-voice-bridge-0.1.0.tgz"
$pluginRoot = Join-Path $env:LOCALAPPDATA 'dsh-cloud-plugin'
npm install --prefix "$pluginRoot" --ignore-scripts "https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/download/v0.1.0/dsh-voice-input-cloud-0.1.0.tgz"
```

Add `$pluginRoot\node_modules\dsh-voice-input-cloud` by absolute path in DSH plugin center.
Neither tarball includes the Windows launcher or Epicenter host. Obtain source for the launcher
and host patch. The bridge CLI can be started as `dsh-voice-bridge`; the launcher instead
asks for the installed `bridge.mjs` path or uses its default source copy. Use one bridge only.
For offline use, download/verify the tarballs first and replace the URLs with their local paths.
The bridge package has zero dependencies; the plugin also contains no installation scripts.

## Scope and support

This is an early release. Core voice/polish has prior user acceptance; the latest rapid-click
guard has synthetic coverage, not a repeat real-browser test. A full clean-user launcher install
is not yet accepted. See `FIRST_INSTALL_CHECK.md` and `VALIDATION.md` for limits.
Use GitHub Issues with versions, a redacted error code and synthetic reproduction steps.
Never attach filled config, keys, token-bearing URLs, recordings, transcripts or full logs.
