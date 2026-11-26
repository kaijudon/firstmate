#!/usr/bin/env bash
# Live driver: real bin/fm-watch.sh, real tmux (private socket), disposable lab home.
# Usage: drive-watcher.sh <checkout-root> <label>
set -u
ROOT=$1; LABEL=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || exit 1
SOCK=$("$ROOT/bin/fm-lab-home.sh" tmux-dir "$LAB") || exit 1
export TMUX_TMPDIR=$SOCK; unset TMUX
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
cleanup() {
  [ -S "$SOCK/tmux-$(id -u)/default" ] && tmux -S "$SOCK/tmux-$(id -u)/default" kill-server 2>/dev/null
  "$ROOT/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1
  rm -rf "$LAB"
}
trap cleanup EXIT
tmux new-session -d -s lab -n fm-held -x 100 -y 30 'cat' || exit 1
tmux send-keys -t lab:fm-held 'idle, holding for the vendor' Enter
printf 'window=lab:fm-held\nproject=demo\nkind=ship\nharness=claude\nbackend=tmux\n' > "$LAB/state/held.meta"
watch_once() {  # <out> <timeout-s> [env...]
  local out=$1 t=$2; shift 2
  env FM_HOME="$LAB" FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$@" \
    timeout "$t" "$ROOT/bin/fm-watch.sh" > "$out" 2>"$out.err"
  echo "watcher exit=$? ($*)"; echo "--- wake line(s) printed:"; cat "$out"; echo "--- stderr:"; head -5 "$out.err"
}
drain_ack() {
  local err=$LAB/drain.err seq gen
  FM_HOME="$LAB" "$ROOT/bin/fm-wake-drain.sh" > "$LAB/drain.out" 2> "$err"
  echo "--- drain presented:"; cat "$LAB/drain.out"
  seq=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation .*$/\1/p' "$err")
  gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$err")
  [ -n "$seq" ] && FM_HOME="$LAB" "$ROOT/bin/fm-wake-drain.sh" --ack-through "$seq" --recovery-generation "$gen"
}
echo "=== [$LABEL] commit $(git -C "$ROOT" rev-parse --short HEAD); tmux $(tmux -V); pane command: $(tmux display-message -p -t lab:fm-held '#{pane_current_command}')"
echo "=== phase 1: worker declares a wait (paused:) - status signal"
printf 'paused [at=%s]: awaiting the vendor rate-limit reset\n' "$(date +%s)" >> "$LAB/state/held.status"
watch_once "$LAB/w1.out" 30
drain_ack
echo "=== phase 2: parked worker, unchanged pane - first-sight stale"
watch_once "$LAB/w2.out" 40 FM_PAUSE_RESURFACE_SECS=999
drain_ack
echo "=== phase 3: 12s of real time pass with recheck cadence FM_PAUSE_RESURFACE_SECS=10 - parked-wait recheck"
sleep 12
watch_once "$LAB/w3.out" 60 FM_PAUSE_RESURFACE_SECS=10
drain_ack
echo "=== wake queue rows (durable):"; cat "$LAB/state/.wake-queue" 2>/dev/null
echo "=== triage log:"; cat "$LAB/state/.watch-triage.log" 2>/dev/null
