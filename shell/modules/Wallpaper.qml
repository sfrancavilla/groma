import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."

// The desktop background. Drawn rather than loaded, so there is something
// behind the glass out of the box - glass over an empty dark desktop is grey,
// whatever tint you give it. A picture chosen in Settings is used instead,
// unless it cannot be loaded - a moved or deleted file falls back to the
// drawing, not to a bare colour.
PanelWindow {
	id: wallpaper

	property string source: Settings.wallpaper !== "" ? "file://" + Settings.wallpaper : ""

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
		visible: wallpaper.source === "" || picture.status === Image.Error
	}

	Image {
		id: picture

		anchors.fill: parent
		source: wallpaper.source
		visible: wallpaper.source !== ""
		fillMode: Image.PreserveAspectCrop
		asynchronous: true
	}
}
