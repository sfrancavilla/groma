#!/bin/sh
#
# What fprintd knows about this machine's reader, for FingerprintDialog.qml:
# one "key value" line each, and a "finger" line per enrolled finger.
#
# Prints nothing at all without fprintd, or without a reader libfprint can
# drive - the dialog reads that as "no reader". Nothing here claims the
# device, so it is safe to run while the lock screen is listening.

call() { gdbus call --system --dest net.reactivated.Fprint "$@" 2>/dev/null; }

device=$(call --object-path /net/reactivated/Fprint/Manager \
	--method net.reactivated.Fprint.Manager.GetDefaultDevice |
	sed -n "s/^(objectpath '\(.*\)',)$/\1/p")
[ -n "$device" ] || exit 0

# Properties come back as (<'value'>,) or (<13>,).
prop() {
	call --object-path "$device" --method org.freedesktop.DBus.Properties.Get \
		net.reactivated.Fprint.Device "$1" |
		sed -n "s/^(<'\{0,1\}\([^']*\)'\{0,1\}>,)$/\1/p"
}

echo "device $device"
echo "name $(prop name)"
echo "stages $(prop num-enroll-stages)"
echo "type $(prop scan-type)"

# Fails with NoEnrolledPrints when there are none, which prints nothing.
call --object-path "$device" --method net.reactivated.Fprint.Device.ListEnrolledFingers "$(id -un)" |
	grep -o "'[a-z-]*'" | tr -d "'" | sed 's/^/finger /'
