#!/bin/sh
# One screen recording, for Capture.qml.
#
# The recorder runs here and not as the shell's own child, so that saving a
# QML file - which reloads the shell and ends every process it started - does
# not cut a recording off half-written. The shell finds out what is going on
# from two files beside the state path:
#
#   <state>        while recording: pid, start time, the file, its poster
#   <state>.done   once it has stopped: exit code, the file, its poster
#   <state>.log    what the recorder said, for when it fails
#
# capture-record.sh <state> <file> <poster> <gpu-screen-recorder arguments...>

state=$1
file=$2
poster=$3
shift 3

rm -f "$state.done"
gpu-screen-recorder "$@" -o "$file" 2>"$state.log" &
pid=$!
printf '%s\n%s\n%s\n%s\n' "$pid" "$(date +%s)" "$file" "$poster" >"$state"

# SIGINT to the recorder is "stop and save"; the shell sends it to $pid.
wait "$pid"
code=$?

# Done before the state goes, so the shell never sees neither.
printf '%s\n%s\n%s\n' "$code" "$file" "$poster" >"$state.done"
rm -f "$state"
