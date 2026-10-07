> Historical pre-publication review dated 2026-10-07. Subsequent release authorization
> uses GitHub source/assets only. npm publication is deferred. Public author name is the
> approved handle, with an empty commit email field. See the release installation guide.

# Local release preparation

This candidate is local and unpublished. No remote creation, push, npm publish or PR has been
authorized. First-release scope is two npm packages plus Epicenter source/patch and build
instructions; no Windows executable or installer is included.
The source archive includes a Windows BAT/PowerShell/Node launcher with first-run key/path
setup. This release supports Windows only; macOS/Linux are not supported. Both npm
packages declare the Windows OS restriction as described in [npm's package documentation](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/#os).

Planned owner/repository: `LatentHarbor-create/dsh-voice-input-cloud`. Support: GitHub Issues.
English is the main language, with Chinese installation pages linked at the top of the root
and both package READMEs. Public demonstrations use synthetic text and diagrams only.

## Completed for this candidate

- Approved public handle in package authors and MIT notices; repository/Issues metadata
  describes the planned destination. No private email was inferred or added.
- Windows isolated host build and four user-operated raw-transcription tests passed on DSH
  `0.1.7-rc.2`, with draft preservation and no auto-submit.
- Real optional polish passed: two successful polish responses and user-confirmed insertion,
  existing draft preservation, and no automatic send. It uses one configurable prompt.
- Windows launcher setup/startup has 28 synthetic checks, including hidden key entry,
  private status/output handling and loopback health authentication; no new voice/cloud call.
- Five verifier tests and sixteen synthetic bridge checks passed. Packaged runtime bytes
  preserve the tested bridge/server/registration bytes. The browser client now has a rapid-click
  guard, with four synthetic regression checks; this client change has no new real browser
  acceptance. No repeat live test is scheduled in this pass.
- Source/current reachable history privacy checks and final archive content checks passed;
  exact counts and archive hashes accompany the delivery. Runtime settings, keys, tokens,
  audio, transcripts, browser data, private logs and `.git` are excluded from the source archive.

See [the final review](FINAL_REVIEW.md) and [validation](VALIDATION.md) for the evidence and its limits.

## Before public release

1. Confirm the exact GitHub-provided noreply commit email from account settings. Use it for
   new public commits; do not guess from the GitHub handle or use a private email.
2. Check both npm names (`dsh-voice-bridge`, `dsh-voice-input-cloud`) and publishing permissions
   for the actual npm account. Public registry requests on 2026-10-07 returned 404 for both names. This is
   a point-in-time lookup, not a reservation or a guarantee of publish permission. Recheck
   before publishing; no npm login or account permissions were inspected.
3. Review the final English/Chinese pages, versions, installation steps and license notices.
   Read the per-package MIT licenses and the Epicenter patch's AGPL-3.0 license. Retain notices.
   The launcher guide identifies Windows-only scope, plaintext local config/backup privacy,
   prerequisites and one-time browser pairing. See [the first-install checklist](FIRST_INSTALL_CHECK.md). Complete first-install launcher user acceptance
   remains a documented limitation, separate from the earlier voice acceptance.
4. Re-run source/history/artifact privacy checks after any subsequent change. Review all new
   public examples manually; use synthetic text/diagrams. Publish only reviewed release files,
   never the whole workspace, private test data or a checkout ZIP containing `.git`.
5. Obtain explicit authorization for the exact public actions. Only then create the planned
   GitHub repository/remote, commit using the confirmed public identity, push and publish.
   Installation via the public registry can only be verified after that publication.

## Validation limits and future scope

The user accepted the successful polish round as completion of this test pass; no further
recording/cloud tests are scheduled for local packaging. Controlled real polish failure and
required pairing have synthetic coverage but were not tested in the real browser. The real
tests used `requireToken: false`; do not label untested modes as real end-to-end acceptance.
Node 24.16.0 was tested; Node 18 is the declared minimum. macOS/Linux are unsupported in
this release; other DSH versions are not a validated matrix. Binaries/installers are separate
follow-up work. The new launcher has independent synthetic evidence, not a new real voice test.

The two optional upstream PR drafts are reference artifacts, not required publishing steps.
Two handoff commits are chronological `b903dc2` then `7bc0668`; original input is retained
privately. Candidate privacy changes were tested separately from the original handoff.
Automatic scanners cannot recognize every private phrase or secret format.
