# Upstream PR drafts for `EpicenterHQ/epicenter`

Two independent bug fixes found while building a fork of the desktop host (the
loopback voice-bridge surface in [`voice-bridge.patch`](voice-bridge.patch)). They are unrelated
to that fork and worth upstream on their own.

- **Base:** `main` @ `1b73addb653987adacde5d9410d6022600c4f6ea` (2026-09-27)
- **Diffs:** [`upstream-pr-a-blob-sync-file.patch`](upstream-pr-a-blob-sync-file.patch),
  [`upstream-pr-b-runevent-reopen-cfg.patch`](upstream-pr-b-runevent-reopen-cfg.patch) —
  each one file, one bug, both verified with `git apply --check -p1` against a clean checkout of
  that commit.
- **Not included** (fork-specific, deliberately kept out of both PRs): the `bridge` module, the
  `tiny_http` dependency, dropping the `vulkan` feature from `transcribe-cpp`, and the
  `icons/icon.ico` bundle entry.
- **Not created from this repository.** No remote, no PR. Copy the text below when submitting.

---

## PR A

**Title:** `fix(recorder): open the sync handle read-write so Windows flushes actually reach the disk`

**Files:** `apps/epicenter/src-tauri/src/recorder/blob.rs` (one function + its doc comment)

### Summary

`sync_file` opens the published blob path read-only and then calls `File::sync_all()`. On
Windows `sync_all` is `FlushFileBuffers`, which requires a handle with write access —
`FlushFileBuffers` on a read-only handle fails with `ERROR_ACCESS_DENIED` (`os error 5`).
POSIX `fsync` accepts a read-only descriptor, so this only ever fails on Windows. The function
now opens the path read-write.

### Why it matters

`sync_file` is the durability step of the publish path (it is what makes "the recording is
published" mean "the bytes are on the platter"). On Windows that step fails, so the sync ladder
does not do what it says: the caller gets
`RecorderError::Failed { message: "sync <path>: <os error 5 text>" }`, and a published
recording is never actually flushed. Any caller that treats a failed sync as "the recording is
not usable" loses the take; any caller that swallows it publishes a recording whose durability
was never established.

### Reproduction

Any Windows build; the code path is unconditional. Observed while building a Windows x64 fork:
the sync step returns `os error 5` where the same code succeeds on macOS and Linux. Minimal
in-repo repro once the test below lands: run `sync_file` on a temp file on Windows — `Err`
before this change, `Ok(())` after.

### The change

```rust
-use std::fs::File;
+use std::fs::{File, OpenOptions};

 fn sync_file(path: &Path) -> Result<(), RecorderError> {
-    File::open(path)
+    OpenOptions::new()
+        .read(true)
+        .write(true)
+        .open(path)
         .and_then(|file| file.sync_all())
         .map_err(|error| RecorderError::failed(format!("sync {}: {error}", path.display())))
 }
```

The doc comment above the function claimed "opening read-only is enough, since `fsync` acts on
the file the descriptor names rather than on the descriptor's access mode" — true on POSIX,
false on Windows, which is exactly the bug. The patch corrects that paragraph too.

### Alternatives considered

- `#[cfg(windows)]`-split bodies (`OpenOptions` write on Windows, `File::open` elsewhere) —
  platform-uniform single path is simpler and has no downside: read-write is a superset of what
  both platforms' sync needs, and the file is one the recorder just wrote.
- Opening write-only — `fsync` accepts it on POSIX, but it breaks syncing a file that happens
  to be read-only on disk, and it loses `read` semantics for the descriptor.
- Reopening by handle instead of by path — not possible here: the writer (`hound`'s `finalize`)
  is consumed by value before the publish step, which is why the function takes a path at all
  (the existing comment explains this; it stays accurate).

### Testing

A Windows-gated unit test is the natural contract:

```rust
#[cfg(windows)]
#[test]
fn sync_file_succeeds_on_windows() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("blob.bin");
    std::fs::write(&path, b"audio").unwrap();
    sync_file(&path).expect("FlushFileBuffers needs a write-capable handle");
}
```

That test is red before this change (`os error 5`) and green after, on Windows only — which is
the platform that can actually observe it.

---

## PR B

**Title:** `fix(desktop): gate the RunEvent::Reopen arm behind cfg(target_os = "macos")`

**Files:** `apps/epicenter/src-tauri/src/lib.rs` (one match arm + a comment)

### Summary

`RunEvent::Reopen` is a macOS-only variant in Tauri v2 (the Dock re-click event; the variant
itself is `#[cfg(target_os = "macos")]` in the tauri crate). The event loop's match arm uses it
ungated, so `cargo check`/`cargo build` fails on Windows and Linux with
`error[E0599]: no variant or associated item named 'Reopen' found for enum 'RunEvent'`. The arm
is now gated with the same `cfg` the variant carries.

### Why it matters

The desktop host cannot be compiled on Windows or Linux at all — not a runtime difference, a
hard build failure, on the app's own supported platforms.

### Reproduction

```bash
cargo check --manifest-path apps/epicenter/src-tauri/Cargo.toml   # on Windows or Linux
# error[E0599]: no variant or associated item named `Reopen` found for enum `RunEvent`
```

### The change

```rust
         .run(|app, event| match event {
+            // `Reopen` is the macOS Dock re-click: a variant that only exists
+            // on macOS. Gating the arm keeps `cargo check`/`cargo build` green
+            // on Windows and Linux, where the catch-all below already covers
+            // every variant this build sees.
+            #[cfg(target_os = "macos")]
             RunEvent::Reopen { .. } => request_window(app, BuiltInApp::Home),
             RunEvent::Exit => shutdown_host(app),
             _ => {}
         });
```

The `_ => {}` catch-all is already present and needs no companion arm.

### Alternatives considered

- `#[cfg(desktop)]` instead of `target_os = "macos"` — does not help: `desktop` is true on
  Windows and Linux too, which is precisely where the variant does not exist.
- Hoisting the whole closure into a `fn handle_run_event(...)` with per-platform arms — larger
  change than the bug needs; the one-line gate is the minimal fix and matches the variant's own
  cfg.
- Making the arm a no-op on other platforms (`#[cfg(not(target_os = "macos"))] RunEvent::Reopen`
  is not even nameable there) — impossible by construction.

### Testing

No unit test applies: the compiler is the test. `cargo check` on the repo's Windows (and Linux)
CI job is sufficient, and it is exactly the check that fails before this change.
