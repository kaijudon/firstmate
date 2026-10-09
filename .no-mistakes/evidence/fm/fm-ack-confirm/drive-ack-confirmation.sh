#!/usr/bin/env bash
# Live driver: real bin/fm-wake-drain.sh against a disposable marked lab FM_HOME.
# Usage: drive-ack-confirmation.sh <repo-dir>
# Wakes are enqueued through the product's own fm_wake_append (bin/fm-wake-lib.sh),
# the same entrypoint the watcher uses.
set -u
REPO=$1
cd "$REPO" || exit 1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
bin/fm-lab-home.sh create "$LAB" >/dev/null || { echo "lab create failed"; exit 1; }
trap 'rm -rf "$LAB"' EXIT

fm() {
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"
}
enq() { fm bash -c '. bin/fm-wake-lib.sh; fm_wake_append "$1" "$2" "$3"' _ "$@"; }
# Run drain, show stdout/stderr separately with exit code.
drain() {
  local out err rc=0
  out=$(mktemp); err=$(mktemp)
  echo "\$ bin/fm-wake-drain.sh $*"
  fm bin/fm-wake-drain.sh "$@" >"$out" 2>"$err" || rc=$?
  echo "  [stdout]"; sed 's/^/    /' "$out"
  echo "  [stderr]"; sed 's/^/    /' "$err"
  echo "  [exit $rc]"
  LAST_ERR=$(cat "$err"); LAST_RC=$rc
  rm -f "$out" "$err"
}
ack_cmd() { printf '%s\n' "$LAST_ERR" | sed -n 's/^WAKE_ACK_REQUIRED:.* run //p' | tail -1; }
queue_rows() { awk 'END{print NR}' "$LAB/state/.wake-queue" 2>/dev/null || echo 0; }

echo "== commit $(git rev-parse --short HEAD) | FM_HOME=lab"
echo
echo "== S1: one wake -> drain -> run the printed WAKE_ACK_REQUIRED command"
enq signal confirm 'signal: confirm.status'
drain
CMD=$(ack_cmd); echo "printed ack command: $CMD"
SEQ=$(printf '%s' "$CMD" | sed -n 's/.*--ack-through \([0-9]*\).*/\1/p')
GEN=$(printf '%s' "$CMD" | sed -n 's/.*--recovery-generation \([^ ]*\).*/\1/p')
drain --ack-through "$SEQ" --recovery-generation "$GEN"
echo "queue rows after ack: $(queue_rows)"
echo
echo "== S2: repeat the same acknowledgement (nothing left, nothing pending)"
drain --ack-through "$SEQ" --recovery-generation "$GEN"
echo
echo "== S3: three wakes -> drain -> ack the batch"
enq signal a 'signal: a.status'
enq signal b 'signal: b.status'
enq signal c 'signal: c.status'
drain
CMD=$(ack_cmd); echo "printed ack command: $CMD"
SEQ=$(printf '%s' "$CMD" | sed -n 's/.*--ack-through \([0-9]*\).*/\1/p')
GEN=$(printf '%s' "$CMD" | sed -n 's/.*--recovery-generation \([^ ]*\).*/\1/p')
drain --ack-through "$SEQ" --recovery-generation "$GEN"
echo "queue rows after ack: $(queue_rows)"
echo
echo "== S4 (adversarial): stale ack below a presented, still-pending wake"
OLD_SEQ=$SEQ
enq signal d 'signal: d.status'
drain
NEW_CMD=$(ack_cmd); echo "printed ack command: $NEW_CMD"
GEN=$(printf '%s' "$NEW_CMD" | sed -n 's/.*--recovery-generation \([^ ]*\).*/\1/p')
drain --ack-through "$OLD_SEQ" --recovery-generation "$GEN"
echo "queue rows after stale ack: $(queue_rows)"
echo
echo "== S5 (adversarial): malformed --ack-through"
drain --ack-through notanumber --recovery-generation "$GEN"
echo "queue rows after malformed ack: $(queue_rows)"
echo
echo "== S6 (adversarial): ack under a recovery generation that no longer matches the marker"
drain --ack-through 5 --recovery-generation "$GEN"
enq signal e 'signal: e.status'
drain
CMD=$(ack_cmd); echo "printed ack command: $CMD"
SEQ=$(printf '%s' "$CMD" | sed -n 's/.*--ack-through \([0-9]*\).*/\1/p')
drain --ack-through "$SEQ" --recovery-generation 1.1.superseded
echo "queue rows after ack: $(queue_rows)"
echo "stderr line count: $(printf '%s\n' "$LAST_ERR" | grep -c .)"
