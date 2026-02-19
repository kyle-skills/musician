#!/bin/bash
# check-context-headroom.sh
#
# Parses the musician's status file for context usage entries and estimates
# remaining budget. Useful for the conductor to passively check an
# musician's context trajectory without interrupting it.
#
# Usage: bash check-context-headroom.sh <task_id>
#   task_id — The task to analyze (e.g. task-03)
#
# Exit codes: 0 = healthy, 1 = caution (self-correction or >60%), 2 = critical (>75%)

set -euo pipefail

# --- Arguments ---
TASK_ID="${1:-}"

if [[ -z "$TASK_ID" ]]; then
  echo "Usage: bash check-context-headroom.sh <task_id>"
  exit 2
fi

# --- Config ---
PROJECT_DIR="${PROJECT_DIR:-/home/kyle/claude/remindly}"
STATUS_FILE="$PROJECT_DIR/temp/${TASK_ID}-status"
CEILING=80  # Hard ceiling percentage

EXIT_CODE=0

# --- Check: Status file exists ---
if [[ ! -f "$STATUS_FILE" ]]; then
  echo "=== Context Headroom: $TASK_ID ==="
  echo "ERROR: Status file not found at $STATUS_FILE"
  echo "=== RESULT: FILE MISSING ==="
  exit 1
fi

TOTAL_LINES=$(wc -l < "$STATUS_FILE")

# --- Parse context entries ---
# Extract all [ctx: XX%] values in order
CTX_VALUES=()
while IFS= read -r val; do
  CTX_VALUES+=("$val")
done < <(grep -oP '\[ctx: \K[0-9]+' "$STATUS_FILE")

CTX_COUNT=${#CTX_VALUES[@]}

echo "=== Context Headroom: $TASK_ID ==="

if [[ $CTX_COUNT -eq 0 ]]; then
  echo "Current:     (no context entries found in status file)"
  echo "=== RESULT: NO DATA ==="
  exit 1
fi

FIRST_CTX=${CTX_VALUES[0]}
LAST_CTX=${CTX_VALUES[$((CTX_COUNT - 1))]}
CONSUMED=$((LAST_CTX - FIRST_CTX))
HEADROOM=$((CEILING - LAST_CTX))

echo "Current:     ${LAST_CTX}% (entry $CTX_COUNT of status file)"

# --- Calculate trajectory ---
if [[ $CTX_COUNT -gt 1 ]]; then
  # Integer math: multiply by 10 for one decimal place precision
  AVG_X10=$(( (CONSUMED * 10) / (CTX_COUNT - 1) ))
  AVG_WHOLE=$((AVG_X10 / 10))
  AVG_FRAC=$((AVG_X10 % 10))
  echo "Trajectory:  +${AVG_WHOLE}.${AVG_FRAC}% per entry avg"

  if [[ $AVG_X10 -gt 0 ]]; then
    EST_ENTRIES=$(( (HEADROOM * 10) / AVG_X10 ))
  else
    EST_ENTRIES=999
  fi
else
  AVG_X10=0
  EST_ENTRIES=999
  echo "Trajectory:  (only 1 entry — insufficient data)"
fi

echo "Headroom:    ${HEADROOM}% remaining to ${CEILING}% ceiling"

# --- Agent tracking ---
AGENTS_LAUNCHED=$(grep -c 'agent.*launched\|launched.*agent' "$STATUS_FILE" 2>/dev/null || echo 0)
AGENTS_RETURNED=$(grep -c 'agent.*returned\|returned.*agent' "$STATUS_FILE" 2>/dev/null || echo 0)
AGENTS_INFLIGHT=$((AGENTS_LAUNCHED - AGENTS_RETURNED))
if [[ $AGENTS_INFLIGHT -lt 0 ]]; then
  AGENTS_INFLIGHT=0
fi

if [[ $AGENTS_RETURNED -gt 0 && $CONSUMED -gt 0 ]]; then
  AVG_PER_AGENT_X10=$(( (CONSUMED * 10) / AGENTS_RETURNED ))
  APA_WHOLE=$((AVG_PER_AGENT_X10 / 10))
  APA_FRAC=$((AVG_PER_AGENT_X10 % 10))
  echo "Agents:      $AGENTS_RETURNED completed, $AGENTS_INFLIGHT in-flight (~${APA_WHOLE}.${APA_FRAC}% per agent avg)"

  if [[ $AVG_PER_AGENT_X10 -gt 0 ]]; then
    EST_AGENTS=$(( (HEADROOM * 10) / AVG_PER_AGENT_X10 ))
    echo "Est. Agents Left: ~$EST_AGENTS agents fit in remaining budget"
  fi
elif [[ $AGENTS_LAUNCHED -gt 0 ]]; then
  echo "Agents:      0 completed, $AGENTS_INFLIGHT in-flight (no avg yet)"
else
  echo "Agents:      no agent entries found"
fi

# --- Step progress ---
STEPS_STARTED=$(grep -c 'step.*started\|started.*step' "$STATUS_FILE" 2>/dev/null || echo 0)
STEPS_COMPLETED=$(grep -c 'step.*completed\|completed.*step' "$STATUS_FILE" 2>/dev/null || echo 0)

# Try to extract total steps from a "of N" pattern
TOTAL_STEPS=$(grep -oP 'of \K[0-9]+' "$STATUS_FILE" 2>/dev/null | tail -1 || true)

if [[ $STEPS_STARTED -gt 0 ]]; then
  CURRENT_STEP=$STEPS_STARTED
  if [[ -n "$TOTAL_STEPS" ]]; then
    echo "Steps:       $STEPS_COMPLETED of $TOTAL_STEPS completed, step $CURRENT_STEP in progress"
  else
    echo "Steps:       $STEPS_COMPLETED completed, step $CURRENT_STEP in progress"
  fi
else
  echo "Steps:       no step entries found"
fi

# --- Self-correction impact ---
SC_COUNT=$(grep -ci 'self-correction' "$STATUS_FILE" 2>/dev/null || echo 0)
if [[ $SC_COUNT -gt 0 ]]; then
  echo "Self-Correction: YES — estimates unreliable (6x risk)"
  if [[ $EXIT_CODE -lt 1 ]]; then
    EXIT_CODE=1
  fi
else
  echo "Self-Correction: NO"
fi

# --- Determine result ---
if [[ $LAST_CTX -ge 75 ]]; then
  RESULT="CRITICAL (context at ${LAST_CTX}%)"
  EXIT_CODE=2
elif [[ $LAST_CTX -ge 60 ]]; then
  RESULT="CAUTION (context at ${LAST_CTX}%)"
  if [[ $EXIT_CODE -lt 1 ]]; then
    EXIT_CODE=1
  fi
elif [[ $SC_COUNT -gt 0 ]]; then
  RESULT="CAUTION (self-correction detected)"
else
  RESULT="HEALTHY"
fi

echo "=== RESULT: $RESULT ==="
exit $EXIT_CODE
