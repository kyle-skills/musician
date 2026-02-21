<skill name="musician-database-queries" version="2.0">

<metadata>
type: reference
parent-skill: musician
tier: 3
</metadata>

<sections>
- bootstrap-queries
- execution-queries
- terminal-write-atomicity
- message-format-standards
- parallel-awareness-queries
</sections>

<section id="bootstrap-queries">
<context>
# Reference: Musician Database Queries

This reference describes the database operations the musician performs, organized by lifecycle phase.
</context>

<core>
## Bootstrap Queries

**1. Atomic Task Claim**

Update the task row to claim it: set state to `working`, record the session ID, start time, and last heartbeat. The claim includes a guard clause that only allows the update if the current state is in the set of claimable states. This prevents double-claiming.

Verify that exactly 1 row was affected. If 0 rows, the guard blocked the claim and the session cannot proceed with this task.

**2. Guard Block Fallback**

If the guard blocks the claim, the session must still exit cleanly. Create a fallback row with `task_id = 'fallback-{session_id}'`, state `exited`, using the current session ID. This row tells the hook that the session should exit cleanly. Send a message to the conductor explaining that the claim was blocked.

**3. Read Task Instruction**

Query for the message with `task_id = '{task_id}'` AND `message_type = 'instruction'` from the conductor (from_session = 'task-00'). This message contains the task instruction file path. Read and parse the full task instruction file.
</core>
</section>

<section id="execution-queries">
<core>
## Execution Queries

**4. Heartbeat Update (Step Boundary)**

At each step boundary in task execution, update the task row's `last_heartbeat` to the current time. This signal refreshes the musician's "liveness" — the conductor knows the session is still running.

**5. Review Request (Checkpoint)**

When reaching a checkpoint and verification tests pass, update the task state to `needs_review` and send a message to the conductor. The message contains all 10 standard review fields:

1. **Context Usage** (%) — Current context window consumption
2. **Self-Correction** (YES/NO) — Whether self-correction occurred during this checkpoint
3. **Deviations** (count + severity) — Count and maximum severity of logged deviations
4. **Agents Remaining** (count (description)) — Estimate of remaining agents needed and their typical cost
5. **Proposal** (path or N/A) — Path to any proposals created, or N/A if none
6. **Summary** — Summary of work accomplished at this checkpoint
7. **Files Modified** (count) — Number of files created or modified
8. **Tests** (status) — Test results (all passing, count of new tests, etc.)
9. **Smoothness** (0-9) — Smoothness score for execution quality
10. **Reason** (why review needed) — Why this review checkpoint was triggered

Additionally include Key Outputs (significant files created, modified, or proposed for RAG addition).

**6. Context Warning & Handoff**

Context monitoring follows the three-threshold model:
- **>50%:** Estimate context cost before every file read. No speculative reads. Log estimates to status file.
- **65%:** Prepare handoff: write HANDOFF doc, finish current step only, no new work steps. Send a context warning message including current context %, self-correction status, remaining agent estimates, how many agents fit in remaining budget, and deviation count.
- **75%:** Mandatory exit. Stop all work immediately. Complete HANDOFF, set state to `exited` (clean handoff, not `error`).

At 65%, the musician prepares for exit but may still complete the current step. At 75%, the musician stops immediately and transitions to `exited` state via the clean exit protocol (query 10).

**7. Error Report (Failure State)**

When an unrecoverable error occurs, update state to `error`, increment retry count, and set `last_error` to the error description. Send a message including:
- Retry attempt number (out of 5 conductor-level retries — distinct from the 2-retry subagent limit)
- Current context usage
- Whether self-correction occurred
- Error description
- Path to detailed error report
- Key outputs (files created or modified during the failed attempt)
- Note that awaiting conductor fix proposal

**8. Completion Report (Final Checkpoint)**

When all task steps are complete, update state to `needs_review` (for final approval) and send a completion message including:
- Smoothness score (0-9 scale)
- Final context usage
- Whether self-correction occurred
- Count of deviations
- Path to completion report
- Summary of all deliverables created
- Count of files modified
- Final test status
- Key outputs (all significant files created, modified, or proposed for RAG addition)

**9. Final Complete (TERMINAL WRITE)**

After conductor approves completion, update state to `complete`, set `completed_at` timestamp, and record the completion report path. This is the absolute last database write for this task.

**10. Clean Exit (TERMINAL WRITE)**

If exiting early due to context exhaustion, update state to `exited`, set `last_heartbeat`, and send a handoff message including:
- Exit reason
- Path to HANDOFF document
- Final context usage
- Last completed step
- List of remaining steps
</core>
</section>

<section id="terminal-write-atomicity">
<mandatory>
## Terminal Write Atomicity

Terminal state writes (queries 9 and 10) must execute in order: (1) write message to `orchestration_messages` first, (2) then update task state in `orchestration_tasks`. This ensures the message serves as a recovery record if the state update fails. Execute each query separately — comms-link may not support multi-statement transactions.
</mandatory>
</section>

<section id="message-format-standards">
<core>
## Message Format Standards

All musician messages include the message type (`review_request`, `error`, `completion`, etc.), timestamp, context usage percentage, and specific content per type. Messages are inserted into `orchestration_messages` table with the task ID, musician session ID, and message type.
</core>
</section>

<section id="parallel-awareness-queries">
<core>
## Parallel Awareness Queries

**11. Check Sibling States**

Optionally query to see what state other musician tasks are in. This is useful for awareness during parallel execution but not required — the musician operates independently unless the conductor sends emergency messages.

**12. Check Conductor Health**

Query the conductor task row (task_id = 'task-00') to check its state and heartbeat staleness. If the conductor's heartbeat is stale (older than 9 minutes), the conductor may have crashed. Use this information when deciding whether to keep waiting or escalate.
</core>
</section>

</skill>
