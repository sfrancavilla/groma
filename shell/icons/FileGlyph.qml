import QtQuick
import QtQuick.Shapes
import ".."

// The marks the design draws inside a lens disc for things in the file
// system: a sheet, a tray, a house, and the rest of turn 10's set. All are
// 2px strokes in the file ink against a 16px box, built from rectangles as
// the design builds them, so they match it to the pixel.
//
// `kind`: file · folder · home · downloads · pictures · trash · drive ·
//         back · forward · search
Item {
	id: glyph

	property string kind: "file"
	property color color: Theme.fileInk
	// Drawn at 1× and scaled, so a grid tile's 1.5× mark is the same mark.
	property real zoom: 1

	implicitWidth: 16 * glyph.zoom
	implicitHeight: 16 * glyph.zoom

	Item {
		id: box

		anchors.centerIn: parent
		width: 16
		height: 16
		scale: glyph.zoom

		// file: a page with its corner folded. folder: a tray with a tab.
		Shape {
			anchors.centerIn: parent
			width: 16
			height: 16
			visible: glyph.kind === "file" || glyph.kind === "folder"
			preferredRendererType: Shape.CurveRenderer

			ShapePath {
				strokeColor: glyph.kind === "file" ? glyph.color : "transparent"
				strokeWidth: 2
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 3.5; startY: 1.5
				PathLine { x: 9.5; y: 1.5 }
				PathLine { x: 13; y: 5 }
				PathLine { x: 13; y: 14.5 }
				PathLine { x: 3.5; y: 14.5 }
				PathLine { x: 3.5; y: 1.5 }
				PathMove { x: 9.5; y: 1.5 }
				PathLine { x: 9.5; y: 5 }
				PathLine { x: 13; y: 5 }
			}

			ShapePath {
				strokeColor: glyph.kind === "folder" ? glyph.color : "transparent"
				strokeWidth: 2
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 1.5; startY: 3.5
				PathLine { x: 6; y: 3.5 }
				PathLine { x: 7.5; y: 5.5 }
				PathLine { x: 14.5; y: 5.5 }
				PathLine { x: 14.5; y: 12.5 }
				PathLine { x: 1.5; y: 12.5 }
				PathLine { x: 1.5; y: 3.5 }
			}
		}

		// home, downloads and trash are outlines rather than assemblies of
		// rectangles: at 14px the design's pieces - a rotated square for a
		// roof, a bar for a lid - read as fragments, where one stroked path
		// reads as the thing.
		Shape {
			anchors.centerIn: parent
			width: 14
			height: 14
			visible: glyph.kind === "home" || glyph.kind === "downloads" || glyph.kind === "trash"
			preferredRendererType: Shape.CurveRenderer

			// home: a roof, then the walls and floor as one open box.
			ShapePath {
				strokeColor: glyph.kind === "home" ? glyph.color : "transparent"
				strokeWidth: 2
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 1; startY: 7
				PathLine { x: 7; y: 1.5 }
				PathLine { x: 13; y: 7 }
				PathMove { x: 3; y: 6 }
				PathLine { x: 3; y: 12.5 }
				PathLine { x: 11; y: 12.5 }
				PathLine { x: 11; y: 6 }
			}

			// downloads: an arrow into a tray.
			ShapePath {
				strokeColor: glyph.kind === "downloads" ? glyph.color : "transparent"
				strokeWidth: 2
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 7; startY: 1
				PathLine { x: 7; y: 8.5 }
				PathMove { x: 3.5; y: 5.5 }
				PathLine { x: 7; y: 9 }
				PathLine { x: 10.5; y: 5.5 }
				PathMove { x: 1.5; y: 10 }
				PathLine { x: 1.5; y: 12.5 }
				PathLine { x: 12.5; y: 12.5 }
				PathLine { x: 12.5; y: 10 }
			}

			// trash: a lid with a handle over a bin that narrows a little.
			ShapePath {
				strokeColor: glyph.kind === "trash" ? glyph.color : "transparent"
				strokeWidth: 2
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 1; startY: 3.5
				PathLine { x: 13; y: 3.5 }
				PathMove { x: 5; y: 3.5 }
				PathLine { x: 5; y: 1.5 }
				PathLine { x: 9; y: 1.5 }
				PathLine { x: 9; y: 3.5 }
				PathMove { x: 2.5; y: 3.5 }
				PathLine { x: 3.5; y: 13 }
				PathLine { x: 10.5; y: 13 }
				PathLine { x: 11.5; y: 3.5 }
			}
		}

		// pictures: a frame with a sun in the corner
		Rectangle {
			anchors.centerIn: parent
			visible: glyph.kind === "pictures"
			width: 14
			height: 11
			radius: 3
			color: "transparent"
			border.width: 2
			border.color: glyph.color

			Rectangle {
				anchors { right: parent.right; top: parent.top; rightMargin: 2; topMargin: 2 }
				width: 3
				height: 3
				radius: 1.5
				color: glyph.color
			}
		}

		// trash: a lid with a handle over a bin
		Item {
			anchors.centerIn: parent
			visible: glyph.kind === "trash"
			width: 14
			height: 15

			Rectangle { y: 2; width: 14; height: 2; radius: 1; color: glyph.color }
			Rectangle { x: 5; y: 0; width: 4; height: 2; radius: 1; color: glyph.color }

			Item {
				x: 2
				y: 5
				width: 6
				height: 8

				Rectangle { anchors.left: parent.left; width: 2; height: parent.height; color: glyph.color }
				Rectangle { anchors.right: parent.right; width: 2; height: parent.height; color: glyph.color }
				Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: glyph.color }
			}
		}

		// drive: a low box with a light
		Rectangle {
			anchors.centerIn: parent
			visible: glyph.kind === "drive"
			width: 14
			height: 9
			radius: 3
			color: "transparent"
			border.width: 2
			border.color: glyph.color

			Rectangle {
				anchors { right: parent.right; top: parent.top; rightMargin: 2; topMargin: 3 }
				width: 3
				height: 3
				radius: 1.5
				color: glyph.color
			}
		}

		// back / forward: a chevron, nudged so its visual centre sits centred
		Item {
			anchors.centerIn: parent
			anchors.horizontalCenterOffset: glyph.kind === "back" ? 2 : -2
			visible: glyph.kind === "back" || glyph.kind === "forward"
			width: 7
			height: 7
			rotation: 45

			Rectangle {
				anchors.left: glyph.kind === "back" ? parent.left : undefined
				anchors.right: glyph.kind === "forward" ? parent.right : undefined
				width: 2
				height: parent.height
				color: glyph.color
			}

			Rectangle {
				anchors.bottom: glyph.kind === "back" ? parent.bottom : undefined
				anchors.top: glyph.kind === "forward" ? parent.top : undefined
				width: parent.width
				height: 2
				color: glyph.color
			}
		}

		// search: a ring with a handle, as the design draws it in a 26px disc
		Item {
			anchors.centerIn: parent
			anchors.horizontalCenterOffset: -1.5
			anchors.verticalCenterOffset: -1.5
			visible: glyph.kind === "search"
			width: 11
			height: 11

			Rectangle {
				anchors.fill: parent
				radius: width / 2
				color: "transparent"
				border.width: 2
				border.color: glyph.color
			}

			Rectangle {
				x: parent.width - 2
				y: parent.height - 3
				width: 6
				height: 2
				radius: 1
				rotation: 45
				color: glyph.color
			}
		}
	}
}
