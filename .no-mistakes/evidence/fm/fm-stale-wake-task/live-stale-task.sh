#!/usr/bin/env bash
# Live check for firstmate issue #6932 item 1: a parked worker's stale recheck
# must name the task id, so the supervision host's real Claude engine reports
# on the task the first time.
#
# Usage: live-parked-stale.sh <worktree> <out-dir> [<rev-for-watch-and-prompt>]
# With a rev, bin/fm-watch.sh and bin/fm-branch-prompt.sh come from that rev
# (pre-fix reproduction); without one, the worktree tree is used as-is.
# Mirrors tests/fm-supervision-host-live-e2e.test.sh's lab layout, but the wake
# is a declared-pause stale recheck from a real tmux pane on a private socket.
set -u
SRC=$1 OUT=$2 REV=${3:-}
mkdir -p "$OUT"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-stale-task-live.XXXXXX"); LAB=$(cd -P "$LAB" && pwd -P)
FM="$LAB/fm" SOCK="$LAB/tmux.sock"
log() { printf '%s %s\n' "$(date +%T)" "$*" | tee -a "$OUT/driver.log"; }

stop_lab() {
  local pid
  if [ -f "$FM/state/.supervision-host" ]; then
    pid=$(awk -F '\t' '$1 == "host" { print $2; exit }' "$FM/state/.supervision-host")
    [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true
    sleep 2
  fi
  pid=$(cat "$FM/state/.watch.lock/pid" 2>/dev/null || true)
  [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true
  [ -n "${HOLDER:-}" ] && kill -TERM "$HOLDER" 2>/dev/null
  tmux -S "$SOCK" kill-server 2>/dev/null || true
  # Keep the evidence, drop the lab.
  for f in .supervision-host.log .wake-queue branch-outcomes.jsonl .watch-triage.log .supervision-host-engine .supervision-host-receipts; do
    [ -e "$FM/state/$f" ] && cp "$FM/state/$f" "$OUT/state$f" 2>/dev/null
  done
  cp "$LAB/host.out" "$OUT/host.out" 2>/dev/null
  rm -rf "$LAB"
}
trap stop_lab EXIT

mkdir -p "$FM"
git -C "$SRC" ls-files -z -co --exclude-standard | (cd "$SRC" && tar --null -T - -cf -) | (cd "$FM" && tar -xf -)
if [ -n "$REV" ]; then
  git -C "$SRC" show "$REV:bin/fm-watch.sh" > "$FM/bin/fm-watch.sh"
  git -C "$SRC" show "$REV:bin/fm-branch-prompt.sh" > "$FM/bin/fm-branch-prompt.sh"
  log "using bin/fm-watch.sh and bin/fm-branch-prompt.sh from $REV"
fi
git -C "$FM" init -q -b main && git -C "$FM" add -A >/dev/null
git -C "$FM" -c user.name=fmtest -c user.email=fmtest@example.invalid commit -q -m lab
mkdir -p "$FM/state" "$FM/config"
: > "$FM/config/supervision-host"
log "lab=$LAB"

# A real parked pane whose agent is still LIVE (a non-shell foreground process),
# with a declared pause, so pause_state_class answers none and the first-sight
# wake comes from surface_nonterminal_stale.
tmux -S "$SOCK" new-session -d -s lab -n fm-held -x 200 -y 50 \
  "sleep 999999"
TMUX_ENV="$SOCK,$(tmux -S "$SOCK" display -p '#{pid}'),0"
mkdir -p "$LAB/wt"; git -C "$LAB/wt" init -q -b fm/held
git -C "$LAB/wt" -c user.name=t -c user.email=t@e.invalid commit -q --allow-empty -m base
printf 'project=demo\nwindow=lab:fm-held\nbackend=tmux\nharness=claude\nkind=ship\nworktree=%s\n' "$LAB/wt" > "$FM/state/held.meta"
printf 'paused: holding for the upstream tool release\n' > "$FM/state/held.status"
[ -n "${FIRST_SIGHT:-}" ] || touch -m -d "@$(( $(date +%s) - 900 ))" "$FM/state/held.status"
# Prime the status signal suppressor, so the only wake is the stale recheck.
(
  cd "$FM" || exit 1
  # shellcheck disable=SC1091
  . bin/fm-classify-lib.sh
  f=state/held.status
  printf 'v2\t%s\t%s@%s' "$(status_observed_signature "$f")" "$(LC_ALL=C wc -c < "$f" | tr -d '[:space:]')" \
    "$(_fm_open_decisions_file_ident "$f")" > state/.seen-held_status
) || { log "could not prime the status suppressor"; exit 1; }
FM_HOME="$FM" "$FM/bin/fm-afk-contract.sh" enter --words 'Watch the fleet. Merge nothing and dispatch nothing.' >/dev/null \
  || { log "could not record away posture"; exit 1; }

export FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_PAUSE_RESURFACE_SECS=240
unset FM_SUPERVISION_ENGINE_CLAUDE_BIN FM_SUPERVISION_ACTOR FM_BRANCH_REPORT_TURN FM_LEASE_HOLDER_PID
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE PI_CODING_AGENT
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS
mkdir -p "$LAB/harness"; ln -s /bin/bash "$LAB/harness/claude"
TMUX="$TMUX_ENV" FM_HOME="$FM" "$LAB/harness/claude" -c '
  printf "%s\n" "$$" > "$FM_HOME/state/.lock"
  "$FM_HOME/bin/fm-supervision-host.sh" park > "$1/host.out" 2>&1
  printf "%s\n" "$?" > "$1/host.rc"
' _ "$LAB" 2>> "$OUT/harness.err" &
HOLDER=$!

i=0
while [ "$i" -lt 3000 ]; do
  n=$(grep -cE '	(handled|failed)	' "$FM/state/.supervision-host.log" 2>/dev/null); n=${n:-0}
  if [ "$n" -ge 1 ] || [ -s "$LAB/host.rc" ]; then break; fi
  sleep 0.2; i=$((i + 1))
done
log "settled after ~$((i / 5))s"
log "lab project dir for Claude transcripts: $FM"
printf '%s\n' "$FM" > "$OUT/lab-path"
