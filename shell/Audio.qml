pragma Singleton

import Quickshell

// Naming a PipeWire sink for a person.
Singleton {
	// PipeWire offers three names for a sink and only one is any use in a
	// label: nickname is the codec ("ALC285 Analog"), description is the
	// device and its profile together ("Ryzen HD Audio Controller Speaker"),
	// and the profile description is what the thing actually is ("Speaker").
	//
	// Bluetooth sinks carry no profile description, so they fall through to a
	// description that is already the device's own name - which is why this
	// reads well for them by accident rather than by design.
	function sinkLabel(node) {
		if (!node)
			return "";

		return (node.properties || {})["device.profile.description"]
			|| node.description
			|| node.nickname
			|| "Output";
	}
}
