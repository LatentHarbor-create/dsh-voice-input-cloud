# epicenter-patch — the loopback voice-bridge surface for the Epicenter desktop host

**This DSH voice-input release supports Windows only. macOS/Linux installation is not
supported here, regardless of upstream Epicenter's platform support.**

This directory holds a **patch for [Epicenter](https://github.com/EpicenterHQ/epicenter)**
(the desktop host the DSH voice plugin records through) plus the two standalone patches that
are worth proposing upstream. Nothing here is applied automatically, and no binary is shipped.

- Upstream project: `EpicenterHQ/epicenter` (the old `epicenter-so/epicenter` path redirects here)
- Cut against: **`main` @ `1b73addb653987adacde5d9410d6022600c4f6ea`** (2026-09-27)
- Files:

| File | What it is |
|---|---|
| `voice-bridge.patch` | The whole fork delta: adds the loopback surface and the two bug fixes |
| `upstream-pr-a-blob-sync-file.patch` | **Upstream PR draft A** — `sync_file` needs a write-capable handle on Windows |
| `upstream-pr-b-runevent-reopen-cfg.patch` | **Upstream PR draft B** — `RunEvent::Reopen` arm needs a `cfg` gate |
| `UPSTREAM_PR.md` | The PR descriptions for A and B |
| `LICENSE` | AGPL-3.0 (see "Licensing" below) |

The original handoff recorded these source checks:

- `git apply --check -p1 voice-bridge.patch` against the upstream tree at `1b73addb` → **applies cleanly** (all 8 files).
- `git apply --check -p1` on both PR draft patches against the same tree → **apply cleanly**.
- Every upstream symbol the new bridge module calls exists and is visible at that commit:
  `recorder::blob::{mint_blob_id, blob_data_path}`, `recorder::commands::refresh_recording_indicator`,
  `recorder::error::RecorderError::{Busy, NotRecording, NoInputDevice, PermissionDenied, Failed}`,
  `Recorder::{start, stop, cancel}`, `HostRecording.device`, `FinalizedRecording::publish` →
  `RecordedAudio { duration_ms, byte_length }`.
- That handoff did not rebuild on Windows. It cites an earlier local user test, which does
  not verify later candidate changes. Check `docs/VALIDATION.md` in the source distribution
  for current candidate evidence. Clean patch application is separate from compilation and
  end-to-end recording/draft insertion.

This candidate changes the full fork patch's request logging to use known method/route labels.
Raw request paths and query strings are excluded. The two upstream bug-fix draft patches are
unchanged. Keep runtime logs private until separately reviewed.

## What the patch changes

| File | Change | Upstream-worthy? |
|---|---|---|
| `src/bridge/mod.rs` | **new** — spawns the surface: binds `127.0.0.1:0`, generates a per-launch 32-byte token, publishes `<app_config_dir>/voice-bridge.json` (tmp + rename), starts 4 workers | fork feature |
| `src/bridge/server.rs` | **new** — routing (`/health /audio /start /stop /cancel`), Host + bearer fence, body cap, error mapping | fork feature |
| `src/lib.rs` | `pub mod bridge;` + one `bridge::spawn(app.handle().clone())` call in `setup` | fork feature |
| `src/lib.rs` | `#[cfg(target_os = "macos")]` on the `RunEvent::Reopen` match arm | **yes — PR B** |
| `src/recorder/blob.rs` | `sync_file` opens read-write instead of read-only | **yes — PR A** |
| `src/recorder/blob.rs` | **new** `read_blob_bytes` — raw published WAV bytes, for forwarding rather than decoding | fork feature |
| `src/recorder/commands.rs` | `refresh_recording_indicator` → `pub(crate)` | fork feature (enables the above) |
| `Cargo.toml` / `Cargo.lock` | adds `tiny_http = "0.12"`; drops the `vulkan` feature from `transcribe-cpp` on Windows x64 | fork build choice |
| `tauri.conf.json` | adds `icons/icon.ico` to the bundle icon list | fork build choice |

The `vulkan` drop is deliberate for this fork's hardware (Intel Iris Xe iGPU; CPU inference
avoids the Vulkan SDK + vcpkg `spirv-headers` chain). It is **not** proposed upstream — upstream
keeps `dynamic-backends` + `vulkan`.

## Apply

```bash
git clone https://github.com/EpicenterHQ/epicenter
cd epicenter
git checkout 1b73addb653987adacde5d9410d6022600c4f6ea
git apply --check -p1 /path/to/dsh-voice-input-cloud/epicenter-patch/voice-bridge.patch
git apply -p1 /path/to/dsh-voice-input-cloud/epicenter-patch/voice-bridge.patch
# or, to keep a reviewable commit:
git apply -p1 --index /path/to/.../voice-bridge.patch && git commit -m "voice bridge"
```

Run `--check` before applying. A checkout already containing the patch is not a pristine
target; do not apply the full patch twice.

