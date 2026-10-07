> Historical pre-publication review dated 2026-10-07. Subsequent release authorization
> uses GitHub source/assets only. npm publication is deferred. Public author name is the
> approved handle, with an empty commit email field. See the release installation guide.

# Final local review

2026-10-07. This is an unpublished Windows-only candidate. No public repository, remote,
push, npm publication or PR was created by this work.

## Review and corrections

- Read bridge, plugin, launcher and installation/privacy/release documentation together.
  Bridge, plugin server entry and registration patch remain byte-for-byte unchanged. The
  browser client now guards rapid clicks before React renders, including recovery after start failure.
- Launcher JSON serialization now preserves deeper settings and refuses excessive nesting
  before setup writes either file. It no longer silently truncates fields at depth 40.
- Reject malformed boolean/string/port fields and unsafe pairing-token characters; preserve
  the existing local file. Setup locking now follows the bridge config profile, including
  launches using different path-settings files.
- Reuse the selected Epicenter executable and refuse a different/unidentified Epicenter
  installation before starting a second host. Process paths cannot prove the environment
  profile of an existing process; keep isolated test profiles separate.
- Report browser-open failure separately from DSH readiness, without storing the authenticated
  URL. The Node helper rejects invalid absolute paths/ports before spawning a service.
  Startup status files are removed when the normal wait completes or fails.
- Correct Windows-only path instructions and document protected pairing-page HTTP 401 behavior.
  Pair first; enabling `requireToken` requires a bridge restart. Existing protected installations
  use the local config token in the pairing snippet, followed by a DSH-tab reload.
- Explain the manual bridge's `gpt-4o-mini` default and the wizard's configurable
  `gpt-5.4-mini` suggestion; cloud credentials and private prompt are never shipped.
- The archive gate now verifies the complete SHA256SUMS set, values and duplicate entries.
- Add a [first-install acceptance checklist](FIRST_INSTALL_CHECK.md) and
  [release-note draft](RELEASE_NOTES.md). Neither triggers publication or a cloud call.

## Evidence

28 launcher checks pass: 16 PowerShell, 9 Node helper, 3 synthetic loopback-health checks.
Four browser-client synthetic checks pass and detect the old rapid-click bug.
Five release-verifier checks pass, including changed/duplicate archive checksums.
The existing sixteen bridge privacy checks and user-operated voice/polish acceptance apply
to the prior voice baseline. The new client guard has synthetic coverage only; it has not
been revalidated with real recording/DSH insertion. No new recording or real cloud call was made.
Fresh Windows offline package installation and source/history/archive gates are recorded
in the accompanying release-validation and delivery reports. Test success does not certify
unknown secret formats or untested platforms.

On 2026-10-07, unauthenticated public registry requests for both
[dsh-voice-bridge](https://registry.npmjs.org/dsh-voice-bridge) and
[dsh-voice-input-cloud](https://registry.npmjs.org/dsh-voice-input-cloud) returned HTTP 404.
This means not found at lookup time, not reserved or guaranteed publishable. No npm account
credentials were sent. The approved [public GitHub handle](https://github.com/LatentHarbor-create)
is visible via a web read; GitHub API verification returned 403. Account ownership, repository
creation permission and the exact settings-provided noreply email remain unverified.

## Remaining before publication

1. Confirm the exact GitHub noreply email and the signed-in GitHub/npm publishing accounts.
   Keep login credentials/2FA local. Recheck both npm names immediately before publication.
   See [npm's unscoped publication instructions](https://docs.npmjs.com/creating-and-publishing-unscoped-public-packages/).
2. Record a complete first-install launcher acceptance, including the new client click guard, on a clean Windows profile/machine.
   Existing voice acceptance and synthetic launcher checks do not establish that result.
3. Review bilingual prose and license notices. Epicenter remains a source/patch build
   prerequisite; this release is not a complete installer or prebuilt host distribution.
4. Get explicit authorization for the exact external publication actions. Re-run privacy,
   content and hash checks after any edits; publish only the reviewed files.
5. After publication, verify registry/GitHub installation and only then prepare a separate
   community-market submission. Marketplace installation alone does not install/start the host.

The user ended the live polish test pass. Controlled real polish failure and required-pairing
browser acceptance remain documented limits; no repeat live test is scheduled here.
Exact archive hashes live outside source in SHA256SUMS, avoiding self-referential hashes.
