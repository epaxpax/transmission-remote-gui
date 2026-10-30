#!/usr/bin/env bash
# CI only: answers the macOS privacy prompts ("Allow … to find devices on local networks?")
# that pop up mid-run on a fresh runner — they are modal and would swallow the suites' clicks.
# ONE long-lived helper instance polls UserNotificationCenter (launching the helper over and
# over would close the suites' open context menus). Start with `&`; stop with `--stop`.
set -u
DIR="${RUNNER_TEMP:-/tmp}/dismiss"
if [ "${1:-}" = --stop ]; then pkill -f "$DIR/d.applescript"; exit 0; fi
mkdir -p "$DIR"
cat > "$DIR/d.applescript" <<'AS'
repeat
  tell application "System Events"
    if exists process "UserNotificationCenter" then
      repeat with w in windows of process "UserNotificationCenter"
        try
          if exists button "Allow" of w then click button "Allow" of w
        end try
      end repeat
    end if
  end tell
  delay 1
end repeat
AS
exec open -g -W -n -a "/Applications/TRGUI UITest Helper.app" --args "$DIR/d.applescript" "$DIR/r.json"
