/**
 * dsh-voice-input — host half.
 *
 * Deliberately minimal: the voice control is client-side (the composer's
 * `conversation.input.left` slot), and the recording/transcription work runs
 * in the local voice-bridge process (127.0.0.1), not in this host. This
 * entry exists because a bundle contributes its client half to the browser
 * roster through its host Loader entry: with no rows, the client module is
 * never scanned. The apply() is a no-op that merely marks composition.
 */
const name = "dsh-voice-input";
const inject = [];

function apply(ctx) {
	// Nothing to mount host-side today. Keep this half tiny: any state the
	// voice flow needs lives in the bridge process, and this plugin must
	// stay removable without behavior change.
}

export { apply, inject, name };
