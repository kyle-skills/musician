<skill name="musician-example-resumption" version="2.0">

<metadata>
type: example
parent-skill: musician
tier: 3
</metadata>

<sections>
- scenario
- sessionstart-hook
- parse-task-identity
- atomic-claim
- read-all-temp-files
- read-handoff-document
- read-conductor-handoff-message
- assess-health
- re-run-verification-tests
- write-verbose-resumption-status
- launch-background-watcher-and-resume
- complete-remaining-work
- log-completion
- summary
</sections>

<section id="scenario">
<context>
# Example: Mid-Session Resumption

This example walks through a second musician session taking over after the first session exited cleanly at context exhaustion.

## Scenario

Session 1 ran task-03 to 72% context, completed the approved scope, and exited cleanly with a HANDOFF document. The conductor set `fix_proposed` state with instructions for the next session. The user launches Session 2.
</context>
</section>

<section id="sessionstart-hook">
<core>
## Step 1: SessionStart Hook

The SessionStart hook automatically extracts the session ID and injects it into the system prompt: `CLAUDE_SESSION_ID=xyz789-abc012-345`. This becomes available to the musician immediately.
</core>
</section>

<section id="parse-task-identity">
<core>
## Step 2: Parse Task Identity

The musician recognizes the standardized launch prompt and extracts: Task ID is `task-03` from the context block. Session role: take over where Session 1 left off.
</core>
</section>

<section id="atomic-claim">
<core>
## Step 3: Atomic Claim

The musician attempts to claim the task. It queries the database for the task record and executes an UPDATE with guard clause:

The task is in `fix_proposed` state (set by conductor after Session 1 exited). The guard clause allows claiming from states: `watching`, `fix_proposed`, or `exit_requested`.

Guard passes. Result: `rows_affected = 1`. Claim succeeded. The musician records: `session_id=xyz789-abc012-345`, `started_at=now`, `worked_by=musician-task-03-S2`.

Note: The `-S2` suffix signals this is a resumed session, not a fresh start.
</core>
</section>

<section id="read-all-temp-files">
<core>
## Step 4: Read All temp/ Files

The musician reads the temp/ status files left by Session 1:

```
temp/task-03-status:
  [Many lines from bootstrap through early work]
  ...
  step 5 agent 2 returned [ctx: 67%]
  checkpoint 3 reached [ctx: 67%]
  checkpoint 3 approved [ctx: 69%]
  clean exit preparing [ctx: 70%]

temp/task-03-HANDOFF:
  (present — indicates clean exit)

temp/task-03-deviations:
  checkpoint 2: review_failed (Smoothness 6/9) [Medium]
  step 5 agent 3 skipped per conductor [Low — instructed scope reduction]
```

This tells the musician what has already been done and what's pending.
</core>
</section>

<section id="read-handoff-document">
<core>
## Step 5: Read HANDOFF Document

The musician reads the HANDOFF document created by Session 1:

```
HANDOFF: task-03

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

## Next Session Instructions
1. Claim task with worked_by = musician-task-03-S2
2. Read this HANDOFF + conductor's handoff message
3. Re-run verification tests from checkpoint 3
4. Execute step 5 agent 3 (table of contents generation)
5. Run final checkpoint, submit completion review
```

This gives the musician a clear roadmap for what needs to be done.
</core>
</section>

<section id="read-conductor-handoff-message">
<core>
## Step 6: Read Conductor Handoff Message

The musician queries the database for the most recent message from the conductor:

```
Session 1 exited cleanly. Resumption instructions:
- Step 5 agent 3 (table of contents) is the only remaining work
- Re-run checkpoint 3 verification to confirm S1's work is intact
- Then complete normally
```

Clear, actionable instructions.
</core>
</section>

<section id="assess-health">
<core>
## Step 7: Assess Health

The musician verifies that resumption is safe:

- **HANDOFF exists and is recent** — ✅ Yes, dated 2026-02-07 16:45:00 (today)
- **Deviations count is manageable** — ✅ 2 total (1 Medium, 1 Low) ≤ 2 allowed
- **No temp/comms mismatches** — ✅ Both status file and database are consistent
- **Conductor message is clear** — ✅ Specific instructions provided
- **No evidence of crash or unclean exit** — ✅ HANDOFF is present and structured

Assessment: **Clean handoff. Safe to continue.**
</core>
</section>

<section id="re-run-verification-tests">
<core>
## Step 8: Re-Run Verification Tests

Even though Session 1 completed and was approved, the resuming session always re-runs verification:

```bash
flutter test
```

Results:
- All 44 tests pass
- No new failures
- No regressions detected

This confirms Session 1's work is intact and the codebase is in a stable state for resumption.

Status: `verification tests: all passing [ctx: 18%]` (fresh session, low context).
</core>
</section>

<section id="write-verbose-resumption-status">
<core>
## Step 9: Write Verbose Resumption Status

The musician logs a detailed resumption message for both the status file and sends it to the conductor:

```
RESUMPTION: musician-task-03-S2 taking over
  Previous session: abc123-def456-789
  HANDOFF: present (clean exit at 72% context)
  Context Usage (fresh session): 18%
  Deviations found: 2 (1 Medium, 1 Low — both from S1, no new deviations)
  Status/comms mismatches: none
  Pending conductor messages: 1 (handoff instructions)
  Self-correction in previous session: YES (step 3, agent 2)
  Assessment: clean handoff
  Verification tests: all passing (44 tests)
  Resuming from: step 5 agent 3 (table of contents generation)
  Estimated remaining work: 1 agent + final checkpoint (~8% context)
```

This message is both logged locally and sent to the conductor as a "resumption_status" message.
</core>
</section>

<section id="launch-background-watcher-and-resume">
<core>
## Step 10: Launch Background Watcher & Resume

The musician:
1. Launches a new background watcher (independent of Session 1's watcher, which stopped)
2. Reads the task instructions for step 5 agent 3
3. Launches the agent to generate table of contents and index

Status update: `step 5 agent 3 launched [ctx: 19%]`.
</core>
</section>

<section id="complete-remaining-work">
<core>
## Step 11: Complete Remaining Work

The musician continues with the HANDOFF instructions:
- Agent 3 returns: Table of contents and index generated (~4% cost)
- Final checkpoint verification: All tests pass, final review submitted
- Conductor approves completion

Final context: ~26% (well within limits for a fresh session).
</core>
</section>

<section id="log-completion">
<core>
## Step 12: Log Completion

The musician logs the successful resumption and completion, noting that the task is now fully complete.
</core>
</section>

<section id="summary">
<context>
## Summary

Mid-session resumption workflow:
- Detected clean HANDOFF and conductor message
- Re-verified previous session's work (all tests passing)
- Resumed from exact checkpoint (step 5 agent 3)
- Completed remaining work efficiently (~8% context cost)
- Final context: ~26% (fresh session, well-managed)
- Task fully complete

Key takeaways:
- HANDOFF documents are the bridge between sessions
- Re-verification is always done, even if S1 passed tests
- Clear instructions from conductor enable smooth handoff
- Context resets on new session, so resumption is lightweight
- Status logging keeps both sides synchronized

This demonstrates the musician's ability to resume mid-project cleanly and efficiently, picking up where the previous session left off with confidence.
</context>
</section>

</skill>
