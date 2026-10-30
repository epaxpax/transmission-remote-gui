#!/usr/bin/env bash
# CI only (GitHub-hosted macOS runners have SIP off): grants the UI-test helper the
# Accessibility / event-posting / System Events rights a person would toggle by hand.
set -euo pipefail
ID="io.github.epaxpax.TRGUIUITestHelper"
grant() {   # [sudo] db service [indirect object]
    local run=(); [ "$1" = sudo ] && { run=(sudo); shift; }
    ${run[@]+"${run[@]}"} sqlite3 "$1" "INSERT OR REPLACE INTO access
        (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags, last_modified)
        VALUES ('$2', '$ID', 0, 2, 4, 1, '${3:-UNUSED}', 0, CAST(strftime('%s','now') AS INTEGER));"
}
SYS="/Library/Application Support/com.apple.TCC/TCC.db"
USR="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
grant sudo "$SYS" kTCCServiceAccessibility
grant sudo "$SYS" kTCCServicePostEvent
grant "$USR" kTCCServiceAppleEvents com.apple.systemevents
grant "$USR" kTCCServiceAppleEvents com.apple.finder
grant "$USR" kTCCServicePostEvent
