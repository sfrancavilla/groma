import QtQuick
import ".."
import "../icons"
import "../ui"

// One network in a list: name, a lock if it is secured, and its strength.
//
// Wanted in the tile and in the full picker, and the two would have drifted.
// They are not identical - the picker is 520 wide and has room for the
// security type and for a selected state, the tile at 300 has room for
// neither - so the differences are properties rather than a second file.
Rectangle {
	id: row

	// The Quickshell Network object.
	property var network: null
	// What the nmcli scan knows about it, if anything.
	property var detail: null
	property int bars: 0

	// The tile's row. Off, it is the picker's: taller, larger type, and the
	// security label on the right.
	property bool compact: true
	property bool selected: false

	// Shown, but dimmed: nmcli's `device wifi connect` can only build open,
	// WEP and WPA-PSK profiles, so an enterprise network is visible and not
	// joinable. Hiding it would be worse - it is in range, and someone looking
	// for it deserves to be told why it will not work rather than left
	// wondering why their network is missing.
	property bool unsupported: false

	// The search term, marked in the name wherever it occurs.
	property string highlight: ""

	signal activated
	signal chosen

	readonly property bool known: row.network?.known ?? false
	readonly property bool connected: row.network?.connected ?? false

	readonly property string name: row.network?.name ?? ""

	// Qt does not elide rich text, so the marked-up name is only used while
	// there is something to mark. In the picker that costs nothing: at 520
	// wide the name column fits more characters than an SSID is allowed.
	readonly property string markedName: {
		const term = row.highlight;

		const escape = part => part.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;");

		if (term === "")
			return row.name;

		const at = row.name.toLowerCase().indexOf(term.toLowerCase());
		if (at < 0)
			return row.name;

		return escape(row.name.slice(0, at))
			+ "<span style=\"background-color:rgba(255,255,255,0.3)\">"
			+ escape(row.name.slice(at, at + term.length))
			+ "</span>"
			+ escape(row.name.slice(at + term.length));
	}

	height: row.compact ? 32 : 42
	radius: row.compact ? 14 : Theme.radiusRow

	opacity: row.unsupported ? 0.55 : 1.0

	color: row.selected ? Theme.glassChipSelected
		: row.connected ? Theme.glassChipActive
		: mouse.containsMouse ? Theme.glassControlHover
		: Theme.glassControl

	border.width: 1
	border.color: row.selected
		? Theme.glassChipSelectedBorder : Theme.glassControlBorder

	Behavior on color {
		ColorAnimation { duration: 120 }
	}

	// The design rings the selected row as well as brightening it. A ring
	// rather than a thicker border, for the same reason the text fields use
	// one: a border that grows on selection shifts every row below it.
	//
	// The design also puts a 1px inset highlight along the top edge. It is not
	// drawn here: at scale 2 a 1px inset lands on two physical pixels directly
	// under the border and reads as a doubled line, which is the same defect
	// that had to be taken out of GlassPanel.
	Rectangle {
		anchors.fill: parent
		anchors.margins: -3
		z: -1
		radius: row.radius + 3
		color: Theme.glassRowRing
		visible: row.selected
	}

	Row {
		anchors {
			left: parent.left
			right: trailing.left
			leftMargin: row.compact ? Theme.spacingM : Theme.spacingL - 2
			rightMargin: Theme.spacingS
			verticalCenter: parent.verticalCenter
		}

		spacing: Theme.spacingS - 2

		Text {
			anchors.verticalCenter: parent.verticalCenter
			text: row.highlight !== "" ? row.markedName : row.name
			textFormat: row.highlight !== "" ? Text.RichText : Text.PlainText
			elide: Text.ElideRight
			width: Math.min(implicitWidth, parent.width - 16)
			font.pixelSize: row.compact ? Theme.fontCaption : Theme.fontLead
			font.weight: row.selected ? Font.Bold : Font.DemiBold
			color: Theme.glassTextPrimary
		}

		LockIcon {
			anchors.verticalCenter: parent.verticalCenter
			visible: row.detail?.secured ?? false
			opacity: 0.6
			color: Theme.glassTextPrimary
		}
	}

	Row {
		id: trailing

		anchors {
			right: parent.right
			rightMargin: row.compact ? Theme.spacingM : Theme.spacingL - 2
			verticalCenter: parent.verticalCenter
		}

		spacing: Theme.spacingM

		// Only the picker has room to spell out what "locked" means.
		Text {
			anchors.verticalCenter: parent.verticalCenter
			visible: !row.compact && text !== ""
			text: row.detail?.security ?? ""
			font.pixelSize: Theme.fontBody
			font.weight: Font.DemiBold
			opacity: row.selected ? 0.8 : 0.7
			color: Theme.glassTextPrimary
		}

		SignalBars {
			anchors.verticalCenter: parent.verticalCenter
			level: row.bars
			color: Theme.glassTextPrimary
		}
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor

		// In the tile a click is the whole interaction. In the picker it picks
		// the row and Join commits, so that a scroll through twenty networks
		// cannot join one by accident - but a double click still means "this
		// one, now", which is what a list of things invites.
		onClicked: row.compact ? row.activated() : row.chosen()
		onDoubleClicked: row.activated()
	}
}
