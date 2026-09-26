import QtQuick
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

		// file: 11×14, radius 2
		Rectangle {
			anchors.centerIn: parent
			visible: glyph.kind === "file"
			width: 11
			height: 14
			radius: 2
			color: "transparent"
			border.width: 2
			border.color: glyph.color
		}

		// folder: 14×11, rounder at the bottom
		Rectangle {
			anchors.centerIn: parent
			visible: glyph.kind === "folder"
			width: 14
			height: 11
			radius: 2
			bottomLeftRadius: 3
			bottomRightRadius: 3
			color: "transparent"
			border.width: 2
			border.color: glyph.color
		}

		// home: a roof over a doorway
		Item {
			anchors.centerIn: parent
			visible: glyph.kind === "home"
			width: 14
			height: 14

			Item {
				x: 2
				y: 2
				width: 8
				height: 8
				rotation: 45

				Rectangle { width: 2; height: parent.height; color: glyph.color }
				Rectangle { width: parent.width; height: 2; color: glyph.color }
			}

			Item {
				x: 2
				anchors.bottom: parent.bottom
				width: 6
				height: 6

				Rectangle { anchors.left: parent.left; width: 2; height: parent.height; color: glyph.color }
				Rectangle { anchors.right: parent.right; width: 2; height: parent.height; color: glyph.color }
				Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; radius: 1; color: glyph.color }
			}
		}

		// downloads: an arrow onto a line
		Item {
			anchors.centerIn: parent
			visible: glyph.kind === "downloads"
			width: 14
			height: 14

			Rectangle { x: 6; y: 0; width: 2; height: 9; radius: 1; color: glyph.color }

			Item {
				x: 3
				y: 2
				width: 6
				height: 6
				rotation: 45

				Rectangle { anchors.right: parent.right; width: 2; height: parent.height; color: glyph.color }
				Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: glyph.color }
			}

			Rectangle { anchors.bottom: parent.bottom; width: 14; height: 2; radius: 1; color: glyph.color }
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
