#!/usr/bin/env bash
# Live driver: real fm-supervision-host.sh + real fm-watch.sh + real tmux + real
# Claude engine, in a disposable lab copy of the checkout (away posture).
# Adapted from tests/fm-supervision-host-live-e2e.test.sh. Usage: drive-host.sh <root> <out-dir>
set -u
ROOT=$1; OUT=$2; mkdir -p "$OUT"
LAB=$(mktemp -d /tmp/fm-hostlab.XXXXXX); LAB=$(cd -P "$LAB" && pwd -P); FM="$LAB/fm"
SOCK=$(mktemp -d /tmp/fml.XXXXXX); chmod 700 "$SOCK"
export TMUX_TMPDIR=$SOCK; unset TMUX
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
unset FM_SUPERVISION_ENGINE_CLAUDE_BIN FM_SUPERVISION_ACTOR FM_BRANCH_REPORT_TURN FM_LEASE_HOLDER_PID PI_CODING_AGENT
mkdir -p "$LAB/harness"; ln -s /bin/bash "$LAB/harness/claude"
stop_lab() {
  local pid
  pid=$(awk -F '\t' '$1 == "host" { print $2; exit }' "$FM/state/.supervision-host" 2>/dev/null)
  [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null; sleep 3
  pid=$(cat "$FM/state/.watch.lock/pid" 2>/dev/null || true)
  [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null
  while IFS= read -r pid; do [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null; done < "$LAB/claude-pids" 2>/dev/null
  [ -S "$SOCK/tmux-$(id -u)/default" ] && tmux -S "$SOCK/tmux-$(id -u)/default" kill-server 2>/dev/null
  cp "$FM/state/.supervision-host.log" "$OUT/supervision-host.log" 2>/dev/null
  cp "$FM/state/branch-outcomes.jsonl" "$OUT/branch-outcomes.jsonl" 2>/dev/null
  cp "$FM/state/.supervision-host-receipts" "$OUT/receipts.tsv" 2>/dev/null
  cp "$FM/state/.wake-queue" "$OUT/wake-queue-final.tsv" 2>/dev/null
  cp "$LAB/host.out" "$OUT/host.out" 2>/dev/null
  echo "$FM" > "$OUT/lab-path.txt"
  sed -n 's/^session=//p' "$FM/state/.supervision-host-engine" > "$OUT/engine-session.txt" 2>/dev/null
  rm -rf "$LAB" "$SOCK"
}
trap stop_lab EXIT
mkdir -p "$FM"
git -C "$ROOT" ls-files -z -co --exclude-standard | (cd "$ROOT" && tar --null -T - -cf -) | (cd "$FM" && tar -xf -)
git -C "$FM" init -q -b main; git -C "$FM" add -A >/dev/null
git -C "$FM" -c user.name=fmtest -c user.email=fmtest@example.invalid commit -q -m lab
mkdir -p "$FM/state" "$FM/config"; : > "$FM/config/supervision-host"
tmux new-session -d -s lab -n fm-held -x 100 -y 30 'cat' || exit 1
tmux send-keys -t lab:fm-held 'idle, holding for the vendor rate-limit reset' Enter
printf 'window=lab:fm-held\nproject=demo\nkind=ship\nharness=claude\nbackend=tmux\n' > "$FM/state/held.meta"
FM_HOME="$FM" "$FM/bin/fm-afk-contract.sh" enter --words 'Watch the fleet. Merge nothing, dispatch nothing, and do not steer or stop any worker.' >/dev/null || { echo "away posture failed"; exit 1; }
export FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_PAUSE_RESURFACE_SECS=${RESURFACE:-45}
FM_HOME="$FM" "$LAB/harness/claude" -c '
  printf "%s\n" "$$" > "$FM_HOME/state/.lock"
  printf "%s\n" "$$" >> "$1/claude-pids"
  "$FM_HOME/bin/fm-supervision-host.sh" park > "$1/host.out" 2>&1
  printf "%s\n" "$?" > "$1/host.rc"
' _ "$LAB" 2>> "$LAB/harness.err" &
wait_until() { local limit=$1 i=0; shift; while [ "$i" -lt "$limit" ]; do "$@" && return 0; sleep 0.5; i=$((i+1)); done; return 1; }
watcher_live() { local p; p=$(cat "$FM/state/.watch.lock/pid" 2>/dev/null) || return 1; [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
settled() { [ "$(grep -cE '	(handled|failed)	' "$FM/state/.supervision-host.log" 2>/dev/null || true)" -ge "$1" ] || [ -s "$LAB/host.rc" ]; }
stale_settled() { [ "$(grep -E '	(handled|failed)	' "$FM/state/.supervision-host.log" 2>/dev/null | grep -c 'stale: lab:fm-held')" -ge "$1" ] || [ -s "$LAB/host.rc" ]; }
wait_until 60 watcher_live || { echo "host never started a watcher: $(cat "$LAB/host.out")"; exit 1; }
echo "host parked, watcher live; claude $(claude --version | head -1)"
printf 'paused [at=%s]: awaiting the vendor rate-limit reset\n' "$(date +%s)" >> "$FM/state/held.status"
wait_until "${T1:-360}" stale_settled 1; echo "after wait 1: stale turns settled >=1? rc=$?"
wait_until "${T2:-300}" stale_settled 2; echo "after wait 2: stale turns settled >=2? rc=$?"
echo "--- host log"; cat "$FM/state/.supervision-host.log"
echo "--- host.rc: $(cat "$LAB/host.rc" 2>/dev/null)"; echo "--- host.out"; cat "$LAB/host.out"
echo "--- outcomes"; cat "$FM/state/branch-outcomes.jsonl" 2>/dev/null
echo "--- watch triage"; cat "$FM/state/.watch-triage.log" 2>/dev/null | tail -20
