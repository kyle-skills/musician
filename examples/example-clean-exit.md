<skill name="musician-example-clean-exit" version="2.0">

<metadata>
type: example
parent-skill: musician
tier: 3
</metadata>

<sections>
- scenario
- final-work-complete
- exit-preparation
- handoff-and-report
- terminal-state
- what-happens-next
- summary
</sections>

<section id="scenario">
<context>
# Example: Clean Exit & Handoff

This example walks through the musician preparing a clean exit when task work is complete and context is approaching its limit.

## Scenario

The musician has completed all conductor-approved work for task-03. Checkpoint 3 has been approved. The conductor confirmed that the scope reduction was accepted (Step 5 agent 3 was skipped). Context is at 72%, well-managed. Time to exit cleanly and prepare for the next session.
</context>
</section>

<section id="final-work-complete">
<core>
## Step 1: Final Work Complete

The musician confirms that all approved work is done:
- Step 1: Complete ✅
- Step 2: Complete ✅
- Step 3: Complete ✅
- Step 4: Complete ✅
- Step 5: Partial (agents 1-2 done, agent 3 skipped per conductor) ✅
- Checkpoint 3: Approved ✅

Status: `checkpoint 3 approved [ctx: 69%]`.
</core>
</section>

<section id="exit-preparation">
<core>
## Step 2: Prepare for Exit

Before setting terminal state, the musician must:
1. Ensure all background agents are stopped
2. Create a handoff document for the next session
3. Write a completion report
4. Update temp/ files
5. Send final message to conductor
6. ONLY THEN set task state to `exited`

## Step 3: Exit All Active Subagents

The musician verifies no subagents are still running:
- Background watcher: Terminate using TaskStop
- No delegated agents are pending (all have returned or been deferred)
- No active processes

All clean.
</core>
</section>

<section id="handoff-and-report">
<core>
## Step 4: Create HANDOFF Document

The musician creates a comprehensive handoff document and writes it to `temp/task-03-HANDOFF`:

```markdown
# HANDOFF: task-03

## Session Info
- Session ID: abc123-def456-789
- worked_by: musician-task-03
- Exit reason: context exhaustion (conductor-approved scope reduction)
- Context at exit: 72%
- Timestamp: 2026-02-07 16:45:00

## Completed Steps
- Step 1: Testing pattern extraction ✅
- Step 2: Quality assurance content + cross-references ✅
- Step 3: Implementation guidelines extraction ✅
- Step 4: Reference document consolidation ✅
- Step 5: Documentation finalization ✅ (partial — agents 1-2 done, agent 3 skipped)

## Pending Steps
- Step 5 agent 3: Generate table of contents and index for knowledge-base/
- Final verification and completion

## Deviations
- Checkpoint 2 review_failed (Medium) — 3 issues resolved
- Step 5 agent 3 skipped (Low) — conductor-directed scope reduction

## Self-Correction
- YES (step 3, agent 2 — parser rewrite, ~6x context impact on that segment)

## Pending Proposals
- docs/implementation/proposals/2026-02-07-parser-rewrite-antipattern.md (ANTI_PATTERN)

## Next Session Instructions
1. Claim task with worked_by = musician-task-03-S2
2. Read this HANDOFF + conductor's handoff message
3. Re-run verification tests from checkpoint 3
4. Execute step 5 agent 3 (table of contents generation)
5. Run final checkpoint, submit completion review
```

Status: `HANDOFF created [ctx: 70%]`.

## Step 5: Write Completion Report

The musician writes a detailed summary report to `docs/implementation/reports/task-03-handoff-s1.md` containing:
- Deliverables list (files created/modified, line counts)
- Test status (all tests passing, count of tests)
- Deviations encountered (2: 1 Medium, 1 Low)
- Self-correction details (step 3 agent 2)
- Remaining work (step 5 agent 3)
- Recommendations for next session

Status: `completion report written [ctx: 71%]`.

## Step 6: Update temp/status

The musician appends final status entries to `temp/task-03-status`:

```
HANDOFF written: temp/task-03-HANDOFF [ctx: 71%]
report written: docs/implementation/reports/task-03-handoff-s1.md [ctx: 72%]
clean exit preparing [ctx: 72%]
```

This creates a continuous log of the session's work from bootstrap through exit.

## Step 7: Write Final Message to Conductor

The musician sends a final message to the conductor via the database:

```
EXITED: Context exhaustion, clean handoff prepared.
HANDOFF: temp/task-03-HANDOFF
Context Usage: 72%
Self-Correction: YES (step 3, ~6x impact)
Last Completed Step: 5 (partial — agents 1-2)
Remaining Steps: step 5 agent 3, final verification
Proposals Pending: 1 (anti-pattern)
Key Outputs:
  - docs/implementation/reports/task-03-handoff-s1.md (created)
  - docs/implementation/proposals/2026-02-07-parser-rewrite-antipattern.md (created)
```

This message:
- Confirms the exit
- Points to the HANDOFF location
- Reports final context usage
- Lists remaining work
- Mentions any anti-patterns or findings for the conductor's review
</core>
</section>

<section id="terminal-state">
<core>
## Step 8: Set Terminal State (LAST STEP)

The musician performs one final database operation to set the task state to `exited`:

```
UPDATE orchestration_tasks
SET state = 'exited', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';
```
</core>

<mandatory>
**This is the absolute last database write.** After this, the musician must not access the database. The Stop hook monitors this `exited` state and allows the session to terminate cleanly.
</mandatory>
</section>

<section id="what-happens-next">
<context>
## What Happens Next

1. **Stop Hook Detects `exited`:** The Stop hook sees the task state is `exited` and allows the session to exit normally (no forced shutdown).

2. **Conductor Reviews Handoff:** The conductor reads the HANDOFF document and final message, then prepares for the next session by:
   - Setting task state to `fix_proposed` with next session instructions
   - Creating a handoff message for session 2
   - Optionally reviewing proposals or anti-patterns

3. **Session 2 Takes Over:** When launched, the new musician session will:
   - Read the HANDOFF
   - Claim the task
   - Execute remaining work (step 5 agent 3)
   - Complete final checkpoint
   - Declare task done
</context>
</section>

<section id="summary">
<context>
## Summary

Clean exit workflow:
1. Verify all work is complete and approved
2. Stop all background agents
3. Create detailed HANDOFF document
4. Write completion report
5. Update status log
6. Send final message to conductor
7. Set task state to `exited` (last operation)
8. Let Stop hook detect exit and allow session termination

Context progression:
- Before exit prep: 69%
- After HANDOFF: 70%
- After report: 71%
- After final message: 71%
- After state update: 72%

Key principles:
- HANDOFF is the bridge to the next session
- No database operations after `exited` state
- All information for resumption must be in HANDOFF
- Reports provide transparency and context for the conductor
- Clean exit enables smooth continuation in future sessions

This demonstrates the musician's ability to conclude work gracefully, prepare for resumption, and communicate clearly with the conductor. The clean exit pattern ensures that long-running tasks can span multiple sessions without losing context or state.
</context>
</section>

</skill>
