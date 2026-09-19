import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."

// The desktop background. Drawn rather than loaded, so there is something
// behind the glass out of the box - glass over an empty dark desktop is grey,
// whatever tint you give it. Point `source` at a file and that is used instead.
PanelWindow {
	id: wallpaper

	property string source: ""

	anchors {
		top: true
		bottom: true
		left: true
		right: true
	}

	exclusionMode: ExclusionMode.Ignore
	WlrLayershell.layer: WlrLayer.Background
	WlrLayershell.namespace: "groma:wallpaper"
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

	color: Theme.desktopBase

	DesktopBackdrop {
		anchors.fill: parent
		visible: wallpaper.source === ""
	}

	Image {
		anchors.fill: parent
		source: wallpaper.source
		visible: wallpaper.source !== ""
		fillMode: Image.PreserveAspectCrop
		asynchronous: true
	}
}
