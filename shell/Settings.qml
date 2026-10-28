pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Choices that have to outlive a restart.
//
// Theme.qml holds what the shell looks like, which is part of the source.
// This holds what the user decided, which is not - so it lives in a file and
// is written back whenever it changes.
Singleton {
	id: root

	// Whether the network tile may ask a web service for the public address.
	// Off by default: a shell that contacts a third party before anyone has
	// agreed to it has asked the question too late.
	readonly property alias publicAddressLookup: adapter.publicAddressLookup

	function setPublicAddressLookup(value) {
		adapter.publicAddressLookup = value;
	}

	// Whether the shell has already said there is a fingerprint reader with
	// nothing enrolled. Once, ever: a nudge that comes back is a nag.
	readonly property alias fingerprintNudged: adapter.fingerprintNudged

	function setFingerprintNudged(value) {
		adapter.fingerprintNudged = value;
	}

	// Applications pinned to the launcher, by desktop-entry id, in order.
	readonly property alias pinnedApps: adapter.pinnedApps

	function isPinned(id) {
		return (adapter.pinnedApps ?? []).includes(id);
	}

	function togglePin(id) {
		const now = adapter.pinnedApps ?? [];
		adapter.pinnedApps = now.includes(id)
			? now.filter(entry => entry !== id)
			: [...now, id].slice(0, 5);
	}

	// What each workspace is for - "Terminals", "Groma", "YouTube" - by
	// number. Kept by number rather than handed to Hyprland, because Hyprland
	// forgets a workspace the moment its last window closes, and a name is
	// worth more than the windows that happen to be on it today.
	readonly property alias workspaceNames: adapter.workspaceNames

	function workspaceName(id) {
		return (adapter.workspaceNames ?? {})[String(id)] ?? "";
	}

	function setWorkspaceName(id, name) {
		const next = Object.assign({}, adapter.workspaceNames ?? {});
		const clean = String(name ?? "").trim();
		if (clean === "")
			delete next[String(id)];
		else
			next[String(id)] = clean;
		adapter.workspaceNames = next;
	}

	// And a colour for each, as a key into Theme.tagPalette - "blue", not a
	// hex value, so a new theme moves everyone's blue along with it.
	readonly property alias workspaceColors: adapter.workspaceColors

	function workspaceColor(id) {
		return (adapter.workspaceColors ?? {})[String(id)] ?? "";
	}

	function setWorkspaceColor(id, key) {
		const next = Object.assign({}, adapter.workspaceColors ?? {});
		if (!key)
			delete next[String(id)];
		else
			next[String(id)] = key;
		adapter.workspaceColors = next;
	}

	// The desktop picture, as an absolute path. Empty is Groma's own, drawn
	// rather than loaded (DesktopBackdrop.qml).
	readonly property alias wallpaper: adapter.wallpaper

	function setWallpaper(path) {
		adapter.wallpaper = path ?? "";
	}

	// --- Idle (modules/IdleChain.qml) --------------------------------------
	// Seconds before each stage, plugged in and on battery; zero turns a stage
	// off. Shorter on battery, where the screen is the expensive part.
	//
	// Blanking the screen is not sleeping: the machine stays fully awake with
	// the display off, which on battery is most of the cost and none of the
	// benefit - hence a suspend stage there. Mains gets none: a plugged in
	// machine left alone should stay reachable.
	readonly property var idleDefaults: ({
		dim:       { mains: 300, battery: 120 },
		lock:      { mains: 600, battery: 240 },
		screenOff: { mains: 660, battery: 300 },
		suspend:   { mains: 0,   battery: 900 },
	})

	// Only what was changed is stored, so a better default still reaches
	// everyone who never touched theirs.
	readonly property alias idleTimes: adapter.idleTimes

	function idleAfter(stage, onBattery) {
		const power = onBattery ? "battery" : "mains";
		return (adapter.idleTimes ?? {})[stage]?.[power] ?? root.idleDefaults[stage][power];
	}

	// null puts the default back.
	function setIdleAfter(stage, onBattery, seconds) {
		const power = onBattery ? "battery" : "mains";
		const next = Object.assign({}, adapter.idleTimes ?? {});
		const entry = Object.assign({}, next[stage] ?? {});
		if (seconds === null || seconds === undefined)
			delete entry[power];
		else
			entry[power] = Math.max(0, Math.round(seconds));
		if (Object.keys(entry).length === 0)
			delete next[stage];
		else
			next[stage] = entry;
		adapter.idleTimes = next;
	}

	// --- Hyprland (HyprConfig.qml) ----------------------------------------
	// Choices that belong to the compositor rather than the shell. Kept here
	// with the rest and written out as Lua by HyprConfig.qml. Unset - empty or
	// null - means hyprland.lua's default, and only what is set is written, so
	// a default changed in the repository still arrives.

	// Keyboard layouts in switching order, as xkb pairs:
	// [{ layout: "it", variant: "" }]. The first is the one a session starts in.
	readonly property alias keyboardLayouts: adapter.keyboardLayouts

	function setKeyboardLayouts(list) {
		adapter.keyboardLayouts = (list ?? [])
			.filter(entry => entry && entry.layout)
			.map(entry => ({ layout: entry.layout, variant: entry.variant ?? "" }));
	}

	readonly property alias naturalScroll: adapter.naturalScroll
	readonly property alias tapToClick: adapter.tapToClick
	// -1 to 1, as Hyprland's input:sensitivity; 0 leaves libinput's speed alone.
	readonly property alias pointerSpeed: adapter.pointerSpeed

	function setNaturalScroll(value) {
		adapter.naturalScroll = value ?? null;
	}

	function setTapToClick(value) {
		adapter.tapToClick = value ?? null;
	}

	function setPointerSpeed(value) {
		adapter.pointerSpeed = value === null || value === undefined
			? null : Math.max(-1, Math.min(1, value));
	}

	// Scale per display, keyed by Hyprland's description of it - make, model
	// and serial - rather than its connector, which is whichever port it went
	// into today. Absent is "auto".
	readonly property alias displayScales: adapter.displayScales

	function displayScale(description) {
		return (adapter.displayScales ?? {})[description] ?? null;
	}

	// Called once a scale has been kept, not while it is being tried:
	// HyprConfig.previewScale() is the trying.
	function setDisplayScale(description, scale) {
		const next = Object.assign({}, adapter.displayScales ?? {});
		if (scale === null || scale === undefined)
			delete next[description];
		else
			next[description] = scale;
		adapter.displayScales = next;
	}

	// Refresh rate per display, as the mode Hyprland is given -
	// "2880x1920@60" - keyed like displayScales. Absent is "preferred".
	readonly property alias displayModes: adapter.displayModes

	function displayMode(description) {
		return (adapter.displayModes ?? {})[description] ?? null;
	}

	// Kept, as with setDisplayScale: HyprConfig.previewDisplay() tries it.
	function setDisplayMode(description, mode) {
		const next = Object.assign({}, adapter.displayModes ?? {});
		if (mode === null || mode === undefined)
			delete next[description];
		else
			next[description] = mode;
		adapter.displayModes = next;
	}

	// How long a held key waits before repeating, in milliseconds, and how
	// many times a second it then repeats.
	readonly property alias repeatDelay: adapter.repeatDelay
	readonly property alias repeatRate: adapter.repeatRate

	function setRepeatDelay(value) {
		adapter.repeatDelay = value === null || value === undefined
			? null : Math.max(150, Math.min(1000, Math.round(value)));
	}

	function setRepeatRate(value) {
		adapter.repeatRate = value === null || value === undefined
			? null : Math.max(10, Math.min(60, Math.round(value)));
	}

	// What Caps Lock does: "" for Caps Lock, "escape", "ctrl" or "none".
	readonly property alias capsLock: adapter.capsLock

	function setCapsLock(value) {
		adapter.capsLock = ["escape", "ctrl", "none"].includes(value) ? value : "";
	}

	readonly property alias disableWhileTyping: adapter.disableWhileTyping
	// 0.2 to 2, as Hyprland's touchpad scroll_factor; 1 leaves it alone.
	readonly property alias scrollFactor: adapter.scrollFactor
	// Three fingers across the touchpad to change workspace.
	readonly property alias workspaceSwipe: adapter.workspaceSwipe

	function setDisableWhileTyping(value) {
		adapter.disableWhileTyping = value ?? null;
	}

	function setScrollFactor(value) {
		adapter.scrollFactor = value === null || value === undefined
			? null : Math.max(0.2, Math.min(2, value));
	}

	function setWorkspaceSwipe(value) {
		adapter.workspaceSwipe = value ?? null;
	}

	// --- Clock (shell.qml, modules/LockContent.qml) ------------------------

	readonly property alias clock24: adapter.clock24
	// The bar's "Wed 28 Oct" before the time.
	readonly property alias clockDate: adapter.clockDate

	function setClock24(value) {
		adapter.clock24 = value;
	}

	function setClockDate(value) {
		adapter.clockDate = value;
	}

	// --- Integration: Nothing earbuds (integrations/nothingear) ----------
	// One settings file for everything, so these keep the baseline's store;
	// the prefix in the comment is the only namespacing there is.

	// Stop the sound when an earbud is taken out - or put in, since the buds
	// do not say which. On by default: the failure mode of "off" is playing
	// into an empty ear.
	readonly property alias pauseOnBudRemoved: adapter.pauseOnBudRemoved

	function setPauseOnBudRemoved(value) {
		adapter.pauseOnBudRemoved = value;
	}

	// And start it again when the bud comes back. Inferred from timing, since
	// the buds report a change and not a direction - see NothingEar.qml.
	readonly property alias resumeOnBudReplaced: adapter.resumeOnBudReplaced

	function setResumeOnBudReplaced(value) {
		adapter.resumeOnBudReplaced = value;
	}

	// The day a week starts on in the calendar: 1 for Monday, 0 for Sunday,
	// or null for the locale's. Not the locale's alone, because a machine
	// set to en_US outside the US is the usual case, not the odd one.
	readonly property alias weekStart: adapter.weekStart

	function setWeekStart(value) {
		adapter.weekStart = value;
	}

	// What a screen recording hears: the computer's own sound, and the
	// microphone. Sound on, microphone off - a recording that picks up the
	// room by default has asked too late, as with the public address.
	readonly property alias recordSound: adapter.recordSound
	readonly property alias recordMicrophone: adapter.recordMicrophone

	function setRecordSound(value) {
		adapter.recordSound = value;
	}

	function setRecordMicrophone(value) {
		adapter.recordMicrophone = value;
	}

	FileView {
		id: file

		// Quickshell makes this directory; a path under ~/.config would have
		// to be created before the first write.
		path: Quickshell.statePath("settings.json")

		// The file does not exist until something is changed, and complaining
		// about that on every first run is noise.
		printErrors: false
		watchChanges: true
		onFileChanged: file.reload()
		onAdapterUpdated: file.writeAdapter()

		JsonAdapter {
			id: adapter

			property bool publicAddressLookup: false
			property bool fingerprintNudged: false
			property var pinnedApps: []
			property var workspaceNames: ({})
			property var workspaceColors: ({})
			property string wallpaper: ""
			property var idleTimes: ({})
			property var keyboardLayouts: []
			property var naturalScroll: null
			property var tapToClick: null
			property var pointerSpeed: null
			property var displayScales: ({})
			property var displayModes: ({})
			property var repeatDelay: null
			property var repeatRate: null
			property string capsLock: ""
			property var disableWhileTyping: null
			property var scrollFactor: null
			property var workspaceSwipe: null
			property bool clock24: true
			property bool clockDate: true
			property bool pauseOnBudRemoved: true
			property bool resumeOnBudReplaced: true
			property var weekStart: null
			property bool recordSound: true
			property bool recordMicrophone: false
		}
	}
}
