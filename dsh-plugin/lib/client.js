/**
 * dsh-voice-input — client half.
 *
 * One text control above the composer card (`conversation.input.dock`,
 * session). Flow, strictly through official faces:
 *
 *   click    → inputActions.captureInsertion()  (revision-guarded span)
 *            → POST bridge /start               (Epicenter starts recording)
 *   click    → POST bridge /stop                 → POST /transcribe
 *            → inputActions.insertText(text, span)
 *              - revision valid   → text lands at the captured spot
 *              - revision stale   → re-capture at the current caret, insert
 *                                   there, and surface a transient note on
 *                                   the control itself (never destructive:
 *                                   `insertText` refuses instead of
 *                                   overwriting, and `setDraft` is never
 *                                   used for a transcript)
 *   submit   → never called from here; the draft is only ever filled.
 *
 * Bridge endpoint + token: localStorage key `dsh-voice-bridge`
 * (`{"url":"http://127.0.0.1:39152","token":"..."}`), one-time pairing — see
 * the bridge's home page. Absent config falls back to the default URL with
 * no token (the bridge's default posture is localhost-fenced).
 */
window.__ModuleLoader__.load({
	id: "dsh-voice-input-cloud",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
		let react = require("react");
		let react_jsx_runtime = require("react/jsx-runtime");
		//#region lib/types/client/index.js

		const SLOT_DOCK = "conversation.composer.dock";
		const SLOT_HERO = "conversation.input.dock";
		const SLOT_ID = "dsh-voice-input";
		const STORAGE_KEY = "dsh-voice-bridge";
		const DEFAULT_URL = "http://127.0.0.1:39152";
		const START_TIMEOUT_MS = 30_000;
		const STOP_TIMEOUT_MS = 30_000;
		const TRANSCRIBE_TIMEOUT_MS = 180_000;

		function readConfig() {
			try {
				const raw = window.localStorage.getItem(STORAGE_KEY);
				if (!raw) return { url: DEFAULT_URL, token: "" };
				const parsed = JSON.parse(raw);
				return {
					url: typeof parsed.url === "string" && parsed.url ? parsed.url : DEFAULT_URL,
					token: typeof parsed.token === "string" ? parsed.token : "",
				};
			} catch {
				return { url: DEFAULT_URL, token: "" };
			}
		}

		async function callBridge(cfg, path, body, timeoutMs) {
			const headers = { "content-type": "application/json" };
			if (cfg.token) headers.authorization = "Bearer " + cfg.token;
			const response = await fetch(cfg.url + path, {
				method: "POST",
				headers,
				body: JSON.stringify(body),
				signal: AbortSignal.timeout(timeoutMs),
			});
			let data = {};
			try {
				data = await response.json();
			} catch {
				/* non-JSON error body */
			}
			if (!response.ok) {
				const error = new Error(
					data?.error?.message ?? "bridge request failed with HTTP " + response.status,
				);
				error.code = data?.error?.code ?? "HTTP" + response.status;
				throw error;
			}
			return data;
		}

		const PHASE_LABEL = {
			idle: "🎤 語音輸入",
			starting: "⏳ 啟動錄音中…",
			recording: "● 停止並轉寫（錄音中）",
			transcribing: "⏳ 轉寫中…",
		};
		const PHASE_TITLE = {
			idle: "語音輸入：點擊開始錄音，說完再點一次",
			starting: "正在啟動錄音，請稍候",
			recording: "錄音中… 點擊停止並轉寫",
			transcribing: "轉寫中…",
		};

		function MicButton(props) {
			const { inputActions, layout } = props || {};
			const [phase, setPhase] = react.useState("idle");
			// A ref changes synchronously; state alone permits rapid clicks before render.
			const phaseRef = react.useRef("idle");
			const changePhase = (next) => { phaseRef.current = next; setPhase(next); };
			const [note, setNote] = react.useState("");
			const [errorText, setErrorText] = react.useState("");
			const runRef = react.useRef({
				requestId: "",
				span: null,
				recordingId: "",
				staleFallback: false,
			});
			const cfgRef = react.useRef(null);
			if (cfgRef.current === null) cfgRef.current = readConfig();

			const fail = (message) => {
				changePhase("idle");
				setErrorText(message);
				window.setTimeout(() => setErrorText((current) => (current === message ? "" : current)), 8000);
			};

			const begin = async () => {
				changePhase("starting");
				try {
					const run = {
						requestId: crypto.randomUUID(),
						span: null,
						recordingId: "",
						staleFallback: false,
					};
					// Capture BEFORE the request so the insertion point is where the
					// caret was when the user chose to speak, not where it drifts to
					// while the request flies.
					run.span = inputActions.captureInsertion();
					runRef.current = run;
					const started = await callBridge(cfgRef.current, "/start", { requestId: run.requestId }, START_TIMEOUT_MS);
					run.recordingId = started.recordingId ?? "";
					changePhase("recording");
				} catch (error) {
					fail(`Voice start failed (${error.code ?? "error"}): ${error.message}`);
				}
			};

			const finish = async () => {
				const run = runRef.current;
				changePhase("transcribing");
				try {
					await callBridge(
						cfgRef.current,
						"/stop",
						{ requestId: run.requestId, recordingId: run.recordingId },
						STOP_TIMEOUT_MS,
					);
					// Transcription runs entirely on the cloud (Groq / OpenAI-
					// compatible wire + optional polish); keys live in the bridge's
					// config file. There is intentionally no local-model fallback:
					// this setup is cloud-only by design.
					const cloud = await callBridge(
						cfgRef.current,
						"/transcribe-cloud",
						{ requestId: run.requestId, recordingId: run.recordingId },
						TRANSCRIBE_TIMEOUT_MS,
					);
					const text =
						typeof cloud.text === "string" ? cloud.text : "";
					if (text.length === 0) {
						fail("Transcription produced no text.");
						return;
					}
					// Revision-guarded insertion. `insertText` returns false when
					// the draft moved on or the editor is locked: never overwrite.
					if (inputActions.insertText(text, run.span)) {
						if (run.staleFallback) {
							setNote("Insertion point had changed \u2014 placed at the current caret.");
							window.setTimeout(() => setNote(""), 6000);
						}
						changePhase("idle");
						return;
					}
					// Stale span (or momentary lock): a second, equally guarded
					// attempt at the CURRENT caret. This is the safe-append
					// fallback \u2014 it inserts fresh text and cannot clobber the
					// user's edits, because the same refusal semantics apply.
					const fresh = inputActions.captureInsertion();
					if (inputActions.insertText(text, fresh)) {
						setNote("Insertion point had changed \u2014 placed at the current caret.");
						window.setTimeout(() => setNote(""), 6000);
						changePhase("idle");
						return;
					}
					fail("The composer is busy; the transcript was not inserted. Try again.");
				} catch (error) {
					fail(`Voice transcription failed (${error.code ?? "error"}): ${error.message}`);
				}
			};

			const onClick = () => {
				if (!inputActions) return;
				if (phaseRef.current === "idle") void begin();
				else if (phaseRef.current === "recording") void finish();
				// starting/transcribing: one bridge call chain in flight.
			};

			const disabled = !inputActions || phase === "starting" || phase === "transcribing";
			const title = !inputActions
				? "Voice input unavailable (no input face)"
				: errorText || PHASE_TITLE[phase];

			return react_jsx_runtime.jsxs("div", {
				style: layout === "hero"
					? {
						display: "flex",
						justifyContent: "flex-end",
						alignItems: "center",
						width: "100%",
						padding: "0 0 6px",
						order: 2,
					}
					: {
						display: "flex",
						alignItems: "center",
						padding: "3px 0 8px",
					},
				children: [
					react_jsx_runtime.jsx("button", {
						type: "button",
						onClick,
						disabled,
						title,
						"aria-label": title,
						style: {
							transform: layout === "hero" ? "translateX(-50%)" : "none",
							cursor: disabled ? "default" : "pointer",
							fontSize: "12px",
							lineHeight: 1.2,
							padding: "5px 12px",
							borderRadius: "999px",
							border: errorText
								? "1px solid #d33"
								: "1px solid var(--dsw-alias-border-l2, #ccc)",
							background: "var(--dsw-alias-interactive-bg-hover, transparent)",
							color: errorText ? "#d33" : "inherit",
							opacity: disabled ? 0.55 : 1,
						},
						children: errorText || PHASE_LABEL[phase],
					}),
					note
						? react_jsx_runtime.jsx("span", {
								style: {
									fontSize: "12px",
									opacity: 0.75,
									alignSelf: "center",
									marginLeft: "8px",
								},
								children: note,
							})
						: null,
				],
			});
		}

		/** Slot registration: one control, session-scoped, in the composer's
		* left tool row. Order keeps it ahead of later registrants. */
		function HeroGate(props) {
			// composer.dock already covers active sessions; this entry shows only
			// while the session is blank (new-session state), so exactly one
			// button exists at any time.
			if (props?.session?.blank !== true) return null;
			return (0, react_jsx_runtime.jsx)(MicButton, { ...props, layout: "hero" });
		}

		function apply(ctx) {
			ctx.slots.inject(SLOT_DOCK, () => {
				try {
					const disposer = ctx.slots.register(
						{
							name: SLOT_DOCK,
							id: SLOT_ID + "-dock",
							order: 0,
						},
						MicButton,
					);
					return disposer;
				} catch (error) {
					return () => {};
				}
			});
			ctx.slots.inject(SLOT_HERO, () => {
				try {
					const disposer = ctx.slots.register(
						{
							name: SLOT_HERO,
							id: SLOT_ID + "-hero",
							order: 0,
						},
						HeroGate,
					);
					return disposer;
				} catch (error) {
					return () => {};
				}
			});
		}

		const inject = ["slots"];
		//#endregion
		exports.apply = apply;
		exports.inject = inject;
		return module.exports;
	},
});

//# sourceMappingURL=client.js.map
