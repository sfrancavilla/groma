.pragma library

// Which of DeviceIcon's shapes a freedesktop icon name asks for. Bluez and
// PipeWire both report one - "audio-headset", "input-mouse", "audio-speakers"
// - and only the family matters.
function kindFor(name) {
	name = name || "";

	if (name.includes("headset") || name.includes("headphone"))
		return "headphones";
	if (name.startsWith("audio") || name.includes("speaker"))
		return "speaker";
	if (name.startsWith("input") || name.includes("mouse")
			|| name.includes("keyboard"))
		return "input";
	if (name.includes("phone") || name.includes("watch"))
		return "phone";

	return "unknown";
}
