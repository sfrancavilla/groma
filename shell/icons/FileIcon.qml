import Quickshell
import QtQuick
import "fileicons.js" as FileIcons

// A file's or folder's icon from the icon theme - Papirus' file types and
// places - inside whatever disc holds it; the drawn outline (FileGlyph) where
// the theme has none.
Item {
	id: icon

	// Either the theme name directly...
	property string iconName: ""
	// ...or the file, to choose one from.
	property string fileName: ""
	property bool folder: false
	property string path: ""
	// The outline to fall back to, and its zoom.
	property string glyph: folder ? "folder" : "file"
	property real zoom: 1

	readonly property string chosen: icon.iconName !== "" ? icon.iconName
		: icon.path !== "" ? FileIcons.name(icon.fileName, icon.folder, icon.path, Quickshell.env("HOME")) : ""
	readonly property string source: icon.chosen !== "" ? Quickshell.iconPath(icon.chosen, true) : ""

	Image {
		anchors.fill: parent
		visible: icon.source !== ""
		source: icon.source
		sourceSize: Qt.size(icon.width * 2, icon.height * 2)
		fillMode: Image.PreserveAspectFit
		smooth: true
	}

	FileGlyph {
		anchors.centerIn: parent
		visible: icon.source === ""
		kind: icon.glyph
		zoom: icon.zoom
	}
}
