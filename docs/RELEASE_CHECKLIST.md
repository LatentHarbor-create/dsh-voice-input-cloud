# GitHub release checklist

Distribution: GitHub source plus two tgz packages, full source archive, SHA256SUMS and
release-validation.json. No npm-registry publication or marketplace submission is included.
Public author: the approved handle LatentHarbor-create, with an empty commit email field.
No private email is inferred. Windows only; keep MIT and Epicenter AGPL-3.0 notices.

1. Review the full diff, English/Chinese installation/upgrade instructions and examples.
2. Run source/history privacy and syntax gates. Compare reviewed content against actual
   local keys, tokens and private prompt without printing their values. Exclude configuration,
   paths.json, recordings, ownership markers, transcripts, private logs/backups and .git.
3. Run relevant synthetic tests and retain separately written validation limits. Existing
   installation checks do not establish clean-user installation acceptance.
4. Pack offline with installation scripts disabled. Verify the exact allowed archive members,
   source/package byte equality and SHA256SUMS. Use a new version; do not overwrite old assets.
5. Inspect public commit identity and all reachable history. Publish only audited source and
   assets after user authorization; preserve an unchanged remote head before fast-forwarding.
6. Read back the public commit/tag/files and download every asset to check byte equality.
   Install downloaded tgz packages in an isolated directory without scripts or cloud calls.

See [current service-control validation](VALIDATION_SERVICE_CONTROL.md),
[privacy rules](PRIVACY.md) and [first-install acceptance](FIRST_INSTALL_CHECK.md).
The last checklist is still pending for a clean Windows machine/profile.
