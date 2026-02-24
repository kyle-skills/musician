# Musician Skill — Integration Review Findings

*Source: Conductor skill review session, 2026-02-20*
*Reviewers: Musician integration reviewer, Copyist integration reviewer*

## Critical (1)

### M-C1: Missing `exit_requested` handling
- **File:** `SKILL.md` (review-communication section, lines 298-304)
- **Issue:** No documented behavior for `exit_requested` state. The Conductor can set this state (e.g., during Repetiteur consultation, user-requested stop, emergency broadcasts) but the Musician has no protocol for handling it.
- **Impact:** Musician's pause watcher WOULD detect the state change and exit, but the Musician has no documented next step. Could lead to unpredictable behavior — re-claiming, ignoring, or hanging.
- **Fix:** Add explicit `exit_requested` handling to review-communication section: "If state changes to `exit_requested`: prepare HANDOFF, set state to `exited`, exit cleanly." Also reference in watcher protocol.

## Major (3)

### M-M1: Context warning `last_error` value not specified
- **Files:** `SKILL.md` (context-monitoring section, lines 245-258), `references/database-queries.md` (lines 68-75)
- **Issue:** Musician never specifies the exact string `context_exhaustion_warning` that the Conductor routes on (`error-recovery.md` line 83). The Conductor's routing depends on this exact string in `last_error`. If Musician writes a different value (e.g., `context warning`, `Context exhaustion at 65%`), the Conductor will route to the standard error workflow instead of the lighter context-situation-checklist.
- **Fix:** Add explicit guidance: "When hitting 65% context, set `last_error = 'context_exhaustion_warning'` (exact string)."

### M-M2: `review_failed` -> `working` intermediate state skipped
- **File:** `references/state-machine.md` (line 59)
- **Issue:** Shows direct `review_failed -> needs_review` without going through `working`. The Conductor expects `review_failed -> working -> needs_review`. The staleness detection query checks for stale heartbeats in `review_failed` state — if the Musician stays in `review_failed` for >9 minutes while applying feedback, the Conductor flags it as stale.
- **Fix:** Update state machine to include `review_failed -> working -> needs_review` as the canonical path. Same issue exists for `fix_proposed`.

### M-M3: Review request examples omit required fields
- **File:** `examples/example-checkpoint-flow.md` (lines 62-71)
- **Issue:** Example review request omits "Reason" and "Smoothness" as separate labeled fields. The Conductor mandates all 10 fields and flags missing ones as deviations.
- **Fix:** Update example to include all 10 required fields.

## Minor (3)

### M-m1: Self-Correction value format inconsistency
- **Issue:** Musician spec says `YES/NO`, Conductor example uses `false` (lowercase boolean). String matching in Conductor checks for `Self-Correction: YES`.
- **Fix:** Standardize on `YES/NO` across all specs and examples.

### M-m2: Bootstrap describes instruction path "in launch prompt"
- **File:** `SKILL.md` (lines 93-98)
- **Issue:** Bootstrap step 3 says "Read the task instruction file path provided in the launch prompt" but the path is actually in the database query result, not directly in the launch prompt text.
- **Fix:** Change to "Read the task instruction file path from the instruction message retrieved via the SQL query in the launch prompt."

### M-m3: Missing `success-criteria` in section vocabulary table
- **File:** `SKILL.md` (lines 163-179)
- **Issue:** The Copyist's parallel template includes a `success-criteria` section, but the Musician's section vocabulary table has no mapping row for it.
- **Fix:** Add: `| success-criteria | Final checklist, verify all criteria met before completion |`
