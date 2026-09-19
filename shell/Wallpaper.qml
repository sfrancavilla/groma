import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

// The desktop background.
//
// Drawn rather than loaded, so there is something behind the glass out of the
// box: glass over an empty dark desktop is grey, whatever tint you give it.
// Point `source` at a file and that is used instead.
//
// This is the mesh the design's mockups sit on, transcribed rather than
// approximated. In CSS it is
//
//   radial-gradient(100% 80% at 15% 15%, oklch(0.78 0.13 130) 0%, transparent 55%),
//   radial-gradient( 90% 90% at 85% 75%, oklch(0.62 0.18 290) 0%, transparent 60%),
//   oklch(0.3 0.05 230)
//
// where the leading pair is the ellipse's radii as a share of the box, not a
// circle - which is what made the first attempt at this too small and too
// round to read as the same backdrop.
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

	// Shapes only offers a circular radial gradient, so the ellipse is a
	// circle of radius rx with the whole layer squashed vertically about the
	// gradient's own centre.
	component Wash: Item {
		id: blob

		property color tint: "#ffffff"
		property real cx: 0
		property real cy: 0
		property real rx: 100
		property real ry: 100
		// Where the colour has faded out entirely, as a share of rx.
		property real fade: 0.55

		anchors.fill: parent
		visible: wallpaper.source === ""

		transform: Scale {
			origin.x: blob.cx
			origin.y: blob.cy
			yScale: blob.rx > 0 ? blob.ry / blob.rx : 1
		}

		Shape {
			anchors.fill: parent
			preferredRendererType: Shape.CurveRenderer
			asynchronous: true

			ShapePath {
				strokeWidth: 0

				fillGradient: RadialGradient {
					centerX: blob.cx
					centerY: blob.cy
					centerRadius: blob.rx
					focalX: blob.cx
					focalY: blob.cy

					GradientStop { position: 0.0; color: blob.tint }
					GradientStop {
						position: blob.fade
						color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0)
					}
				}

				// Overdrawn vertically, because the squash above would
				// otherwise leave the top and bottom of the screen bare.
				startX: 0; startY: blob.cy - blob.height * 4
				PathLine { x: blob.width; y: blob.cy - blob.height * 4 }
				PathLine { x: blob.width; y: blob.cy + blob.height * 4 }
				PathLine { x: 0; y: blob.cy + blob.height * 4 }
			}
		}
	}

	Wash {
		tint: Theme.desktopWashA
		cx: wallpaper.width * 0.15
		cy: wallpaper.height * 0.15
		rx: wallpaper.width * 1.0
		ry: wallpaper.height * 0.8
		fade: 0.55
	}

	Wash {
		tint: Theme.desktopWashB
		cx: wallpaper.width * 0.85
		cy: wallpaper.height * 0.75
		rx: wallpaper.width * 0.9
		ry: wallpaper.height * 0.9
		fade: 0.60
	}
}