If it fails on `Cargo.lock` only, the fix is to re-resolve rather than to force the hunk:

```bash
git apply -p1 --exclude=apps/epicenter/src-tauri/Cargo.lock /path/to/.../voice-bridge.patch
cd apps/epicenter/src-tauri && cargo update -p tiny_http --precise 0.12.0
```

## Windows build prerequisites

Reported from the Windows machine that produced this patch (this repository does not rebuild
it; treat the list as the fork's build notes, not as verified instructions for your machine):

- **bun** (the monorepo's JS tasks, `bun install`, `bunx`).
- **rustup** with the **MSVC** toolchain (`stable-x86_64-pc-windows-msvc`) — not the GNU
  toolchain, which cannot link the Tauri/Windows dependencies.
- **Visual Studio Build Tools** with the **"Desktop development with C++"** workload
  (MSVC C++ build tools + Windows SDK). `VCTools` alone without the SDK is not enough for the
  `windows` crate's resource compilation.
- **CMake < 4** — `transcribe-cpp`/`ggml`'s CMake files (and their vendored projects) do not
  support CMake 4's removed compatibility with `cmake_minimum_required(VERSION <3.5)`.
  Put the 3.x `cmake.exe` first on `PATH` for the build.
- **UTF-8 console**: run the build from a console with `chcp 65001` (and, if you script it,
  set `PYTHONUTF8=1`). The tree's sources and comments contain non-ASCII characters; a
  CP950/CP936 console can mangle them in tool output.
- **UTF-8 C/C++ source**: set `CXXFLAGS=/utf-8` and `CFLAGS=/utf-8` for MSVC. The
  `transcribe-cpp-sys` source contains UTF-8 characters; the candidate's clean native build
  failed under the default source code page and succeeded with these compiler flags.
  A UTF-8 console alone does not set MSVC's source encoding.
- **Short build paths**: native CMake/MSBuild steps can still hit a 260-character path limit.
  Use a short checkout and a short, separate `CARGO_TARGET_DIR` (for example `C:\build\dsh-voice`).
  A long target path failed an Opus C compiler probe during candidate verification; this was
  a build-directory issue, not evidence that the Rust bridge source failed to compile.
- **`bunx tauri icon <png>`** to (re)generate `apps/epicenter/src-tauri/icons/icon.ico` from a
  square PNG. The patch adds `icons/icon.ico` to the bundle icon list, so the file must exist
  before `tauri build`.
- **No Vulkan SDK / vcpkg `spirv-headers` needed** with this patch, because the `vulkan`
  feature is dropped here (see above). If you restore `vulkan`, you must also install
  **SPIRV-Headers through vcpkg** and add its prefix to `CMAKE_PREFIX_PATH` — the Vulkan SDK
  provides the loader but not that CMake package.
- Build command used: `cd apps/epicenter && bunx tauri build` (CPU inference, no GPU backend).

For the candidate's isolated Windows debug validation, the sequence was:

```powershell
# Run in the pinned, patched checkout. Choose a short writable target path.
$env:CARGO_TARGET_DIR = 'C:\build\dsh-voice'
$env:CXXFLAGS = '/utf-8'
$env:CFLAGS = '/utf-8'
bun install --frozen-lockfile --ignore-scripts
cd apps/epicenter
bun run build:desktop
cargo build --offline --locked --manifest-path src-tauri/Cargo.toml
```

The offline Rust step uses previously cached locked crates. On a new machine, dependency
downloads are still required. The debug executable was launched in an isolated environment;
user-operated recording, real cloud transcription and DSH draft insertion passed in this
candidate. See [validation](../docs/VALIDATION.md) for coverage and remaining gates.
No executable or installer is packaged for distribution.

## Licensing

`epicenter-patch/` is a derivative work of Epicenter and is licensed **AGPL-3.0**
(see [`LICENSE`](LICENSE)). The two npm packages in this repository (`bridge/`,
`dsh-plugin/`) are MIT and do not contain this patch.

Consequence, stated plainly: **a patched Epicenter build is an AGPL-3.0 work.** Keep it local,
or, if you distribute it, satisfy AGPL-3.0 (source availability, notices, license text). This
directory ships source only — **no Windows executable is included or distributed here**, and
the decision whether to distribute binaries at all is deliberately left open.

## Making the upstream PRs

`UPSTREAM_PR.md` holds the descriptions; the two `.patch` files next to it are the exact diffs.
They are independent of the fork: each touches one file and one bug, they apply to a clean
`1b73addb` checkout, and neither depends on the bridge module. Recommended: two separate PRs,
each one commit, each with the reproduction from `UPSTREAM_PR.md`. Per the release plan, **no PR
is created from this repository** — the user submits them manually after review.

For isolated runs, set the same absolute `EPICENTER_DATA_DIR` in the host and bridge. The launch discovery file follows that root; with the variable unset, the existing default path is retained. Bridge config and state still follow its process `APPDATA`.
