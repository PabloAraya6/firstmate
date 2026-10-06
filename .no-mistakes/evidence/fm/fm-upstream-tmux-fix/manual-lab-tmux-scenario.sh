#!/usr/bin/env bash
# Independent manual live drive of the product (no test file), against a
# stand-in operator tmux server on a private socket. Proves the reported
# failure mode is fixed: a lab/suite cleanup kill-server that runs with no
# private tmux directory must never reach the "operator" server.
set -u
ROOT=$1
LABHOME="$ROOT/bin/fm-lab-home.sh"
TMP=$(mktemp -d /tmp/fm-manual.XXXXXX)
OPERATOR="$TMP/operator"
SOCKET="$OPERATOR/default"
mkdir -p "$OPERATOR"
fail() { echo "FAIL: $*" >&2; exit 1; }

LAB2_PID=
cleanup() {
  [ -n "$LAB2_PID" ] && kill "$LAB2_PID" 2>/dev/null || true
  tmux -S "$SOCKET" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# Stand-in for the operator's real default server with live worker panes.
tmux -S "$SOCKET" -f /dev/null new-session -d -s firstmate 'exec sleep 600' \
  || fail "could not start stand-in operator server"
OP_PID=$(tmux -S "$SOCKET" display-message -p '#{pid}')
echo "operator server pid=$OP_PID sessions=$(tmux -S "$SOCKET" list-sessions | wc -l)"

echo
echo "== A. suite inherits operator TMUX/TMUX_PANE, then runs bare tmux kill-server =="
env -u FM_TEST_TMUX_TMPDIR -u TMUX_TMPDIR \
  TMUX="$SOCKET,$OP_PID,0" TMUX_PANE=0 \
  bash -c '. "$1/tests/lib.sh"; tmux kill-server' _ "$ROOT" 2>&1
if tmux -S "$SOCKET" has-session -t =firstmate 2>/dev/null; then
  echo "PASS: operator server survived the suite's bare kill-server"
else
  fail "operator server was killed by a suite that inherited TMUX"
fi

echo
echo "== B. fm-lab-home.sh tmux refuses with no private dir (before tmux-dir) =="
LAB=$("$LABHOME" create "$TMP/labB") || fail "create lab"
env TMUX="$SOCKET,$OP_PID,0" "$LABHOME" tmux "$LAB" kill-server 2>&1
rc=$?
echo "exit=$rc"
[ "$rc" -ne 0 ] || fail "expected refusal before any tmux-dir exists"
tmux -S "$SOCKET" has-session -t =firstmate 2>/dev/null \
  || fail "operator server died on the no-private-dir refusal"
echo "PASS: refused and operator server intact"

echo
echo "== C. fm-lab-home.sh tmux reaches only the lab server =="
SOCKET_DIR=$("$LABHOME" tmux-dir "$LAB") || fail "tmux-dir"
echo "lab socket dir=$SOCKET_DIR"
env TMUX="$SOCKET,$OP_PID,0" TMUX_PANE=0 "$LABHOME" tmux "$LAB" -f /dev/null new-session -d -s primary 'exec sleep 600' \
  || fail "start lab server"
env TMUX="$SOCKET,$OP_PID,0" "$LABHOME" tmux "$LAB" has-session -t =primary \
  || fail "lab session unreachable"
env TMUX="$SOCKET,$OP_PID,0" "$LABHOME" tmux "$LAB" kill-server \
  || fail "stop lab server"
tmux -S "$SOCKET" has-session -t =firstmate 2>/dev/null \
  || fail "stopping the lab server killed the operator server"
echo "PASS: reached only the lab server; operator server intact"

echo
echo "== D. the reported failure: cleanup kill-server after the private dir is gone =="
LAB2=$("$LABHOME" create "$TMP/labD") || fail "create lab2"
DIR2=$("$LABHOME" tmux-dir "$LAB2") || fail "tmux-dir lab2"
env "$LABHOME" tmux "$LAB2" -f /dev/null new-session -d -s primary 'exec sleep 600' \
  || fail "start lab2 server"
LAB2_PID=$("$LABHOME" tmux "$LAB2" display-message -p '#{pid}')
# A cleanup trap that runs after teardown already deleted the directory: the
# private dir is gone but the recorded record may still point at a missing path.
rm -rf "$DIR2"
env TMUX="$SOCKET,$OP_PID,0" "$LABHOME" tmux "$LAB2" kill-server 2>&1
rc=$?
echo "exit=$rc"
[ "$rc" -ne 0 ] || fail "expected refusal once the private dir is gone"
tmux -S "$SOCKET" has-session -t =firstmate 2>/dev/null \
  || fail "operator server died when the private dir was already gone"
echo "PASS: refused after the private dir vanished; operator server intact"

echo
echo "ALL MANUAL SCENARIOS PASSED"
