#!/usr/bin/env bash
# Real watcher on a lab parked pane (idle shell, agent exited after a declared
# pause) with an aged unhandled steering-inbox message; then the legacy
# supervise daemon's handle_wake consumes each real queued line.
set -u
SRC=$1
LAB=$(mktemp -d /tmp/fm-wd.XXXXXX); FM=$LAB/fm; SOCK=$LAB/tmux.sock
trap 'tmux -S "$SOCK" kill-server 2>/dev/null; rm -rf "$LAB"' EXIT
mkdir -p "$FM"
git -C "$SRC" ls-files -z -co --exclude-standard | (cd "$SRC" && tar --null -T - -cf -) | (cd "$FM" && tar -xf -)
git -C "$FM" init -q -b main && git -C "$FM" add -A >/dev/null && git -C "$FM" -c user.name=t -c user.email=t@e.invalid commit -q -m lab
mkdir -p "$FM/state" "$FM/config" "$LAB/wt"
git -C "$LAB/wt" init -q -b fm/held; git -C "$LAB/wt" -c user.name=t -c user.email=t@e.invalid commit -q --allow-empty -m base
tmux -S "$SOCK" new-session -d -s lab -n fm-held -x 200 -y 50 "env PS1='\$ ' bash --norc --noprofile -i"
export TMUX="$SOCK,$(tmux -S "$SOCK" display -p '#{pid}'),0"
printf 'project=demo\nwindow=lab:fm-held\nbackend=tmux\nharness=claude\nkind=ship\nworktree=%s\n' "$LAB/wt" > "$FM/state/held.meta"
printf 'paused: holding for the upstream tool release\n' > "$FM/state/held.status"
touch -m -d "@$(( $(date +%s) - 900 ))" "$FM/state/held.status"
( cd "$FM"; . bin/fm-classify-lib.sh; f=state/held.status
  printf 'v2\t%s\t%s@%s' "$(status_observed_signature "$f")" "$(LC_ALL=C wc -c < "$f" | tr -d '[:space:]')" "$(_fm_open_decisions_file_ident "$f")" > state/.seen-held_status )
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS
if [ "${WITH_INBOX:-1}" = 1 ]; then
  rec=$(cd "$FM" && FM_HOME="$FM" bash -c '. bin/fm-task-inbox-lib.sh && fm_task_inbox_write "$1/state" held "please re-run the release check"' _ "$FM")
  touch -m -d "@$(( $(date +%s) - 900 ))" "$rec"
fi
FM_HOME="$FM" FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_PAUSE_RESURFACE_SECS=240 FM_TASK_INBOX_GRACE_SECS=0 \
  timeout 60 "$FM/bin/fm-watch.sh" > "$LAB/watch.out" 2>"$LAB/watch.err"
echo "=== real watcher stdout (rc=$?):"; cat "$LAB/watch.out"
echo "=== queued stale rows (payload column):"; cut -f5 "$FM/state/.wake-queue"
echo "=== daemon handle_wake on each queued payload:"
while IFS=$'\t' read -r _e _s _k _key payload; do
  ( export FM_HOME="$FM" FM_TEST_DAEMON_SOURCED=1 FM_ESCALATE_BATCH_SECS=999999
    cd "$FM" && . bin/fm-supervise-daemon.sh
    LOG_OUT=$(handle_wake "$payload" "$FM/state" 2>&1); echo "handle_wake rc=$?"
    grep -F -- "$payload" "$FM/state/.subsuper.log" 2>/dev/null | tail -n 1 | sed 's/^/daemon log: /'
    ls -a "$FM/state" | grep -E '^\.subsuper-(pause|stale)' | sed 's/^/daemon marker: /'
    [ -s "$FM/state/.subsuper-escalations" ] && sed 's/^/escalation buffer: /' "$FM/state/.subsuper-escalations"
    printf '%s\n' "$LOG_OUT" | sed '/^$/d; s/^/daemon output: /' | tail -3 )
  rm -f "$FM/state/.subsuper-escalations"
  echo ---
done < "$FM/state/.wake-queue"
