#!/usr/bin/env bash
# Drive the real bin/fm-watch.sh against a disposable lab home with a parked
# worker in a real tmux pane on a private socket. Prints each watcher run's
# printed reason and queued wake record.
# Usage: direct-watcher.sh <worktree> [<rev>]   (rev: take bin/fm-watch.sh from it)
set -u
SRC=$1 REV=${2:-}
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LAB=$(cd -P "$LAB" && pwd -P)
SOCK="$LAB/tmux.sock"
cleanup() { tmux -S "$SOCK" kill-server 2>/dev/null; rm -rf "$LAB"; }
trap cleanup EXIT
git -C "$SRC" ls-files -z -co --exclude-standard | (cd "$SRC" && tar --null -T - -cf -) | (cd "$LAB" && tar -xf -)
[ -z "$REV" ] || git -C "$SRC" show "$REV:bin/fm-watch.sh" > "$LAB/bin/fm-watch.sh"
mkdir -p "$LAB/state" "$LAB/config"
tmux -S "$SOCK" new-session -d -s lab -n fm-held -x 200 -y 50 "sleep 999999"
export TMUX="$SOCK,$(tmux -S "$SOCK" display -p '#{pid}'),0"
mkdir -p "$LAB/wt"; git -C "$LAB/wt" init -q -b fm/held
git -C "$LAB/wt" -c user.name=t -c user.email=t@e.invalid commit -q --allow-empty -m base
printf 'project=demo\nwindow=lab:fm-held\nbackend=tmux\nharness=claude\nkind=ship\nworktree=%s\n' "$LAB/wt" > "$LAB/state/held.meta"
printf 'paused: awaiting the vendor rate-limit reset\n' > "$LAB/state/held.status"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS
export FM_HOME="$LAB" FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999
run() {  # <label> [env...]
  local label=$1; shift
  echo "== watcher run: $label"
  : > "$LAB/state/.wake-queue" 2>/dev/null
  (cd "$LAB" && env "$@" timeout 40 bin/fm-watch.sh 2>&1 | grep -E '^(signal|stale|check):' | head -3); echo "exit=${PIPESTATUS[0]}"
  echo "queued: $(cut -f5 "$LAB/state/.wake-queue" 2>/dev/null)"
  (cd "$LAB" && bin/fm-wake-drain.sh >/dev/null 2>&1; true)
}
run "1 status signal" FM_PAUSE_RESURFACE_SECS=999999
run "2 first-sight stale" FM_PAUSE_RESURFACE_SECS=999999
sleep 6
run "3 aged declared pause recheck" FM_PAUSE_RESURFACE_SECS=5
