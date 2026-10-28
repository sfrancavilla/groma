import QtQuick
import QtQuick.Shapes
import ".."

// The sections of the Settings window, each by the one thing that names it:
// a keyboard's keys and space bar, a display on its stand, a crescent for
// idle, a picture's sun and hill, a pair of earbuds, a shield, an i.
//
// Built like HardwareIcon: the shared 24-unit grid, marks spanning 3..21, at
// markLine, in the file ink a lens disc takes.
//
// `kind`: keyboard · display · idle · wallpaper · earbuds · privacy · about
Item {
	id: icon

	property color color: Theme.fileInk
	property string kind: "keyboard"
	property real lineWidth: Theme.markLine

	readonly property real baseWidth: 24
	readonly property real baseHeight: 24
	readonly property real units: icon.lineWidth * icon.baseWidth / Math.max(1, icon.width)

	readonly property var paths: ({
		keyboard: "M4.5 6.5H19.5A2 2 0 0 1 21.5 8.5V15.5A2 2 0 0 1 19.5 17.5H4.5A2 2 0 0 1 2.5 15.5V8.5A2 2 0 0 1 4.5 6.5Z"
			+ "M6.5 10H7.5M10.5 10H11.5M14.5 10H15.5M8 14H16",
		display: "M5 4H19A2 2 0 0 1 21 6V14A2 2 0 0 1 19 16H5A2 2 0 0 1 3 14V6A2 2 0 0 1 5 4Z"
			+ "M9 20H15M12 16V20",
		idle: "M19.5 14.5A8 8 0 0 1 9.5 4.5A8 8 0 1 0 19.5 14.5Z",
		wallpaper: "M5 4H19A2 2 0 0 1 21 6V18A2 2 0 0 1 19 20H5A2 2 0 0 1 3 18V6A2 2 0 0 1 5 4Z"
			+ "M7 10A2 2 0 1 0 11 10A2 2 0 1 0 7 10Z"
			+ "M21 16L16 11L7 20",
		earbuds: "M8 4H7A3 3 0 0 0 4 7V8A3 3 0 0 0 7 11H8ZM8 11V19"
			+ "M16 4H17A3 3 0 0 1 20 7V8A3 3 0 0 1 17 11H16ZM16 11V19",
		privacy: "M12 3L19 6V11C19 15.5 16 19 12 21C8 19 5 15.5 5 11V6Z",
		about: "M3 12A9 9 0 1 0 21 12A9 9 0 1 0 3 12Z"
			+ "M12 11V16.5M12 7.75V8.25",
	})

	implicitWidth: 16
	implicitHeight: 16

	Item {
		width: icon.baseWidth
		height: icon.baseHeight

		transform: Scale {
			xScale: icon.width / icon.baseWidth
			yScale: icon.height / icon.baseHeight
		}

		Shape {
			anchors.fill: parent
			// As in HardwareIcon: the curve renderer draws nothing in a
			// surface created hidden, which a window is until it is opened.
			antialiasing: true
			layer.enabled: true
			layer.samples: 4
			layer.textureSize: Qt.size(icon.width * 3, icon.height * 3)
			layer.smooth: true

			ShapePath {
				strokeColor: icon.color
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				PathSvg { path: icon.paths[icon.kind] ?? "" }
			}
		}
	}
}
