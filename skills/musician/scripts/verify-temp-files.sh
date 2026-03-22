#!/bin/bash
# verify-tmp-files.sh
#
# Validates that the musician's temp/ files exist and are properly structured.
# Run at bootstrap or resumption to verify file integrity.
#
# Usage: bash verify-tmp-files.sh <task_id>
#   task_id — The task to verify (e.g. task-03)
#
# Exit codes: 0 = OK, 1 = required files missing

set -euo pipefail

# --- Arguments ---
TASK_ID="${1:-}"

if [[ -z "$TASK_ID" ]]; then
  echo "Usage: bash verify-tmp-files.sh <task_id>"
  exit 2
fi

# Extract the NN portion (task-03 → 03)
TASK_NUM="${TASK_ID#task-}"

# --- Config ---
PROJECT_DIR="${PROJECT_DIR:-/home/kyle/claude/remindly}"
TEMP_DIR="$PROJECT_DIR/temp"

STATUS_FILE="$TEMP_DIR/${TASK_ID}-status"
DEVIATIONS_FILE="$TEMP_DIR/${TASK_ID}-deviations"
HANDOFF_FILE="$TEMP_DIR/${TASK_ID}-HANDOFF"

ISSUES=0

echo "=== temp/ File Verification: $TASK_ID ==="

# --- Check 1: Required files exist ---
if [[ -f "$STATUS_FILE" ]]; then
  LINE_COUNT=$(wc -l < "$STATUS_FILE")
  LAST_ENTRY=$(tail -n 1 "$STATUS_FILE")

  # Extract last context percentage
  LAST_CTX=$(grep -oP '\[ctx: \K[0-9]+' "$STATUS_FILE" | tail -n 1)

  echo "Status File:    ${TASK_ID}-status ($LINE_COUNT lines)"
  echo "  Last Entry:   $LAST_ENTRY"

  if [[ -n "${LAST_CTX:-}" ]]; then
    echo "  Last Context:  ${LAST_CTX}%"
  else
    echo "  Last Context:  (no [ctx: XX%] tag found)"
  fi

  # Check minimum content
  if [[ $LINE_COUNT -lt 1 ]]; then
    echo "  WARNING: status file is empty"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo "Status File:    MISSING — ${TASK_ID}-status"
  ISSUES=$((ISSUES + 1))
fi

# --- Check 2: Deviations file ---
if [[ -f "$DEVIATIONS_FILE" ]]; then
  DEV_COUNT=$(wc -l < "$DEVIATIONS_FILE")

  # Count by severity
  LOW=$(grep -ci 'low' "$DEVIATIONS_FILE" 2>/dev/null || true)
  LOW="${LOW:-0}"
  MEDIUM=$(grep -ci 'medium' "$DEVIATIONS_FILE" 2>/dev/null || true)
  MEDIUM="${MEDIUM:-0}"
  HIGH=$(grep -ci 'high' "$DEVIATIONS_FILE" 2>/dev/null || true)
  HIGH="${HIGH:-0}"

  echo "Deviations:     ${TASK_ID}-deviations ($DEV_COUNT entries)"
  echo "  Breakdown:    $HIGH High, $MEDIUM Medium, $LOW Low"
else
  echo "Deviations:     MISSING — ${TASK_ID}-deviations"
  ISSUES=$((ISSUES + 1))
fi

# --- Check 3: File naming sanity ---
# Look for any temp files that reference a different task number
MISMATCHED=$(find "$TEMP_DIR" -maxdepth 1 -name "task-*" ! -name "${TASK_ID}*" -printf '%f\n' 2>/dev/null || true)
if [[ -n "$MISMATCHED" ]]; then
  echo "Other Tasks:    files for other task IDs found in temp/"
  while IFS= read -r f; do
    echo "  - $f"
  done <<< "$MISMATCHED"
fi

# --- Check 4: Self-correction detection ---
if [[ -f "$STATUS_FILE" ]]; then
  SC_COUNT=$(grep -ci 'self-correction' "$STATUS_FILE" 2>/dev/null || echo 0)
  if [[ $SC_COUNT -gt 0 ]]; then
    SC_DETAILS=$(grep -in 'self-correction' "$STATUS_FILE" 2>/dev/null || true)
    echo "Self-Correction: $SC_COUNT event(s)"
    while IFS= read -r line; do
      echo "  - $line"
    done <<< "$SC_DETAILS"
  else
    echo "Self-Correction: none"
  fi
fi

# --- Check 5: HANDOFF file ---
if [[ -f "$HANDOFF_FILE" ]]; then
  echo "HANDOFF:        present ($HANDOFF_FILE)"

  # Try to extract session info and exit reason
  EXIT_REASON=$(grep -i 'exit.reason\|reason.*exit' "$HANDOFF_FILE" | head -1 || true)
  PENDING=$(grep -ci 'pending\|remaining' "$HANDOFF_FILE" 2>/dev/null || echo 0)

  if [[ -n "$EXIT_REASON" ]]; then
    echo "  Exit Reason:  $EXIT_REASON"
  fi
  echo "  Pending refs: $PENDING lines mentioning pending/remaining"
else
  echo "HANDOFF:        not present (expected if session still active)"
fi

# --- Result ---
if [[ $ISSUES -eq 0 ]]; then
  echo "=== RESULT: OK ==="
  exit 0
else
  echo "=== RESULT: MISSING FILES ($ISSUES required file(s) absent) ==="
  exit 1
fi
