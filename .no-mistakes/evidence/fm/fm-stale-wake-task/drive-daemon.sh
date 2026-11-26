#!/usr/bin/env bash
# Feed the watcher's real emitted stale lines to the real daemon handle_wake.
set -u
ROOT=$1; . "$ROOT/tests/wake-helpers.sh"
export FM_TEST_DAEMON_SOURCED=1; . "$ROOT/bin/fm-supervise-daemon.sh"
T=$(mktemp -d /tmp/fm-daemon-drive.XXXXXX); trap 'rm -rf "$T"' EXIT
run() {  # <label> <reason>
  local s="$T/$1/state" key; mkdir -p "$s"
  printf 'window=lab:fm-held\nbackend=tmux\n' > "$s/held.meta"
  printf 'paused: awaiting the vendor rate-limit reset\n' > "$s/held.status"
  key=$(printf '%s' held | tr ':/.' '___'); date +%s > "$s/.subsuper-stale-$key"
  LOG="$T/$1/daemon.log" FM_STATE_OVERRIDE="$s" handle_wake "$2" "$s"
  printf '[%s]\n  wake: %s\n  pause marker recorded: %s | wedge marker kept: %s | escalations: %s\n  daemon log: %s\n' "$1" "$2" \
    "$([ -e "$s/.subsuper-paused-$key" ] && echo yes || echo NO)" "$([ -e "$s/.subsuper-stale-$key" ] && echo YES || echo no)" \
    "$(wc -c < "$s/.subsuper-escalations" 2>/dev/null || echo 0) bytes" "$(tr '\n' '|' < "$T/$1/daemon.log" 2>/dev/null)"
}
run first-sight 'stale: lab:fm-held (task=held)'
run parked-recheck 'stale: lab:fm-held (paused 23s, awaiting external - declared pause, rechecked on a long cadence not a wedge; confirm the wait still holds) task=held'
run adversarial-bare-suffix 'stale: lab:fm-held task=held'
