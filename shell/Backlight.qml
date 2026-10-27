pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Which backlight is the screen's, found rather than named, so the brightness
// keys and the idle dim work on any machine - not only the one whose panel is
// amdgpu_bl1.
//
// The kernel's advice when there are several: prefer firmware, then platform,
// then raw. A laptop usually has one; a desktop or a virtual machine has none,
// and then `device` stays empty and brightness is left alone.
//
// Read once at start: backlights do not come and go while the session runs.
Singleton {
	id: root

	property string device: ""

	Process {
		running: true
		command: ["sh", "-c",
			"for d in /sys/class/backlight/*; do [ -e \"$d/type\" ] && echo \"$(cat \"$d/type\") ${d##*/}\"; done"]

		stdout: StdioCollector {
			onStreamFinished: {
				const rank = { firmware: 0, platform: 1, raw: 2 };
				const found = text.trim().split("\n")
					.filter(line => line !== "")
					.map(line => line.split(" "))
					.sort((a, b) => (rank[a[0]] ?? 3) - (rank[b[0]] ?? 3));

				root.device = found.length > 0 ? found[0][1] : "";
			}
		}
	}
}
