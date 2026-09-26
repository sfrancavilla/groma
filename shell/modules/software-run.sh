#!/usr/bin/env bash
# Run a package command in the terminal the Software window opened, and
# leave a log the window can tail: every line of output, then "exit:N".
#
#   software-run.sh <log> <command> [args...]
#
# The log starts with "pid:N" - the process group the window signals on
# Cancel. pacman takes SIGINT safely before it commits and ignores it
# during, which is the behaviour Cancel should have.
log="$1"; shift
: > "$log"
set -m
echo "pid:$$" >> "$log"
printf '\033]0;Software\007'
echo "\$ $*"
"$@" 2>&1 | tee -a "$log"
code=${PIPESTATUS[0]}
echo "exit:$code" >> "$log"
echo
if [ "$code" -eq 0 ]; then echo "Done. This window closes in a moment."; sleep 2
else echo "Finished with code $code. Press Enter to close."; read -r; fi
