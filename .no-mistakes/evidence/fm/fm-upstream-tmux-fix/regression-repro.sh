#!/usr/bin/env bash
# Regression reproduction for the reported incident: a test-suite cleanup ran
# `tmux kill-server` while the private terminal directory was already gone, so
# tmux addressed the operator's own default server and killed every worker.
# Uses a stand-in operator server on a private socket, never the real default.
set -u
ROOT=$1
TMP=$(mktemp -d /tmp/fm-regress.XXXXXX)
OPERATOR="$TMP/operator"
SOCKET="$OPERATOR/default"
mkdir -p "$OPERATOR"
fail() { echo "FAIL: $*" >&2; exit 1; }
cleanup() { tmux -S "$SOCKET" kill-server 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

start_operator() {
  tmux -S "$SOCKET" -f /dev/null new-session -d -s firstmate 'exec sleep 600' \
    || fail "could not start stand-in operator server"
  tmux -S "$SOCKET" display-message -p '#{pid}'
}

echo "== BEFORE FIX: suite inherits operator TMUX, private dir gone, bare tmux kill-server =="
OP_PID=$(start_operator)
# The pre-fix suite inherited the operator's TMUX and addressed its lab through
# TMUX_TMPDIR alone; with that directory gone, a bare kill-server used the
# inherited socket.
env -u TMUX_TMPDIR TMUX="$SOCKET,$OP_PID,0" TMUX_PANE=0 \
  bash -c 'tmux kill-server' 2>&1
if tmux -S "$SOCKET" has-session -t =firstmate 2>/dev/null; then
  echo "UNEXPECTED: did not reproduce the operator kill"
else
  echo "REPRODUCED: with inherited TMUX and no private dir, kill-server killed the operator server"
fi
tmux -S "$SOCKET" kill-server 2>/dev/null || true

echo
echo "== AFTER FIX: tests/lib.sh drops the inherited TMUX, same bare kill-server =="
OP_PID=$(start_operator)
env -u TMUX_TMPDIR TMUX="$SOCKET,$OP_PID,0" TMUX_PANE=0 \
  bash -c '. "$1/tests/lib.sh"; tmux kill-server' _ "$ROOT" 2>&1
tmux -S "$SOCKET" has-session -t =firstmate 2>/dev/null \
  && echo "PASS: fixed lib.sh protected the inherited operator server" \
  || fail "fixed lib.sh failed to protect the inherited operator server"
