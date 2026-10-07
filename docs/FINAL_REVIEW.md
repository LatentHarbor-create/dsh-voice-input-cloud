# Review of v0.1.1

The launcher now reconciles each component independently in Epicenter -> Bridge -> DSH
order. Healthy components are reused; missing components start; verified unresponsive voice
components are repaired individually. Stop, Restart, Status and Settings share one English
BAT menu. Ownership/health checks, safe failures and marker-only history cleanup are covered
by synthetic tests and existing-installation Windows checks.

Review corrected the previous bilingual-menu wording and the old no-cleanup privacy claim.
Both installation languages explain upgrades, local-only settings and the two cloud key
purposes. The bridge package includes its required recording-history.mjs module; the full
source archive includes all launcher helpers. Old v0.1.0 assets remain unchanged.

The optional polish prompt remains a single configurable instruction; the transcript is
sent separately as user content. Keys and private prompt/config are never release inputs.
The root README distinguishes manual bridge defaults from configurable wizard suggestions.

See [service-control validation and limits](VALIDATION_SERVICE_CONTROL.md) and the
[release checklist](RELEASE_CHECKLIST.md). A full clean-user first installation remains
pending. GitHub-only distribution remains a prerelease, with no npm publish, marketplace PR,
patched host binary or new real microphone/cloud test in this update.
