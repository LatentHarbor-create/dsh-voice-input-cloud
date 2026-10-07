# First Windows installation acceptance

This checklist is prepared, not executed. The current user-operated voice acceptance used
an existing isolated installation; synthetic launcher checks are separate evidence.

Use a clean Windows profile or another Windows machine. Keep existing drafts and services
on the daily profile undisturbed. Use invented speech/text and local credentials; publish
only version names and pass/fail results. Do not attach config, recordings or screenshots.

1. Extract the reviewed source archive. Verify its external SHA-256 before extracting.
2. Install Node, DSH >= 0.1.7-rc.2, Bun and the documented Epicenter build prerequisites.
   Apply the full patch to the pinned clean upstream commit and build the patched host.
   The source bundle includes no host executable or installer.
3. Install/enable the voice plugin using the source path or reviewed local tarball.
   Run `.\launcher\start-voice.bat -SetupOnly` from a terminal, or double-click the BAT normally
   for setup plus startup. Enter program paths and the speech key with hidden input.
   Optionally enable polish and enter its provider/model/key plus one prompt.
4. Verify the wizard created local paths/config, generated a pairing token, and preserved
   any existing fields. Keys and backups must remain outside the extracted source tree.
5. Launch normally. Check Epicenter/bridge health and DSH opening; pair the tab once.
   Confirm exactly one voice control. Record a synthetic sentence, stop and verify insertion
   in the draft, preservation of an existing synthetic edit and no automatic send.
6. Close only the launcher window and invoke it again. Confirm it reuses existing services
   and retains the draft. Check `-Check` and `-NoBrowser` without recording.
7. Use `-SetupOnly` to revisit settings; Enter should retain both local keys, pairing token
   and prompt. Choosing another endpoint requires its own matching key.
8. Record only Windows/Node/DSH versions, build type and each outcome. If a step fails, keep
   diagnostics private and report a redacted error code and reproducible step.

Do not enable boot startup as part of this checklist. The launcher does not stop services.
For rollback, retain the original local config/paths or private `.backup-*` copies, close only
processes you started after verifying their identity, and restore settings locally as needed.
No keys, authentication URLs, real drafts or recordings belong in an acceptance report.
