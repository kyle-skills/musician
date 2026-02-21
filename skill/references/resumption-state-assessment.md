<skill name="musician-resumption-state-assessment" version="2.0">

<metadata>
type: reference
parent-skill: musician
tier: 3
</metadata>

<sections>
- resumption-decision-tree
- handoff-document-structure
- state-reconciliation
- verbose-resumption-status
- post-resumption-verification
</sections>

<section id="resumption-decision-tree">
<core>
# Reference: Resumption State Assessment

## Resumption Decision Tree

When a new session starts and previous sessions have exited, follow this decision tree:

1. **Read temp/ HANDOFF document**
2. **Assess HANDOFF quality:**
   - HANDOFF exists and recent: Clean exit, previous session prepared handoff
   - HANDOFF missing or stale: Forced exit, previous session crashed or exited unexpectedly
3. **Read conductor message** (latest message from conductor for this task)
4. **Read temp/ deviations file** (list of any deviations from plan)
5. **Assess health:**
   - ≤2 deviations AND no mismatches: Continue from last checkpoint
   - >2 deviations OR multiple mismatches OR temp/comms mismatch: Report to conductor for guidance. When >2 deviations exist, the conductor may issue a **correction task** — a scoped set of fixes to apply before resuming normal execution. The musician applies correction task steps first, re-runs verification, then resumes from the last checkpoint. See the deviation escalation thresholds in SKILL.md for severity rules.
</core>
</section>

<section id="handoff-document-structure">
<core>
## HANDOFF Document Structure

When exiting, create a HANDOFF document with:

```
# HANDOFF: task-{NN}

## Session Info
- Session ID: {session_id}
- worked_by: musician-task-{NN}[-S2, -S3, etc. if resumed]
- Exit reason: context exhaustion / conductor requested / etc.
- Context at exit: {XX%}
- Timestamp: {datetime}

## Completed Steps
- Step 1: {description} ✅
- Step 2: {description} ✅
- Step 3: {partial description, agents 1-2 done, agent 3 not started}

## Pending Steps
- Step 3 agent 3: {what remains}
- Step 4: {full description}
- Step 5: {full description}

## Deviations
- {list from temp/ deviations file, or "none"}

## Self-Correction
- YES/NO with details if YES

## Pending Proposals
- {list any proposals created but not yet reviewed}

## Next Session Instructions
1. Claim task with worked_by = musician-task-{NN}-S2
2. Read this HANDOFF + conductor's handoff message
3. Re-run verification tests from step 3 checkpoint
4. Continue from step 3 agent 3
```
</core>
</section>

<section id="state-reconciliation">
<core>
## State Reconciliation

When resuming, the musician may find mismatches between:
- `temp/task-XX-status` (local, most recent state)
- `orchestration_tasks` row (persistent state)
- `temp/task-XX-deviations` (local deviations record)

**Categorize mismatches:**

**Benign:** One field differs with clear explanation
- Timestamps off by <1 minute
- Step count off by 1
- Last checkpoint differs by 1
- **Action:** Auto-correct using temp/ files (local, more recent)

**Suspicious:** Multiple fields differ, needs investigation
- Different files listed as modified
- Different step reported as current
- Deviations count mismatch
- **Action:** Re-run verification tests to clarify correct state

**Contradictory:** Fundamental state conflict
- DB says `complete` but temp shows work in progress
- DB says `error` but temp shows checkpoint passed
- Conductor message timestamp > session start
- **Action:** Escalate to conductor immediately
</core>
</section>

<section id="verbose-resumption-status">
<core>
## Verbose Resumption Status

Write resumption status to both `temp/task-XX-status` and `orchestration_messages`:

```
RESUMPTION: musician-task-{NN}-S2 taking over
  Previous session: {session_id from HANDOFF}
  HANDOFF: present/missing/stale
  Context Usage: {XX%} (fresh session)
  Deviations found: {N} (breakdown by severity)
  Status/comms mismatches: {N or "none"}
  Pending conductor messages: {N}
  Self-correction in previous session: YES/NO
  Assessment: clean handoff / needs verification / needs guidance
  Resuming from: step {N}, {description}
```
</core>
</section>

<section id="post-resumption-verification">
<mandatory>
## Post-Resumption Verification

ALWAYS re-run verification tests after resuming, even if:
- Conductor approved previous session's work
- HANDOFF indicates all tests passed
- No mismatches were found

This ensures fresh confidence in the current session's state and catches any environment-dependent issues.
</mandatory>
</section>

</skill>
