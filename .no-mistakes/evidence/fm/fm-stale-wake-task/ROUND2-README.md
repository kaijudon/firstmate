# Round 2 live evidence (target bd21510)

- live-round2-head/: real watcher on a lab tmux pane (shell, agent exited, paused declared) -> supervision host with real Claude engine. Wake: `stale: lab:fm-held (paused 903s, ...) task=held`. Engine reported `--task held` on first try, 5 turns.
- live-round2-first-sight-head/: same lab with a live non-shell pane (`sleep`). Wake: `stale: lab:fm-held (task=held)`. Engine reported `--task held` on first try, 5 turns, never queried the pane name.
- live-round2-first-sight-base/: same first-sight lab with bin/fm-watch.sh and bin/fm-branch-prompt.sh from base 19fcbbd. Wake: bare `stale: lab:fm-held`. Engine first ran `fm-crew-state.sh lab:fm-held` -> "no metadata for lab:fm-held", then had to discover the task (7 turns).
- round2-watcher-and-daemon-consume.log: real watcher queue rows (steering-inbox unavailable-endpoint line and first-sight line) consumed by fm-supervise-daemon.sh handle_wake; both resolve to task `held` (.subsuper-paused-held).
- round2-daemon-parse-adversarial.log: parenthetical forms resolve to `held`; a bare-space suffix (`stale: lab:fm-held task=held`) would resolve to the bogus window `held task=held`.
- round2-teeth-fm-wake-queue-on-base-watch.log: updated fm-wake-queue first-sight assertion fails against the base watcher.
