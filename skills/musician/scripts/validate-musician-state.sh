#!/bin/bash
# validate-musician-state.sh
#
# Validates database consistency for an musician's task.
# Run by the musician at any time, or by the conductor to spot-check.
#
# Usage: bash validate-musician-state.sh <task_id> [session_id]
#   task_id    — The task to validate (e.g. task-03)
#   session_id — Optional; pass explicitly (CLAUDE_SESSION_ID is a system prompt value, not an env var)
#
# Exit codes: 0 = healthy, 1 = issues found

set -euo pipefail

# --- Arguments ---
TASK_ID="${1:-}"
# NOTE: CLAUDE_SESSION_ID is a system prompt value, not a bash env var.
# Always pass session_id explicitly as the second argument.
SESSION_ID="${2:-}"

if [[ -z "$TASK_ID" ]]; then
  echo "Usage: bash validate-musician-state.sh <task_id> [session_id]"
  exit 2
fi

# --- Config ---
PROJECT_DIR="${PROJECT_DIR:-/home/kyle/claude/remindly}"
DB_PATH="${DB_PATH:-$PROJECT_DIR/comms.db}"

# Valid states (musician + conductor)
VALID_STATES="watching working needs_review error complete exited review_approved review_failed fix_proposed exit_requested"

ISSUES=0

# --- Helper: query DB ---
db_query() {
  sqlite3 -separator '|' "$DB_PATH" "$1" 2>/dev/null
}

# --- Check: DB exists ---
if [[ ! -f "$DB_PATH" ]]; then
  echo "=== Musician State Validation: $TASK_ID ==="
  echo "ERROR: Database not found at $DB_PATH"
  echo "=== RESULT: DB MISSING ==="
  exit 1
fi

# --- Check 1: Task exists ---
ROW=$(db_query "SELECT task_id, state, session_id, worked_by, last_heartbeat, retry_count FROM orchestration_tasks WHERE task_id='$TASK_ID';")

if [[ -z "$ROW" ]]; then
  echo "=== Musician State Validation: $TASK_ID ==="
  echo "ERROR: No task found with task_id=$TASK_ID"
  echo "=== RESULT: TASK NOT FOUND ==="
  exit 1
fi

# Parse fields
IFS='|' read -r T_ID T_STATE T_SESSION T_WORKED T_HEARTBEAT T_RETRY <<< "$ROW"

echo "=== Musician State Validation: $TASK_ID ==="

# --- Check 2: Session match ---
if [[ -n "$SESSION_ID" ]]; then
  if [[ "$T_SESSION" == "$SESSION_ID" ]]; then
    echo "Session:    $T_SESSION [MATCH]"
  else
    echo "Session:    $SESSION_ID [MISMATCH — task has $T_SESSION]"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo "Session:    $T_SESSION (no session_id provided to compare)"
fi

echo "State:      $T_STATE"
echo "Worked By:  ${T_WORKED:-<unset>}"

# --- Check 3: Heartbeat freshness ---
if [[ -n "$T_HEARTBEAT" && "$T_HEARTBEAT" != "null" ]]; then
  AGE_SECONDS=$(db_query "SELECT CAST((julianday('now') - julianday('$T_HEARTBEAT')) * 86400 AS INTEGER);")
  AGE_SECONDS="${AGE_SECONDS:-0}"

  if [[ $AGE_SECONDS -lt 480 ]]; then
    HB_STATUS="OK"
  elif [[ $AGE_SECONDS -lt 540 ]]; then
    HB_STATUS="STALE"
    ISSUES=$((ISSUES + 1))
  else
    HB_STATUS="ALARM"
    ISSUES=$((ISSUES + 1))
  fi
  echo "Heartbeat:  $T_HEARTBEAT (${AGE_SECONDS}s ago) [$HB_STATUS]"
else
  echo "Heartbeat:  <never set>"
  # Only flag if task is supposed to be active
  if [[ "$T_STATE" == "working" || "$T_STATE" == "needs_review" ]]; then
    ISSUES=$((ISSUES + 1))
  fi
fi

# --- Check 4: State validity ---
STATE_VALID=false
for s in $VALID_STATES; do
  if [[ "$T_STATE" == "$s" ]]; then
    STATE_VALID=true
    break
  fi
done
if [[ "$STATE_VALID" == "false" ]]; then
  echo "State:      WARNING — '$T_STATE' is not a recognized state"
  ISSUES=$((ISSUES + 1))
fi

echo "Retry:      ${T_RETRY:-0}/5"

# --- Check 5: Pending messages ---
if [[ -n "$T_HEARTBEAT" && "$T_HEARTBEAT" != "null" ]]; then
  MSG_COUNT=$(db_query "SELECT COUNT(*) FROM orchestration_messages WHERE task_id='$TASK_ID' AND from_session='task-00' AND timestamp > '$T_HEARTBEAT';")
else
  MSG_COUNT=$(db_query "SELECT COUNT(*) FROM orchestration_messages WHERE task_id='$TASK_ID' AND from_session='task-00';")
fi
echo "Messages:   ${MSG_COUNT:-0} pending"
if [[ "${MSG_COUNT:-0}" -gt 0 ]]; then
  ISSUES=$((ISSUES + 1))
fi

# --- Check 6: Fallback rows ---
if [[ -n "$SESSION_ID" ]]; then
  FALLBACK=$(db_query "SELECT task_id FROM orchestration_tasks WHERE task_id LIKE 'fallback-%' AND session_id='$SESSION_ID';")
  if [[ -n "$FALLBACK" ]]; then
    echo "Fallbacks:  WARNING — fallback row exists ($FALLBACK)"
    ISSUES=$((ISSUES + 1))
  else
    echo "Fallbacks:  none"
  fi
else
  echo "Fallbacks:  (skipped — no session_id)"
fi

# --- Result ---
if [[ $ISSUES -eq 0 ]]; then
  echo "=== RESULT: HEALTHY ==="
  exit 0
else
  echo "=== RESULT: ISSUES FOUND ($ISSUES) ==="
  exit 1
fi
