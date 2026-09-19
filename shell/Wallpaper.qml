import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

// The desktop background.
//
// Drawn rather than loaded, so there is something behind the glass out of the
// box: glass over an empty black desktop is just grey, whatever tint you give
// it. Point `source` at a file and that is used instead.
//
// The gradient is the mesh the design's mockups sit on, so the shell looks the
// way it was drawn.
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

	Image {
		anchors.fill: parent
		source: wallpaper.source
		visible: wallpaper.source !== ""
		fillMode: Image.PreserveAspectCrop
		asynchronous: true
	}

	// Two broad washes of colour over the base, the way the design's backdrop
	// is built. Shapes rather than Rectangle, because a Rectangle gradient is
	// linear only.
	Shape {
		anchors.fill: parent
		visible: wallpaper.source === ""
		preferredRendererType: Shape.CurveRenderer
		asynchronous: true

		ShapePath {
			strokeWidth: 0

			fillGradient: RadialGradient {
				centerX: wallpaper.width * 0.15
				centerY: wallpaper.height * 0.15
				centerRadius: wallpaper.width * 0.75
				focalX: wallpaper.width * 0.15
				focalY: wallpaper.height * 0.15

				GradientStop { position: 0.0; color: Theme.desktopWashA }
				GradientStop { position: 0.55; color: "#00000000" }
			}

			startX: 0; startY: 0
			PathLine { x: wallpaper.width; y: 0 }
			PathLine { x: wallpaper.width; y: wallpaper.height }
			PathLine { x: 0; y: wallpaper.height }
			PathLine { x: 0; y: 0 }
		}
	}

	Shape {
		anchors.fill: parent
		visible: wallpaper.source === ""
		preferredRendererType: Shape.CurveRenderer
		asynchronous: true

		ShapePath {
			strokeWidth: 0

			fillGradient: RadialGradient {
				centerX: wallpaper.width * 0.85
				centerY: wallpaper.height * 0.78
				centerRadius: wallpaper.width * 0.7
				focalX: wallpaper.width * 0.85
				focalY: wallpaper.height * 0.78

				GradientStop { position: 0.0; color: Theme.desktopWashB }
				GradientStop { position: 0.6; color: "#00000000" }
			}

			startX: 0; startY: 0
			PathLine { x: wallpaper.width; y: 0 }
			PathLine { x: wallpaper.width; y: wallpaper.height }
			PathLine { x: 0; y: wallpaper.height }
			PathLine { x: 0; y: 0 }
		}
	}
}
