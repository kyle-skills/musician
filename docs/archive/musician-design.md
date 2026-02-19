# Musician Skill Design Document

## Frontmatter & Skill Metadata

```yaml
---
name: Musician
description: This skill should be used when the user asks to "execute task instruction", "run task in external session", "musician session for task", "implement task instructions", or launches an external Claude session to autonomously execute a phased task with subagent coordination, testing integration, review cycles, and context-aware checkpointing.
---
```

## Purpose

The Musician is a coding-focused conductor designed to run in external Claude sessions (Tier 1) coordinated by the main Conductor skill. It reads self-contained task instructions, launches Tier 2 subagents (Opus model) for focused implementation work, integrates their results at the module/feature level, verifies code and tests at checkpoints, manages review cycles with the conductor, and handles context-aware pausing/resumption.

Unlike the main Conductor (Tier 0, which coordinates multiple external sessions), the Musician does **direct integration work**: refactoring, assembly, holistic testing, connecting subagent outputs. It delegates smaller, isolated pieces (individual functions, unit tests, documentation) to subagents.

The Musician is cautious about context usage, self-aware about remaining headroom, follows task instructions strictly, and escalates to the conductor when deviating from instructions or making significant decisions outside the task scope.

## Design Rationale

Key design decisions and the reasoning behind them:

- **Why a separate musician tier:** Subagents lack session persistence and cross-step context. The musician provides integration coherence across a multi-step task — it remembers what Agent 1 produced when launching Agent 2, and can verify their outputs integrate correctly. Without this tier, the conductor would need to manage fine-grained implementation details across multiple sessions.

- **Why atomic claim with guard clause:** Prevents double-claiming in parallel launches. Only the first session to execute the UPDATE succeeds (rows_affected=1); concurrent sessions get rows_affected=0 and fall back cleanly. This eliminates race conditions without external locking.

- **Why watcher agents instead of musician polling:** Separates the monitoring concern from implementation work. The musician's context stays focused on task execution rather than interleaving poll cycles. The watcher runs in its own context (cheap Haiku model) and exits on events, signaling the musician without polluting its working memory.

- **Why message ID deduplication over timestamp:** Timestamps can be identical for concurrent messages (same-second writes). Message IDs are guaranteed unique and monotonically increasing, making `id > last_processed_id` reliable for deduplication.

- **Why 8-min heartbeat / 9-min staleness:** The 1-minute buffer prevents false stale-session alarms while catching genuine crashes quickly. If heartbeat refresh is at 8 minutes and conductor staleness threshold is 9 minutes, a healthy session always refreshes before being flagged.

- **Why terminal state must be last write:** The Stop hook queries the DB for task state. If the state update hasn't happened yet, the hook blocks exit — keeping the session alive for cleanup. Writing `exited` or `complete` as the absolute last operation ensures all cleanup (HANDOFF, messages, reports) completes before the session can terminate.

- **Why temp/ files for passive monitoring:** The conductor can peek at musician progress via subagent file reads without sending a message that would interrupt execution flow. Status files provide a read-only window into musician state.

- **Why proposals instead of direct RAG modification:** The musician doesn't have enough context to judge whether a pattern is truly novel or already captured elsewhere. Proposals let the conductor deduplicate, triage, and batch RAG additions with full project awareness.

## 3-Tier Orchestration Model

```
Tier 0: Main session (Haiku) — Conductor
  ├─ Reads and locks implementation plan
  ├─ Creates phases, launches task instruction subagents
  ├─ Monitors all Tier 1 sessions via database
  └─ Handles reviews, errors, phase transitions

Tier 1: Execution sessions (Opus, EXTERNAL Claude sessions) — MUSICIAN
  ├─ Reads task instruction file
  ├─ Launches Tier 2 subagents for small/isolated work
  ├─ Does direct integration work (refactor, assemble, holistic test)
  ├─ Manages verification checkpoints
  ├─ Coordinates review cycles with conductor
  └─ Handles context-aware pausing and resumption

Tier 2: Subagents (Opus, launched by Tier 1)
  ├─ Receive task-specific instruction sections
  ├─ Do focused implementation (code, unit tests, docs)
  ├─ Self-test via Opus capabilities (no explicit instruction needed)
  └─ Return tested code ready for integration
```

## Execution Model & Tool Utilization

**Subagent Model (Tier 2):**
- Model: **Opus** (proven self-testing capability, 100% coding accuracy in testing)
- Expected behavior: complete code work + self-test in single pass
- Test creation: handled by subagent (returns tested code)
- No explicit testing instructions needed in subagent prompts

**Musician Model (Tier 1):**
- Uses TDD or subagent-driven-development patterns
- Does NOT delegate integration-level work
- Launches subagents for: individual functions, isolated features, unit test refinement, documentation
- Keeps integration, assembly, and holistic testing for itself
- Test coverage maintenance is a key responsibility
- Spec reviews and code reviews as appropriate

## Hybrid Work Distribution

**Musician does directly:**
- Integration work across modules
- Refactoring and assembly
- Holistic/integration testing
- Test coverage analysis
- Code and spec reviews
- Complex decision-making

**Musician delegates to subagents:**
- Individual function implementation
- Isolated feature completion
- Unit test creation
- Documentation writing
- Straightforward, scoped pieces

**Decision heuristic:** If >500 LOC, touches multiple modules, or involves integration/refactoring → musician does it. If <500 LOC, isolated, self-contained → delegate to subagent.

## Bootstrap & Initialization

Execute these steps in order when starting a new musician session:

### 1. Parse Task Identity

The musician's task_id is embedded in its initial prompt (e.g., "Read task #3 from messages"). Parse the task number → `task-03`.

### 1a. Recognize Launch Prompt

The musician is launched with a standardized prompt. Expected structure:

- `/musician` skill invocation
- SQL query to retrieve task instructions from `orchestration_messages` (task_id + message_type = 'instruction')
- Context block with Task ID and Phase info

Parse the task ID from the Context block (e.g., `task-07`). Use the provided SQL query in step 6 to retrieve instructions — do not improvise a different query.

### 2. Session Identity

The `CLAUDE_SESSION_ID` is automatically injected into the system prompt by the SessionStart hook. It is NOT a bash environment variable — it appears in the system prompt context. Validate it is present. If missing, the hook failed — log an error message explaining the failure and exit immediately (this is the one pre-bootstrap case where direct output is necessary since orchestration DB communication requires a session ID).

### 3. Atomic Task Claim

Claim the task with a guard clause to prevent double-claiming:

```sql
UPDATE orchestration_tasks
SET state = 'working',
    session_id = '{session_id}',
    worked_by = 'musician-task-03',
    started_at = datetime('now'),
    last_heartbeat = datetime('now'),
    retry_count = 0
WHERE task_id = 'task-03'
  AND state IN ('watching', 'fix_proposed', 'exit_requested');
```

**Guard clause:** The `state IN ('watching', 'fix_proposed', 'exit_requested')` ensures only claimable states allow the UPDATE. Prevents claiming a task that is already being worked on, already finished, or already exited. Only the first session to execute this UPDATE succeeds (matches 1 row). Any subsequent attempt matches 0 rows.

**Verify `rows_affected = 1`.** If 0, the guard blocked the claim.

### 4. Guard Block Fallback

If the guard blocks (rows_affected = 0), the session cannot claim the task. To exit cleanly:

```sql
-- Create fallback row (NO guard — must always succeed)
INSERT INTO orchestration_tasks (task_id, state, session_id, last_heartbeat)
VALUES ('fallback-{session_id}', 'exited', '{session_id}', datetime('now'));

-- Notify conductor
INSERT INTO orchestration_messages (task_id, from_session, message_type, message)
VALUES ('task-03', '{session_id}', 'claim_blocked',
    'CLAIM BLOCKED: Guard prevented claim on task-03 (state was not claimable).
     Created fallback row to exit cleanly. Conductor intervention needed.');
```

The `fallback-{session_id}` row uses the session ID as suffix for unique primary keys. The hook sees `exited` state for this session and allows clean exit.

### 5. Session Handoff (Conductor Pattern)

When a session needs to exit and a new session takes over:

1. Old session exits → writes HANDOFF, sets state to `exited`
2. Conductor reads HANDOFF → sets state to `fix_proposed` + sends handoff message
3. New session launches → atomic claim succeeds (guard allows `fix_proposed`)
4. New session writes its session ID (from system prompt), continues work

The `worked_by` field tracks session succession:
- First session: `musician-task-03`
- Resumed session: `musician-task-03-S2`
- Third session: `musician-task-03-S3`

### 6. Read Task Instructions

Query `orchestration_messages` for the task instruction:

```sql
SELECT message FROM orchestration_messages
WHERE task_id = 'task-03' AND from_session = 'task-00'
ORDER BY timestamp ASC LIMIT 1;
```

Read the instruction file path from the message, then read the full task instruction file.

If no instruction message is found, send a `claim_blocked` message explaining instructions are missing, create a fallback row (`fallback-{session_id}` with state `exited`), and exit cleanly.

### 7. Initialize temp/ Files

Create task-tagged temporary files:

```
temp/task-03-status
temp/task-03-deviations
```

Write initial status entry:
```
bootstrap started [ctx: 5%]
task claimed, session: {session_id} [ctx: 7%]
instructions loaded: docs/plans/implementation/task-03.md [ctx: 12%]
```

### 8. Launch Background Watcher

Start the background message watcher agent. See [Message Watcher Protocol](#message-watcher-protocol).

### 9. Begin Execution

Start executing task instruction steps. Update heartbeat at each step boundary.

## Parallel Execution Coordination

### Awareness Model

The musician is **partially aware** of parallel siblings:
- Knows it is part of a parallel phase (stated in task instructions)
- Does NOT communicate directly with other musicians
- Can query sibling task states from `orchestration_tasks` if needed
- All cross-musician communication goes through the conductor as intermediary

### Sibling Independence

By default, each musician operates independently:
- **Review checkpoints:** Each musician blocks only on its own review. Sibling musicians keep working.
- **Errors:** If one musician hits an error, siblings continue. The conductor sends emergency messages if cross-cutting intervention is needed.
- **Context exhaustion:** If one musician exits for context, siblings continue. The conductor handles reassignment.

This default can be overridden by task instructions (e.g., "pause all musicians at checkpoint 3 for cross-task integration review").

### Emergency Messages

The conductor may send emergency messages to musicians during parallel execution. Each musician's background watcher monitors for messages addressed to its task_id.

**Message format:** The conductor sends **separate messages per task** (one INSERT per task_id). No body parsing required — the watcher simply watches its own `task_id` column.

**Musician response to emergency messages:** The musician judges urgency based on the message content and instructions. Options:
- Kill current subagent immediately (urgent: "stop all work")
- Wait for current subagent to finish (informational: "heads up about future step")
- Acknowledge and continue (advisory: instructions for a step not yet in progress)

The musician trusts the conductor to send interrupts when something cross-cutting needs attention. No preemptive reaction to sibling problems.

### Database Queries for Parallel Awareness

**Check sibling task states (optional, on-demand):**

```sql
SELECT task_id, state, last_heartbeat
FROM orchestration_tasks
WHERE task_id != 'task-00' AND task_id != 'task-03'
ORDER BY task_id;
```

**Check for messages from conductor:**

```sql
SELECT id, message, timestamp FROM orchestration_messages
WHERE task_id = 'task-03'
  AND from_session = 'task-00'
  AND id > {last_processed_message_id}
ORDER BY id;
```

## Message Watcher Protocol

The musician uses two watcher agents with distinct roles. Both modes include heartbeat refresh.

### Heartbeat Refresh (Both Modes)

Every poll cycle, the watcher checks `last_heartbeat` age. If >8 minutes old, refresh it:

```sql
UPDATE orchestration_tasks
SET last_heartbeat = datetime('now')
WHERE task_id = 'task-03';
```

The conductor's staleness threshold is 9 minutes. The 1-minute buffer between refresh (8 min) and concern (9 min) prevents false alarms while catching genuine crashes quickly.

If the watcher is alive, the session is alive. If the session crashes, the watcher dies with it, heartbeat goes stale, conductor detects it.

### Background Watcher (During Active Work)

**Launched:** At bootstrap and after resume mode.

**Runs:** In background (`run_in_background=True`) while musician works.

**Poll cycle:**
1. Query `orchestration_messages` for new messages from conductor
2. Check `last_heartbeat` age → refresh if >8 minutes
3. Sleep, repeat

**Query:**

```sql
SELECT id, message, timestamp FROM orchestration_messages
WHERE task_id = 'task-03'
  AND from_session = 'task-00'
  AND id > {last_processed_message_id}
ORDER BY id;
```

**On message detected:** The watcher immediately exits. The musician detects the watcher exit, reads the message from the database, decides whether to interrupt current work (urgent) or continue (informational), and immediately relaunches the background watcher.

### Pause Watcher (During Conductor Wait)

**Launched:** When musician sets `error` or `needs_review` and needs to wait for conductor response.

**Runs:** In foreground (blocks musician).

**Transition to pause mode:**
1. Musician sets state (`error` or `needs_review`) + sends message
2. Terminate background watcher
3. Exit all active subagents
4. Launch foreground pause watcher (musician blocks)

**Poll cycle:**
1. Query `orchestration_tasks` for state change on this task
2. Check `last_heartbeat` age → refresh if >8 minutes
3. Sleep, repeat

**Exit condition query:**

```sql
SELECT state FROM orchestration_tasks
WHERE task_id = 'task-03';
```

The pause watcher exits when the task's state changes to something other than `error` or `needs_review`. This is how the musician detects that the conductor has responded. Once detected, the watcher exits. The musician then reads the new state and latest message from the database.

**Timeout behavior:** 15-minute timeout. Before declaring the conductor unresponsive, the watcher checks the conductor's heartbeat (`SELECT last_heartbeat FROM orchestration_tasks WHERE task_id = 'task-00'`). If the conductor's heartbeat is recent (within 9 minutes), the conductor is alive but busy — retry the watcher. If the conductor's heartbeat is stale, the conductor may have crashed — return timeout indicator to musician for escalation.

### Resume Mode (After Processing Response)

After musician receives and processes the conductor's response:
1. Terminate foreground pause watcher
2. Restart background watcher
3. Resume musician work

### Watcher Lifecycle Summary

```
Bootstrap → Background Watcher (working)
         ↓ (needs_review or error)
    Terminate background → Exit subagents → Foreground Watcher (paused)
         ↓ (conductor responds)
    Terminate foreground → Background Watcher (resumed)
         ↓ (next checkpoint or error)
    [cycle repeats]
         ↓ (completion)
    Terminate all watchers → Clean exit
```

## Context Monitoring & Break Point Logic

**Hyper-focused monitoring:**
- Musician tracks context with each system message received
- Quick, lightweight checks (minimal overhead)
- No continuous evaluation — only triggers at thresholds

**Evaluation trigger: 50% context usage**

When musician reaches 50% context usage, it evaluates whether it can reach the next scheduled (task instruction) checkpoint:

- **<70% context to reach checkpoint** → proceed as normal, no escalation
- **70-80% context to reach checkpoint** → message conductor: "I think I can reach the checkpoint, but what do you think?" (ask for confirmation)
  - Include in message: current context usage %, estimated context to reach checkpoint, **per-remaining-agent estimates**, **how many agents fit in 65% context**, deviations + complexity assessment
- **>80% context to reach checkpoint** → escalate to conductor (must pause now)
  - Same message format with agent estimates

**Agent estimation is required for ANY context worry pause** (50%, 70-80%, or >80% escalation), not just one zone.

**REF-3: Agents-Remaining Estimation Algorithm.** Calculate how many agents fit in the remaining budget: `(65% - current_context%) / avg_agent_cost%`. Use 8% as the default average agent cost (adjust based on actual costs of previous agents in this session). This estimate goes into the conductor message.

**Context escalation is an error state.** The musician sets `state = 'error'` (not `needs_review`) with `last_error = 'context_exhaustion_warning'`. This signals to the conductor that the musician cannot reliably continue without intervention.

**Context escalation response states from conductor:**
1. `review_approved` — "Proceed as planned to checkpoint, then stop and report back for clean handoff"
2. `fix_proposed` — "Only complete 2 more agents then prepare handoff" OR "Adjust approach as follows: [instructions]"
3. `review_failed` — "Do not proceed, prepare handoff now"

Musician waits for conductor state update before continuing (via pause watcher).

**REF-4: Context Checkpoint Priority.** If both a context threshold and a task instruction checkpoint trigger simultaneously, context check takes priority. Address the context concern before proceeding to checkpoint verification.

## Checkpoint Types & Verification

**Task Instruction Checkpoints (preferred):**
- Defined in task instructions
- Scheduled verification points
- Musician runs verification tests at these points

**Context Worry Checkpoints (fallback):**
- Musician-initiated early breaks
- Triggered when context math doesn't allow reaching next scheduled checkpoint
- Same verification test protocol applies

**Verification Testing Protocol:**
- Tests run **only at checkpoints** (task instruction or context worry)
- Musician verifies first, reports second
- Test validation is **always** injected at checkpoints, even if instructions don't mention it
- Validation includes: running tests, checking coverage, testing the tests themselves
- Not run after each subagent completes (batched at checkpoints)
- Musician collects subagent results, then does comprehensive verification pass at checkpoint

**Checkpoint workflow:**
1. Musician reaches checkpoint
2. Run verification tests (test the tests + any checkpoint tests)
3. Report results to conductor (set `needs_review`)
4. Launch pause watcher — wait for response
5. On `review_approved` → proceed to next section
6. On `review_failed` → process feedback, fix, re-submit
7. Context enforcement beforehand ensures safe execution of tests

## Review & Conductor Communication

### Review Request Flow

At each checkpoint, the musician sends a review request:

1. Set `state = 'needs_review'` + send review message
2. Transition to pause mode (terminate background watcher, exit subagents, launch foreground watcher)
3. Wait for conductor response
4. Foreground watcher detects state change and exits; musician reads new state + message from DB
5. Process response based on state

### Response Handling

**`review_approved`:**
- Launch background watcher
- Read approval message for any notes
- Proceed with next steps

**`review_failed`:**
- Launch background watcher
- Read rejection message for required changes
- Apply feedback
- Re-run verification tests
- Re-submit for review (back to `needs_review`)

**`fix_proposed`:**
- Launch background watcher
- Read proposal message for specific instructions
- Apply proposed changes/adjustments
- Re-run verification tests
- Re-submit for review (back to `needs_review`)

### Context Usage in All Messages

**Every message to the conductor includes context usage.** This is feasible because the only messages the musician sends are:

1. Review requests (`needs_review`) — checkpoint reviews
2. Completion reports (`needs_review`) — final review
3. Error reports (`error`) — failures, context warnings
4. Claim blocked (`fallback-{session_id}`) — guard clause failure

All are significant events where context reporting is natural.

### No Proactive Pings

The musician does NOT send status updates or progress pings mid-work. The conductor monitors passively via:
- Database state and heartbeat queries
- Reading `temp/task-XX-status` via subagent (no musician interruption needed)

## Proposal System

The musician and its subagents create proposals **JIT (just-in-time)** whenever they discover patterns, anti-patterns, learnings, or anything worth preserving. Proposals are created liberally and verbosely — the conductor handles deduplication and integration.

**Musician does NOT directly modify:** MEMORY.md, CLAUDE.md, RAG content, or memory MCP. It creates proposals in `docs/implementation/proposals/` and the conductor integrates them.

**Proposal types the musician should watch for:**
- `PATTERN` — Reusable patterns discovered during implementation
- `ANTI_PATTERN` — Approaches that fail or cause problems (document WHY)
- `MEMORY` — Cross-session learnings, project conventions, debugging strategies
- `CLAUDE_MD` — Rules or conventions that should be enforced project-wide
- `RAG` — Knowledge-base content worth preserving for future sessions
- `MEMORY_MCP` — Entities, relations, observations for the memory graph
- `DOCUMENTATION` — Gaps in existing documentation

**Guidelines:**
- Create proposals at any time during execution (not just at checkpoints)
- Be verbose — better to over-document than to lose insights
- Don't worry about duplicates — conductor deduplicates during integration
- Tag files per README conventions: `YYYY-MM-DD-brief-description.md`
- Include clear rationale (WHY, not just WHAT)
- Anti-patterns are as valuable as patterns — always document failures and why they failed
- See `docs/implementation/proposals/README.md` for full template and workflow

## Message Format Standards

### Review Request

```
REVIEW REQUEST (Smoothness: 4/9):
  Checkpoint: 2 of 5
  Context Usage: 47%
  Self-Correction: YES (step 2, agent 3 — test failure in auth module, rewrote validation logic. ~6x context impact for affected segment)
  Deviations: 1 (Medium — switched from TDD to fix-first due to flaky test fixture)
  Agents Remaining: 3 (~8% context each, ~24% total)
  Proposal: docs/implementation/proposals/task-03-auth-validation.md
  Summary: Completed auth module extraction, 2 knowledge-base files created
  Files Modified: 8
  Tests: All passing (14 tests, 2 new)
```

### Context Warning (Error State)

```
CONTEXT WARNING: 58% usage
  Self-Correction: YES (step 3, agent 1 — integration test mismatch, refactored connector. ~6x context impact)
  Agents Remaining: 4 (~8% each, ~32% total)
  Agents That Fit in 65% Budget: 1 (due to self-correction bloat)
  Deviations: 2 (1 Medium, 1 Low)
  Awaiting conductor instructions
```

### Key Outputs Format

Included in review, error, and completion messages:

```
Key Outputs:
  - path/to/file.md (created)
  - path/to/other.ts (modified)
  - docs/implementation/proposals/rag-something.md (rag-addition)
```

All paths project-root-relative. Each entry annotated: `(created)`, `(modified)`, or `(rag-addition)`. Include significant file creations, proposals, and reports. Exclude minor edits (those stay in the `Files Modified` count).

### Completion Report

```
TASK COMPLETE (Smoothness: 1/9):
  Context Usage: 62%
  Self-Correction: NO
  Deviations: 0
  Report: docs/implementation/reports/task-03-completion.md
  Summary: All deliverables created, tests passing, ready for integration
  Files Modified: 14
  Tests: All passing (28 tests, 12 new)
```

### Error Report

```
ERROR (Retry 1/5):
  Context Usage: 38%
  Self-Correction: NO
  Error: test_auth_integration timeout
  Report: docs/implementation/reports/task-03-error-retry-1.md
  Awaiting conductor fix proposal
```

### Claim Blocked

```
CLAIM BLOCKED: Guard prevented claim on task-03 (state was not claimable).
  Created fallback row to exit cleanly. Conductor intervention needed.
```

## Temporary File Management

**CRITICAL: Always use `temp/` (project root), NEVER `/tmp/` or any absolute tmp path.** `temp/` is a symlink — it provides ephemerality with a project-relative path that the conductor can find.

**Location:** `remindly/temp/`

`temp/` is disposable scratch space — no cleanup needed, no file management required. Files auto-clear on system reboot. This is in contrast to `docs/`, which is strictly governed (structured directories, controlled file creation, no temporary files except proposals).

**File naming:** All files are tagged with task_id to prevent conflicts across parallel and successive sessions. Multiple sessions working on the same task (original + resumption) all write to the same files, building a continuous history.

**File structure:**

1. **status file** (`temp/task-03-status`)
   - Append-only log of step progress with context usage
   - **Normal entries:** `step 1 started [ctx: 12%]`, `step 1 completed [ctx: 18%]`
   - **Deviation entries:** `step 2 deviation: switched parsing strategy (Medium) [ctx: 41%]`
   - **Self-correction entries:** `step 2 self-correction: test failure in parser, rewrote tokenizer [ctx: 34%]`
   - **Agent entries:** `step 2 agent 1 launched [ctx: 21%]`, `step 2 agent 1 returned [ctx: 29%]`
   - **Exception:** On resumption, musician writes verbose comprehensive takeover message showing comprehension of state
   - Resumption update includes: task state, deviations found, issues with status/comms table, pending conductor messages, other relevant details
   - Serves as historical record AND passive monitoring channel (conductor can peek without interrupting musician)

2. **deviations file** (`temp/task-03-deviations`)
   - Tracked throughout execution
   - Read only when musician checks in with conductor
   - Records: deviations from plan, approach changes, complexity assessments
   - Complexity levels: Low (minor), Medium (notable), High (major)
   - Escalation threshold: >2 deviations triggers report to conductor

3. **HANDOFF file** (`temp/task-03-HANDOFF`)
   - Created **only on clean exit**
   - Comprehensive handoff document
   - Includes clean exit protocol and resumption instructions
   - Primary healthiness indicator for previous session
   - Checked first by resuming session

## Deviations & Escalation Thresholds

**Deviation tracking:**
- All deviations from plan recorded in `temp/task-XX-deviations`
- Musician self-assesses complexity level: Low (minor), Medium (notable), High (major)
- Conductor counts Medium+ as hard gates for progress

**REF-5: Deviation Severity Definitions.**
- **Low** = no timeline impact, minor approach change
- **Medium** = <1 hour impact, notable approach change
- **High** = >1 hour impact, significant scope or architecture change

**Self-correction flag:**
- Binary: did musician correct its own code in this session?
- **Critical signal** to conductor: if self-correction occurred, context usage estimates are off by **~6x**
- Opus is strong, but during self-correction phases it becomes immensely context-heavy
- Logged in `temp/task-XX-status` with details: `self-correction: true (step 3, agent 2 — test failure, rewrote auth module)`
- Reported in ALL review/completion/error messages to conductor
- Impacts conductor's context planning: should plan for early handoff when flagged

**Escalation triggers:**
- >2 tasks with deviations between temp/ and comms table
- >2 tasks in `working` state (potential crash indicator)
- **REF-6: 2+ Medium deviations OR 1+ High deviation** triggers escalation to conductor (replaces vague ">2 deviations" rule)
- Self-correction issues during execution

## Heartbeat Protocol

**Step-boundary heartbeats:** The musician updates `last_heartbeat` at every step start and step complete:

```sql
UPDATE orchestration_tasks
SET last_heartbeat = datetime('now')
WHERE task_id = 'task-03';
```

**Watcher-driven heartbeats:** Both background and foreground watchers refresh `last_heartbeat` if >8 minutes old. This catches long-running steps where step boundaries are far apart.

**Staleness detection (conductor side):**
- 9-minute threshold for concern
- 1-minute buffer between watcher refresh (8 min) and conductor alarm (9 min)
- Stale heartbeat + `working` state → session likely crashed

**Heartbeat update points:**
- State transitions (automatic — every state change updates `last_heartbeat`)
- Step started
- Step completed
- Watcher refresh (>8 minutes since last update)

## Clean Exit Protocol

When musician cleanly reaches handoff point (context exhaustion, task completion, etc.):

1. Exit all active subagents
2. Terminate all watchers
3. Create verbose HANDOFF document in `temp/task-XX-HANDOFF`
   - Include: session ID, current context state, what was completed, what's pending, next steps
   - Include clean exit protocol instructions
   - Include resumption instructions
4. Write completion report to `report_path`
5. Echo "clean exit" message to `temp/task-XX-status`
6. Write final message to `orchestration_messages`
7. **LAST STEP:** Set state to `exited` (or `complete` for task completion)

`complete` and `exited` are terminal signals to the implementation-hook. They must be the **absolute last database write** — nothing should happen between setting the terminal state and the session ending. This prevents accidental early exit between completion cleanup steps.

If watcher/subagent termination fails (TaskStop errors), proceed to terminal state write anyway. Do not let cleanup failures prevent clean exit.

## Completion Flow

When the musician finishes all steps:

1. Execute final step and collect all subagent results
2. Run final checkpoint verification (tests, coverage, test validation)
3. Set `needs_review` + send completion report message (final review)
4. Launch pause watcher (foreground) — wait for conductor's final approval

**REF-8: Final Verification Requirement.** Final checkpoint ALWAYS runs full verification (tests, coverage, integration check) before reporting completion. Never skip verification on the final checkpoint, even if previous checkpoint passed.
5. **On `review_approved`:**
   - Process any final feedback notes
   - Write completion report to `report_path` location
   - Clean up any remaining work
   - Write final message to `orchestration_messages`
   - **LAST STEP:** `UPDATE orchestration_tasks SET state = 'complete'`
6. **On `review_failed`:**
   - Process feedback
   - Fix issues
   - Re-run verification
   - Loop back to step 3 (re-submit for review)

## Mid-Session Resumption Protocol

**Scenario:** Session 1 exits (context exhaustion or otherwise). Session 2 launches to resume.

**Session 2 startup:**

1. **Perform full bootstrap** — Parse task identity, claim task (guard allows `fix_proposed` from conductor), read instructions, initialize database connection
2. **Read all temp/ files** — `task-XX-status`, `task-XX-deviations`, `task-XX-HANDOFF` (if exists)
3. **Assess health:**
   - If HANDOFF exists and is fresh: previous session exited cleanly
     - Check for conductor message
     - Apply any fixes, re-run verification tests (ALWAYS, even if conductor approved)
   - Otherwise (HANDOFF missing/stale): session likely exited forcefully at high context
     - Read conductor message
     - Apply fixes
     - Re-run verification tests
     - Include "HANDOFF missing/stale" fact in resumption status message

4. **Handle in-progress/mismatch states:**
   - If temp and/or comms table show in-progress OR differing states:
     - Create new verification task
     - Launch agent with this task
     - Review results
     - If complete: echo corrections to temp/comms
     - If partial: create task-specific correction task with verification, run again
     - If fully incomplete: echo corrective message in temp/comms
     - Log all to deviations file

5. **Escalation check:**
   - If >2 tasks with deviations (temp vs. comms mismatch) OR >2 tasks in `working` state
   - Report to conductor for further instruction
   - When >2 deviations exist, the conductor may issue a **correction task** — a scoped set of fixes to apply before resuming normal execution. The musician applies correction task steps first, re-runs verification, then resumes from the last checkpoint.
   - Reason: prior session may have crashed forcefully
   - Fresh session should comprehensively evaluate ALL in-progress tasks (save conductor context, use fresh window)
   - May indicate need for git-revert

6. **Write resumption status message**
   - Verbose, comprehensive (exception to echo protocol)
   - Shows musician's comprehension of state it took over
   - Include: deviations found, status/comms issues, pending messages, task assessment, context usage
   - Serves as "I'm taking over now" signal
   - Written to both `temp/task-XX-status` and `orchestration_messages`

## Implementation-Hook Integration

The musician relies on two hooks that are self-configuring:

**SessionStart hook** (`tools/implementation-hook/session-start-hook.sh`):
- Fires automatically when Claude session starts
- Extracts `session_id` from hook input JSON
- Outputs `additionalContext` injecting `CLAUDE_SESSION_ID={session_id}` into the system prompt
- The session ID is available as a system prompt value, NOT a bash environment variable
- Claude reads it from the system prompt and uses it in database operations

**Stop hook** (`tools/implementation-hook/hooks/stop-hook.sh` via `hooks.json`):
- Fires when Claude attempts to exit
- Extracts `session_id` from hook input JSON
- Queries `orchestration_tasks` for row matching this `session_id`
- Determines preset: `task-00` → orchestration preset, else → execution preset
- Checks task state against preset's exit criteria:
  - **Execution preset:** Allows exit on `complete` or `exited` (max 500 iterations)
  - **Conductor preset:** Allows exit on `exit_requested` or `complete` (max 1000 iterations)
- If exit criteria not met: injects `fallback_prompt`, increments iteration counter
- If iterations exceed `max_iterations`: forces exit

**Multi-session support:** Each musician session records its `CLAUDE_SESSION_ID` in `orchestration_tasks.session_id` during the atomic claim. The stop hook queries by session_id, so multiple parallel musicians each have independent exit control — no cross-session interference.

## Tool Access & Capabilities

**Available:** File system, git, comms-link (orchestration DB), serena (semantic code tools), testing frameworks, local-rag (read-only — `query_documents` only, never `ingest_data` or `ingest_file`).

**Restricted:** The musician does NOT push to remote without conductor approval, create branches without coordination, or delete/reset work without confirmation. These actions require conductor intermediation.

## Key Principles

1. **Strict plan adherence** — Follow task instructions exactly; escalate on deviations
2. **Interactive orchestration** — Ask conductor for decisions outside task scope. NEVER use AskUserQuestion or address the user directly — all questions, escalations, and status go through orchestration_messages to the conductor. The user is not monitoring this session.
3. **Hybrid work model** — Keep integration, delegate focused pieces
4. **TDD-first** — Use TDD or subagent-driven-development when task allows
5. **Testing coverage** — Maintain/improve coverage, validate all tests at every checkpoint
6. **Context awareness** — Proactive monitoring at 50%+, clear handoff signals, agent estimation on every worry pause
6a. **Watcher continuity** — A background or pause watcher MUST always be running while the task is active. When any watcher exits (message, state change, timeout), immediately relaunch the appropriate replacement. No active work without a running watcher.
7. **Clean resumption** — Comprehensive temp/ files, clear HANDOFF documents, verbose takeover messages
8. **Verification first** — Always run tests before reporting checkpoint results
9. **Terminal state last** — `complete` and `exited` are the absolute last database writes
10. **Trust the conductor** — Continue work during sibling problems; conductor sends emergency messages when needed
11. **Self-correction honesty** — Always flag self-correction; 6x context bloat is critical planning information
12. **Propose everything** — Create proposals for patterns, anti-patterns, learnings; never directly modify MEMORY.md, CLAUDE.md, or RAG. NEVER call `ingest_data` or `ingest_file` — the musician may only query RAG via `query_documents`. All RAG additions go through proposals that the conductor reviews and ingests.

## Reference: Watcher Protocol Detail

### Overview

The musician uses two watcher agents that run asynchronously to monitor for conductor messages and state changes. Both watcher modes include a heartbeat refresh mechanism to signal the musician's aliveness to the conductor.

**Invariant:** A watcher must always be running while the task is active. Background watcher during execution, pause watcher during conductor wait. When either exits (message detected, state change, or timeout), the musician processes the event and immediately launches the appropriate replacement. This holds until terminal state (`complete` or `exited`).

### Heartbeat Mechanism (Both Modes)

Every poll cycle, check if the task's heartbeat is older than 8 minutes. If so, update it to the current time. The conductor considers a task stale after 9 minutes without a heartbeat, so this 1-minute buffer ensures the musician's liveness is always detected if the watcher is running.

If the watcher dies (session crashes), the heartbeat becomes stale and the conductor detects the failure. This mechanism is the musician's way of saying "I'm still here and working."

### Background Watcher (During Active Work)

**When launched:** At bootstrap and after resuming from pause mode.

**Runs:** In the background while the musician performs implementation work.

**Polling cycle:**
1. Query the database for new messages from the conductor addressed to this task
2. Check the task's heartbeat age and refresh if older than 8 minutes
3. Sleep for 15 seconds
4. Repeat

If a new message is detected, the watcher immediately exits. The musician detects the watcher exit, reads the message from the database, decides whether to interrupt current work (urgent) or continue (informational), and immediately relaunches the background watcher.

**Key behavior:** The background watcher uses message ID-based tracking to avoid processing the same message twice. After querying and processing a message, it updates its internal state to track that message ID, then only queries for messages with higher IDs on subsequent polls.

### Background Watcher Prompt Template

```
Task("Watch for conductor messages", prompt="""
You are a background message watcher for musician task-{task_id}.

POLL CYCLE (repeat until message found or terminated):
1. Query for new messages:
   SELECT id, message, timestamp FROM orchestration_messages
   WHERE task_id = '{task_id}'
     AND from_session = 'task-00'
     AND id > {last_processed_message_id}
   ORDER BY id;

2. If message found: Exit immediately with the message content, id, and timestamp.

3. Check heartbeat age:
   SELECT (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
   FROM orchestration_tasks WHERE task_id = '{task_id}';
   If seconds_stale > 480 (8 minutes): Update heartbeat:
   UPDATE orchestration_tasks SET last_heartbeat = datetime('now')
   WHERE task_id = '{task_id}';

4. Wait 15 seconds, repeat from step 1.

Use comms-link query for SELECTs, comms-link execute for UPDATEs.
""", subagent_type="general-purpose", model="haiku", run_in_background=True)
```

### Pause Watcher (During Conductor Wait)

**When launched:** When the musician sets its state to `error` or `needs_review` and must wait for an conductor response.

**Runs:** In the foreground, blocking the musician from proceeding.

**Polling cycle:**
1. Query the task state from the database
2. Check the task's heartbeat age and refresh if older than 8 minutes
3. Sleep for 10 seconds
4. Repeat until state change

The pause watcher exits when the task's state changes to something other than `error` or `needs_review`. This is how the musician detects that the conductor has responded. Once detected, the watcher exits. The musician then reads the new state and latest message from the database.

**Timeout behavior:** If the pause watcher has been waiting more than 15 minutes, before declaring the conductor unresponsive, it checks the conductor's own heartbeat. If the conductor's heartbeat is fresh (within 9 minutes), the conductor is alive but busy, so the watcher continues waiting. If the conductor's heartbeat is stale (older than 9 minutes), the conductor may have crashed, and the watcher exits with a timeout indicator so the musician can escalate.

### Pause Watcher Prompt Template

```
Task("Wait for conductor response", prompt="""
You are a foreground watcher for musician task-{task_id}, waiting for conductor response.
The musician has set state to '{current_state}' and is blocked until the conductor responds.

POLL CYCLE (repeat until state change, timeout, or terminated):
1. Check task state:
   SELECT state FROM orchestration_tasks WHERE task_id = '{task_id}';
   If state NOT IN ('error', 'needs_review'): State has changed — proceed to step 5.

2. Check heartbeat age:
   SELECT (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
   FROM orchestration_tasks WHERE task_id = '{task_id}';
   If seconds_stale > 480 (8 minutes): Update heartbeat:
   UPDATE orchestration_tasks SET last_heartbeat = datetime('now')
   WHERE task_id = '{task_id}';

3. Check elapsed time. If >15 minutes since watcher started:
   Check conductor heartbeat before giving up:
   SELECT last_heartbeat, (julianday('now') - julianday(last_heartbeat)) * 86400 as orch_stale
   FROM orchestration_tasks WHERE task_id = 'task-00';
   If orch_stale < 540 (9 minutes): Conductor alive but busy. Continue waiting (reset timeout).
   If orch_stale >= 540: Conductor may be down. Exit with TIMEOUT indicator.

4. Wait 10 seconds, repeat from step 1.

5. State changed. Exit immediately — musician will read latest message from DB.

Use comms-link query for SELECTs, comms-link execute for UPDATEs.
""", subagent_type="general-purpose", model="haiku")
```

### Mode Transitions

**Working → Pause (checkpoint or error reached):**
1. Musician sets state (`needs_review` or `error`) and sends a message
2. Terminate the background watcher if running
3. Exit all active subagents to free resources
4. Launch the pause watcher in foreground mode
5. Musician blocks until pause watcher exits

**Pause → Resume (conductor responds):**
1. Pause watcher detects state change and exits
2. Musician processes the response (apply feedback, adjust scope, etc.)
3. Launch a new background watcher
4. Resume execution

**Timeout handling:**
1. If pause watcher times out after 15 minutes, check conductor health first
2. If conductor is alive but slow: retry the pause watcher
3. If conductor appears down: update temp/ status files, set state to `error`, send timeout message, and relaunch pause watcher for recovery
4. If timeout happens twice: write HANDOFF, exit cleanly

### Watcher Lifecycle Tracking

Maintain two variables to track watcher task IDs: `background_watcher_id` and `pause_watcher_id`. Before launching any new watcher, terminate all previous watchers using the Task tool's stop capability. This ensures clean lifecycle management and prevents orphaned watchers.

**Critical rule:** Never have two watchers of the same type running simultaneously. Each transition between modes must explicitly terminate the old watcher before launching the new one.

### Message Deduplication

The background watcher must deduplicate messages to avoid processing the same message twice. Instead of using timestamps (which can be identical for multiple messages), use message ID (auto-incrementing integer).

**Implementation:**
- Track `last_processed_message_id` as an integer, initialized to 0
- Query for messages where `id > last_processed_message_id`
- After processing each message, update `last_processed_message_id` to that message's ID

This approach is safer than timestamp-based tracking because message IDs are guaranteed unique and monotonically increasing, avoiding race conditions where identical timestamps cause messages to be missed or processed twice.

## Reference: Musician State Machine

### States the Musician Sets

The musician manages its own state transitions in the orchestration database:

- **`working`** — Task has been claimed and execution is in progress
- **`needs_review`** — A checkpoint has been reached and verification tests passed; awaiting conductor approval
- **`error`** — An unrecoverable failure occurred or context exhaustion warning triggered; awaiting conductor instructions
- **`complete`** — All task steps are done and the conductor has approved completion (terminal state)
- **`exited`** — The musician has prepared a clean handoff for context exhaustion or other early termination (terminal state)

### States the Conductor Sets

The conductor responds with these states:

- **`watching`** — Task created, not yet claimed by any musician
- **`review_approved`** — Checkpoint review passed; musician proceeds with next steps
- **`review_failed`** — Checkpoint review rejected; musician applies feedback and re-submits
- **`fix_proposed`** — Conductor has a specific fix or adjustment; musician applies it and re-submits
- **`exit_requested`** — Conductor requests musician to prepare handoff and exit

### Valid State Transitions

Musician initiates these transitions:

```
watching → working              (atomic claim succeeds at bootstrap)
working → needs_review          (checkpoint reached, tests pass)
working → error                 (failure, context worry, timeout)
review_approved → working       (implicit; musician resumes work)
review_approved → needs_review  (completion review after final step)
review_failed → needs_review    (re-submit after applying feedback)
fix_proposed → working          (implicit; musician resumes after fix)
fix_proposed → needs_review     (re-submit after applying proposed fix)
working → complete              (TERMINAL: after conductor approves)
working → exited                (TERMINAL: clean handoff for context exhaustion)
error → exited                  (TERMINAL: unrecoverable failure)
```

### Guard Clause Rules

The atomic claim uses a guard clause to prevent double-claiming:

```
WHERE state IN ('watching', 'fix_proposed', 'exit_requested')
```

States that **allow** claiming: `watching`, `fix_proposed`, `exit_requested`

States that **block** claiming: `working`, `complete`, `exited`, `review_approved`, `review_failed`, `error`, `needs_review`

The conductor always intermediates crash recovery. If a session crashes in `review_approved`, `needs_review`, `error`, or `review_failed`, the conductor detects the stale heartbeat, reviews state, sends a handoff message, and sets `fix_proposed`. New sessions only need to claim from the 3 conductor-prepared states.

If the guard blocks (no rows matched), the session cannot claim the task. Fallback: create a `fallback-{session_id}` row with state `exited` so the hook allows clean session exit.

### Terminal States

Once a task reaches `complete` or `exited`, it cannot transition back to an active state. These are absolute end states. The musician must treat these writes as irreversible.

## Reference: Musician Database Queries

This reference describes the database operations the musician performs, organized by lifecycle phase.

### Bootstrap Queries

**1. Atomic Task Claim**

Update the task row to claim it: set state to `working`, record the session ID, start time, and last heartbeat. The claim includes a guard clause that only allows the update if the current state is in the set of claimable states. This prevents double-claiming.

```sql
UPDATE orchestration_tasks
SET state = 'working',
    session_id = '{session_id}',
    worked_by = 'musician-task-{NN}',
    started_at = datetime('now'),
    last_heartbeat = datetime('now'),
    retry_count = 0
WHERE task_id = 'task-{NN}'
  AND state IN ('watching', 'fix_proposed', 'exit_requested');
```

Verify that exactly 1 row was affected. If 0 rows, the guard blocked the claim and the session cannot proceed with this task.

**2. Guard Block Fallback**

If the guard blocks the claim, the session must still exit cleanly. Create a fallback row with `task_id = 'fallback-{session_id}'`, state `exited`, using the current session ID. This row tells the hook that the session should exit cleanly. Send a message to the conductor explaining that the claim was blocked.

```sql
INSERT INTO orchestration_tasks (task_id, state, session_id, last_heartbeat)
VALUES ('fallback-{session_id}', 'exited', '{session_id}', datetime('now'));

INSERT INTO orchestration_messages (task_id, from_session, message_type, message)
VALUES ('task-{NN}', '{session_id}', 'claim_blocked',
    'CLAIM BLOCKED: Guard prevented claim on task-{NN}. Conductor intervention needed.');
```

**3. Read Task Instruction**

Query for the message with `task_id = '{task_id}'` AND `message_type = 'instruction'` from the conductor (from_session = 'task-00'). This message contains the task instruction file path. Read and parse the full task instruction file.

```sql
SELECT message FROM orchestration_messages
WHERE task_id = 'task-{NN}' AND from_session = 'task-00'
  AND message_type = 'instruction'
ORDER BY timestamp ASC LIMIT 1;
```

### Execution Queries

**4. Heartbeat Update (Step Boundary)**

At each step boundary in task execution, update the task row's `last_heartbeat` to the current time.

```sql
UPDATE orchestration_tasks
SET last_heartbeat = datetime('now')
WHERE task_id = 'task-{NN}';
```

**5. Review Request (Checkpoint)**

When reaching a checkpoint and verification tests pass, update the task state to `needs_review` and send a message to the conductor. The message contains checkpoint number, context usage, self-correction status, deviations, agent estimates, proposal paths, summary, files modified, test status, and key outputs.

```sql
UPDATE orchestration_tasks
SET state = 'needs_review', last_heartbeat = datetime('now')
WHERE task_id = 'task-{NN}';

INSERT INTO orchestration_messages (task_id, from_session, message_type, message)
VALUES ('task-{NN}', '{session_id}', 'review_request',
    'REVIEW REQUEST (Smoothness: X/9):
     Checkpoint: N of M
     Context Usage: XX%
     Self-Correction: YES/NO (details)
     Deviations: N (severity — description)
     Agents Remaining: N (~X% each, ~Y% total)
     Proposal: path/to/proposal.md
     Summary: what was accomplished
     Files Modified: N
     Tests: status
     Key Outputs:
       - path/to/file (created)
       - path/to/other (modified)');
```

**6. Context Warning (Error State)**

If context usage reaches a warning threshold, update state to `error` with `last_error = 'context_exhaustion_warning'`. Send a message including context usage, self-correction status, agent estimates, budget fit, and deviations.

```sql
UPDATE orchestration_tasks
SET state = 'error', last_heartbeat = datetime('now'),
    last_error = 'context_exhaustion_warning'
WHERE task_id = 'task-{NN}';

INSERT INTO orchestration_messages (task_id, from_session, message_type, message)
VALUES ('task-{NN}', '{session_id}', 'context_warning',
    'CONTEXT WARNING: XX% usage
     Self-Correction: YES/NO
     Agents Remaining: N (~X% each, ~Y% total)
     Agents That Fit in 65% Budget: N
     Deviations: N (details)
     Awaiting conductor instructions');
```

**7. Error Report (Failure State)**

When an unrecoverable error occurs, update state to `error`, increment retry count, and set `last_error` to the error description. Send a message with retry count, context usage, error description, report path, and key outputs.

```sql
UPDATE orchestration_tasks
SET state = 'error', last_heartbeat = datetime('now'),
    retry_count = retry_count + 1,
    last_error = 'error description'
WHERE task_id = 'task-{NN}';

INSERT INTO orchestration_messages (task_id, from_session, message_type, message)
VALUES ('task-{NN}', '{session_id}', 'error',
    'ERROR (Retry N/5):
     Context Usage: XX%
     Self-Correction: YES/NO
     Error: description
     Report: path/to/error-report.md
     Key Outputs:
       - path/to/file (created)
     Awaiting conductor fix proposal');
```

**8. Completion Report (Final Checkpoint)**

When all task steps are complete, update state to `needs_review` (for final approval) and send a completion message including smoothness score, context usage, self-correction, deviations, report path, deliverables, files modified, test status, and key outputs.

```sql
UPDATE orchestration_tasks
SET state = 'needs_review', last_heartbeat = datetime('now')
WHERE task_id = 'task-{NN}';

INSERT INTO orchestration_messages (task_id, from_session, message_type, message)
VALUES ('task-{NN}', '{session_id}', 'completion',
    'TASK COMPLETE (Smoothness: X/9):
     Context Usage: XX%
     Self-Correction: YES/NO
     Deviations: N
     Report: path/to/completion-report.md
     Summary: all deliverables created
     Files Modified: N
     Tests: status
     Key Outputs:
       - path/to/file (created)
       - path/to/other (modified)');
```

**9. Final Complete (TERMINAL WRITE)**

After conductor approves completion, update state to `complete`, set `completed_at` timestamp, and record the completion report path. This is the absolute last database write for this task.

```sql
UPDATE orchestration_tasks
SET state = 'complete', last_heartbeat = datetime('now'),
    completed_at = datetime('now'),
    report_path = 'path/to/completion-report.md'
WHERE task_id = 'task-{NN}';
```

**10. Clean Exit (TERMINAL WRITE)**

If exiting early due to context exhaustion, update state to `exited`, set `last_heartbeat`, and send a handoff message including exit reason, HANDOFF path, context usage, last completed step, and remaining steps.

```sql
INSERT INTO orchestration_messages (task_id, from_session, message_type, message)
VALUES ('task-{NN}', '{session_id}', 'handoff',
    'EXITED: Context exhaustion, clean handoff prepared.
     HANDOFF: temp/task-{NN}-HANDOFF
     Context Usage: XX%
     Last Completed Step: N
     Remaining Steps: list');

UPDATE orchestration_tasks
SET state = 'exited', last_heartbeat = datetime('now')
WHERE task_id = 'task-{NN}';
```

### Terminal Write Atomicity

Terminal state writes (queries 9 and 10) must execute in order: (1) write message to `orchestration_messages` first, (2) then update task state in `orchestration_tasks`. This ensures the message serves as a recovery record if the state update fails. Execute each query separately — comms-link may not support multi-statement transactions.

### Message Format Standards

All musician messages include the message type (`review_request`, `error`, `completion`, etc.), timestamp, context usage percentage, and specific content per type. Messages are inserted into `orchestration_messages` table with the task ID, musician session ID, and message type.

### Parallel Awareness Queries

**11. Check Sibling States (optional)**

Optionally query to see what state other musician tasks are in. This is useful for awareness during parallel execution but not required.

```sql
SELECT task_id, state, last_heartbeat
FROM orchestration_tasks
WHERE task_id != 'task-00' AND task_id != 'task-{NN}'
ORDER BY task_id;
```

**12. Check Conductor Health**

Query the conductor task row (task_id = 'task-00') to check its state and heartbeat staleness.

```sql
SELECT state, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE task_id = 'task-00';
```

## Reference: Subagent Delegation

### Delegation Decision Matrix

Before launching a subagent, evaluate the work against these criteria:

| Criteria | Do It Yourself | Delegate |
|----------|---|---|
| Lines of code | >500 LOC | <500 LOC |
| Scope | Multi-module, cross-cutting | Single file/module, isolated |
| Type | Refactoring, assembly, holistic testing | Individual function, unit test, documentation |
| Dependencies | Touches shared/danger files | Self-contained, no shared state |
| Complexity | Requires session context/history | Single-prompt description sufficient |

**When in doubt, keep it.** Delegation has overhead (launching agent, reading results, integrating). Keep integration work and multi-file refactoring with the musician.

### Subagent Prompt Structure

All subagent prompts follow this template:

```
## Task
[1-3 sentence description of what to implement]

## Context
- Project: [project name] at [path]
- Working branch: [branch name]
- Related files: [list of files to read/modify]
- Testing framework: [framework and run command]

## Requirements
[Extracted from task instructions — the specific steps being delegated]

## Constraints
- Do NOT modify files outside listed scope
- Run tests after implementation
- If tests fail, fix them before returning
- If issues arise outside scope, document and return

## Deliverables
Return summary of:
1. Files created/modified (with paths)
2. Tests added/modified
3. Test results (pass/fail with output)
4. Any issues or scope concerns
```

### Subagent Prompt Rules

1. **Always use `model="opus"`** — Opus is required for subagents to self-test their work. This cannot be changed after launch.
2. **Never paste full task instructions** — Extract only the specific steps being delegated
3. **List specific files** — Don't make the agent search; provide exact file paths
4. **Include test command** — The agent needs to know how to verify its own work
5. **Define scope boundaries explicitly** — State what NOT to touch
6. **Minimize orchestration context** — The agent doesn't need to know about the database, conductor, or watcher pattern

### Handling Subagent Results

When a subagent returns:

1. Read the summary of files modified, tests added, issues encountered
2. Quick verification that claimed deliverables exist
3. **Do NOT run tests yet** — Tests are batched at checkpoints
4. Log to status file: `step N agent M returned [ctx: XX%]`
5. If agent reports scope concerns: assess whether this is a deviation (log to deviations file if Medium or higher severity)
6. If agent failed: decide whether to retry (same prompt), adjust prompt, or do it yourself

### Retry Policy

Maximum 2 retries per subagent task (this is separate from the 5 conductor-level error retries in database-queries):

**Retry 1 (Same Prompt, Fresh Context):**
- Relaunch with identical prompt in a fresh session
- Fresh context often resolves transient issues
- If succeeds: proceed to integration
- If fails: proceed to Retry 2

**Retry 2 (Adjusted Prompt):**
- Analyze the failure and refine the prompt
- Clarify requirements, add context, reduce scope, or provide skeleton code
- Relaunch with adjusted prompt
- If succeeds: proceed to integration
- If fails: proceed to decision below

**After 2 Failures:**
- If work is <500 LOC and well-defined: **Musician absorbs it** (faster than more retries)
- If work is >500 LOC or ambiguous: **Escalate to conductor** (needs different approach or priority decision)
- Never retry more than twice — diminishing returns

**Retry Escalation Flowchart:**

```
Subagent fails
  ├─→ Retry 1: Same prompt, fresh context
  │     ├─ Success → integrate result
  │     └─ Fail ↓
  ├─→ Retry 2: Adjusted prompt (clarify, reduce scope, add skeleton)
  │     ├─ Success → integrate result
  │     └─ Fail ↓
  └─→ Decision:
        ├─ <500 LOC + well-defined → Absorb: musician does it directly
        └─ >500 LOC or ambiguous  → Escalate: message conductor for guidance
```

### Expected Subagent Output

Subagents return natural language summaries (no JSON schema required). Expected content:

- Files modified (with paths)
- Code changes (key snippets or descriptions)
- Tests created and their results
- Issues encountered or scope concerns

The musician is responsible for verifying all claims. Don't just accept the summary — spot-check files, re-run tests at checkpoint, verify coverage. Subagent summaries are a starting point for integration, not a source of truth.

### Subagent Context Budget

Each subagent receives its own context window (not shared with musician). Typical costs:

- Prompt + file reads: ~5-15k tokens
- Implementation: ~10-30k tokens
- Testing: ~5-10k tokens
- Total per subagent: ~20-55k tokens

The musician's cost per subagent is minimal (~1-2k tokens for launch + result reading), which is why delegation preserves musician headroom. Estimate ~8% context cost per subagent when planning how many to launch.

## Reference: Checkpoint Verification Checklist

### Checkpoint Types

**Task Instruction Checkpoints:** Defined in the task instructions, these are scheduled verification points where the musician verifies work and reports to the conductor.

**Context Worry Checkpoints:** Musician-initiated early breaks triggered when context usage makes reaching the next scheduled checkpoint risky. Same verification protocol applies.

### Verification Protocol (Every Checkpoint)

At every checkpoint, execute these steps in order:

**1. Run Tests**
Run the full test suite (or scoped to affected areas). Run unit tests for modified files and integration tests for affected modules.

**2. Test the Tests (Validity Check)**
Verify that new tests can actually fail. Check test assertions aren't trivially true, coverage addresses the code that was modified, and tests pass for the right reasons (not just because everything is mocked away).

**3. Coverage Check**
Run coverage if available. Verify coverage didn't decrease from the start of this checkpoint. New code should have test coverage (no untested new functions).

**4. Self Code Review**
Quick scan of all modified files. Check for debug prints, commented-out code, TODO markers that should be resolved, and naming conventions matching project style.

**5. Integration Check**
Verify changes compile without errors, imports are correct (no cycles), and if multiple agents contributed, outputs integrate cleanly.

### Verification Decision Matrix

| All Tests Pass | Coverage OK | Code Clean | Decision |
|---|---|---|---|
| Yes | Yes | Yes | Report `needs_review` |
| Yes | No (<80%) | Yes | Improve coverage first, then report |
| Yes | No (80-90%) | Yes | Note coverage gap, still report |
| No | — | — | Fix failures first, don't report yet |
| Yes | Yes | No | Clean up, then report |

### Always-Injected Test Validation

Even if task instructions don't mention testing at a checkpoint, the musician ALWAYS:
1. Runs the test suite
2. Verifies new code has tests
3. Validates that tests can fail

This is non-negotiable.

### Test Selection at Checkpoints

When running tests, include tests from these categories:

1. **Unit tests for modified files** — All tests for files created/modified since last checkpoint
2. **Integration tests for affected modules** — Tests for modules containing modified files
3. **Checkpoint-specific tests** — Tests explicitly listed in task instructions
4. **Previously failed tests** — Any test that was fixed during this checkpoint (verify it still passes)

Run categories in order. If any fails, stop and fix before proceeding.

### Subagent Test Validation at Checkpoints

Re-run ALL subagent-reported tests at checkpoint — don't trust reported pass status. Subagents may have stale test state, incomplete runs, or environment differences. At each checkpoint:

1. Re-run every test the subagent claims passed
2. Run musician-level integration tests beyond subagent unit tests
3. Verify subagent test results match reality (same pass count, no new failures)

### Coverage Targets

- **Minimum:** 80% coverage on modified code
- **Target:** 90% coverage
- **Enforcement:** If coverage drops below 80% after checkpoint: Improve before reporting. If coverage drops >5% from baseline but stays >80%: Explain in review why.

### Flaky Test Handling

If a test fails during checkpoint verification:

1. Re-run the same test 3 times
2. If all 3 pass: Test is flaky, mark as such in review message but proceed
3. If all 3 fail: Consistent failure, analyze and fix before reporting
4. If inconsistent (some pass, some fail): Definitively flaky, mark as such and escalate to conductor

Never suppress flaky tests — they're symptoms of real issues (race conditions, timing sensitivity). Document them so the conductor can decide on a permanent fix strategy.

### Test Failure Analysis Decision Tree

When a test fails:

**Step 1: Determine failure type**
- Is the test itself broken? (syntax error, wrong test data)
- OR is the implementation wrong? (code logic failure)
- OR is it environmental? (network, filesystem, timing)

**Step 2: If test is broken**
- Fix the test code
- Re-run to verify pass
- Note in review: "Test bug fixed"

**Step 3: If implementation is wrong**
- Analyze the regression
- Fix the implementation
- Re-run test to verify pass
- Note in review: "Implementation fixed"

**Step 4: If environmental**
- Re-run the suite 3 times
- If consistent: Investigate environment issues
- If inconsistent: Escalate as flaky (see flaky test handling above)

**Step 5: If root cause unclear**
- Increment retry count
- Report to conductor with analysis
- Wait for conductor guidance

## Reference: Resumption State Assessment

### Resumption Decision Tree

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

### HANDOFF Document Structure

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

### State Reconciliation

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

### Verbose Resumption Status

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

### Post-Resumption Verification

ALWAYS re-run verification tests after resuming, even if:
- Conductor approved previous session's work
- HANDOFF indicates all tests passed
- No mismatches were found

This ensures fresh confidence in the current session's state and catches any environment-dependent issues.

## Example: Bootstrap & First Execution

This example walks through a fresh musician session claiming task-03 (parallel phase) and beginning its first step.

### Scenario

The conductor has created task-03 with instructions at `docs/tasks/task-03.md`. The user launches an musician session targeting this task.

### Step 1: SessionStart Hook Fires

The SessionStart hook automatically extracts the session ID and provides it to the musician via the system prompt context: `CLAUDE_SESSION_ID=abc123-def456-789`.

### Step 2: Parse Task Identity

The musician recognizes the standardized launch prompt (skill invocation + embedded SQL query + context block). It extracts `task-03` as the task ID from the context block.

### Step 3: Atomic Task Claim

Execute UPDATE with guard clause. The task is in `watching` state (set by conductor), so guard allows the claim. Result: `rows_affected = 1`. Claim succeeded. Record: `session_id=abc123-def456-789`, `started_at=now`, `worked_by=musician-task-03`.

If `rows_affected = 0`, execute Guard Block Fallback: insert `fallback-abc123-def456-789` with state `exited` and send claim_blocked message.

### Step 4: Read Task Instructions

Run the SQL query from the launch prompt to retrieve the task instruction message (`task_id = 'task-03'`, `message_type = 'instruction'`). Extract the file path `docs/tasks/task-03.md` and read the full task instruction file.

### Step 5: Initialize temp/ Files

Create `temp/task-03-status` with initial bootstrap entries:
- `bootstrap started [ctx: 5%]`
- `task claimed, session: abc123-def456-789 [ctx: 7%]`
- `instructions loaded: docs/tasks/task-03.md [ctx: 12%]`

Create `temp/task-03-deviations` (empty initially).

### Step 6: Launch Background Watcher

Start background message watcher agent using Task tool with `run_in_background=True`. Watcher polls every 15 seconds for new messages from conductor. Musician continues immediately.

### Step 7: Begin First Step

Read Step 1 from task instructions. Evaluate: "Extract 3 testing pattern files from docs2/ to knowledge-base/". Scope is <500 LOC, isolated → delegate to subagent.

Launch subagent with structured prompt including Task, Context, Requirements, Constraints, Deliverables sections. Log: `step 1 agent 1 launched [ctx: 15%]`.

When subagent returns, log: `step 1 agent 1 returned [ctx: 17%]`. Update heartbeat. Do NOT run tests yet (batched at checkpoints).

### Summary

Bootstrap takes ~5 minutes and consumes ~12-15% context. Execution begins in Step 1 after background watcher is launched. The musician is now ready for checkpoint verification when Step 1 completes or when context thresholds are hit.

---

## Example: Subagent Launch & Integration

This example walks through the musician delegating a two-part task and integrating the results.

### Scenario

The musician is at Step 2 of task-03, which involves creating a new knowledge-base file with content synthesized from 2 source documents. The step requires 2 specialized agents: Agent 1 extracts and reformats content from an existing guidelines document, and Agent 2 adds cross-references to 3 related knowledge-base files.

### Step 1: Evaluate Delegation

The musician reads Step 2's requirements:
- Agent 1: Extract and reformat content from `docs2/guidelines/reference/quality-assurance.md` into a new knowledge-base file. ~200 LOC, single file, isolated.
- Agent 2: Add cross-references to 3 existing knowledge-base files. ~50 LOC across 3 files, simple edits.

Both are under 500 LOC, isolated, and self-contained. The musician decides to delegate both.

### Step 2: Launch Agent 1

The musician launches the first subagent with a structured prompt that includes:
- Task description: Extract and reformat the quality assurance guidelines into a knowledge-base file.
- Context: Current project, working branch, source and target file paths.
- Requirements: Extract all actionable patterns, reformat into knowledge-base style with clear headers and code examples, add frontmatter with category and tags.
- Constraints: Don't modify the source file, only create the target file, follow existing knowledge-base file structure.
- Deliverables: Return file created, line count, section headers, and any unclear content.

The musician updates its status log: `step 2 started [ctx: 19%]` and `step 2 agent 1 launched [ctx: 20%]`.

### Step 3: Agent 1 Returns

Agent 1 returns successfully:
- File created: `docs/knowledge-base/implementation/quality-assurance-patterns.md` (287 lines)
- Sections: 8 patterns extracted (error handling, test design, code review, etc.)
- All code examples preserved
- Frontmatter added with tags

The musician logs: `step 2 agent 1 returned [ctx: 22%]`. It does NOT run tests yet (tests are batched at checkpoints).

### Step 4: Integrate Agent 1 Results

The musician:
1. Verifies the file was created and is readable
2. Checks the line count and structure against expectations
3. Updates the task progress record with the file path and status

The musician does not make modifications; Agent 1 handled the full scope. Status update: `step 2 agent 1 integrated [ctx: 23%]`.

### Step 5: Launch Agent 2

The musician now launches the second subagent with a structured prompt for cross-reference work:
- Task description: Add cross-references from the new quality-assurance-patterns file to 3 related knowledge-base files (error-handling-patterns, test-design-patterns, code-review-guidelines).
- Context: Project path, new file location, target files to reference.
- Requirements: Identify logical connection points, add inline references with proper markdown link syntax, ensure bidirectional references where appropriate.
- Constraints: Only modify the 3 target files, don't change the source file, keep edits focused and minimal.
- Deliverables: Return files modified, number of references added, any issues encountered.

The musician logs: `step 2 agent 2 launched [ctx: 24%]`.

### Step 6: Agent 2 Returns

Agent 2 returns successfully:
- Files modified: 3 (error-handling-patterns, test-design-patterns, code-review-guidelines)
- Cross-references added: 7 total (2-3 per file)
- All references use consistent markdown link format
- No conflicts encountered

The musician logs: `step 2 agent 2 returned [ctx: 26%]`.

### Step 7: Integration Assessment

The musician checks:
1. Both agents completed without errors
2. All required deliverables present and valid
3. File structure is consistent with existing knowledge-base patterns
4. No conflicting changes

Assessment: Both agents succeeded, integration is clean. The musician updates its status: `step 2 agents 1-2 integrated successfully [ctx: 27%]`.

### Step 8: Handle Agent Failure (Alternative Path)

If Agent 2 had failed (e.g., conflicting edits or broken links), the musician would:
1. Log the failure: `step 2 agent 2 FAILED — [error reason]`
2. Assess: Is this a retry-able error or structural issue?
3. Retry 1: Adjust the prompt with more specific constraints (e.g., "Avoid editing lines 45-60 due to pending changes")
4. If Retry 1 succeeds, integrate results
5. If Retry 2 fails, escalate to conductor with error details

### Summary

Both subagents completed successfully. The musician went from delegation decision → Launch Agent 1 → Integrate → Launch Agent 2 → Integrate, consuming ~7-8% context. Step 2 is now ready for verification testing at the checkpoint. The musician logs the step completion and moves to the next phase of task execution.

---

## Example: Verification Checkpoint Flow

This example demonstrates the verification checkpoint protocol when the musician reaches a checkpoint with multiple agents' work to validate.

### Scenario

The musician has completed Step 2 (multiple subagents contributed). Task instructions mark this as Checkpoint 1. Context is at 35%.

### Step 1: Reach Checkpoint

Musician has all subagent work integrated locally. Now runs comprehensive verification.

### Step 2: Run Tests

Run unit tests for all files modified in Step 2. Run integration tests for affected modules. Result: All 47 tests passing. 3 new tests added by subagents.

### Step 3: Test the Tests

Verify each new test can fail. Check assertions aren't trivially true (all mocked away). Confirm coverage addresses modified code. Status: All new tests valid.

### Step 4: Coverage Check

Run coverage tool. Result: 85% coverage on modified code (baseline was 82%). Coverage increased → good sign. No untested new functions.

### Step 5: Self Code Review

Scan all modified files. Check for debug prints (found 0), commented code (found 1 block — remove it), TODO markers (found 2 — both addressed in task, OK to leave). Naming conventions match project style.

### Step 6: Integration Check

Verify compilation with no errors. Check imports: no cycles. Multiple subagents' outputs integrate cleanly. No conflicts on shared files.

### Step 7: Prepare Review Request

All checks passed. Prepare review request message:
- Checkpoint: 1 of 4
- Context Usage: 35%
- Self-Correction: YES (removed debug code)
- Deviations: 0
- Agents Remaining: ~8 (@8% each = ~64% total)
- Tests: All 47 passing, 3 new tests
- Proposal: docs/implementation/proposals/testing-patterns-improvement.md
- Key Outputs:
  - docs/implementation/proposals/testing-patterns-improvement.md (created)
  - docs/implementation/proposals/rag-widget-test-isolation.md (rag-addition)

### Step 8: Send Review + Enter Pause Mode

Execute UPDATE: set state='needs_review', send message to orchestration_messages. Terminate background watcher. Exit all active subagents. Launch foreground pause watcher — musician blocks.

### Step 9: Pause Watcher Detects Response

After 2 minutes, conductor reviews and updates state to 'review_approved'. Pause watcher detects the state change and exits.

### Step 10: Process Approval

Musician reads approval message (no required changes). Logs: `checkpoint 1 approved [ctx: 35%]`.

### Step 11: Resume

Launch new background watcher. Resume execution with Step 3.

### Summary

Checkpoint verification takes ~1-2 minutes and consumes ~2-3% context. The musician validates all work before reporting, ensuring only verified code reaches conductor review. If tests had failed, musician would fix and re-submit before reporting.

---

## Example: Conductor Pause & Feedback Cycle

This example walks through the musician receiving rejection feedback from the conductor, applying fixes, and resubmitting.

### Scenario

The musician submitted checkpoint 2 of task-03 to the conductor for review. The conductor evaluated the work and found issues that need to be fixed before approval.

### Step 1: Conductor Rejects Review

The conductor identifies issues with the checkpoint submission:
- Issue 1: A knowledge-base file contains an incorrect cross-reference to a deleted file
- Issue 2: Two test assertions are too broad (testing truthiness rather than specific values)
- Issue 3: Missing coverage for an edge case (empty input to extractContent())

The conductor sets the task state to `review_failed` and sends a detailed rejection message listing all 3 issues and requesting resubmission after fixes.

### Step 2: Pause Watcher Detects Rejection

The pause watcher detects the state change to `review_failed` and exits. The musician detects the exit, reads the rejection message from the database, and processes the full list of issues.

The musician reads the message, launches a new background watcher (maintaining watcher continuity), and updates its status: `review_failed — 3 issues to address [ctx: 55%]`.

### Step 3: Process Feedback

The musician analyzes all 3 issues and decides how to address each:

1. **Incorrect cross-reference** — This is a direct file edit. The musician can fix this directly (~10 LOC, familiar with the file structure from earlier work).
2. **Broad test assertions** — The musician knows the test context and can fix this directly by making assertions check specific values.
3. **Missing edge case coverage** — This requires writing a new unit test. The musician decides to delegate this to a subagent (isolated, focused task).

### Step 4: Apply Direct Fixes

The musician fixes issues 1 and 2 directly:

**Fix 1 — Cross-reference:**
- Read the knowledge-base file (checkpoint-commit-pattern.md)
- Find the incorrect reference (link to deleted file)
- Update the link to point to the correct existing file
- Verify the fix

**Fix 2 — Test assertions:**
- Read the test file (test/knowledge_base_test.dart)
- Find the two assertions flagged as too broad
- Change from checking truthiness to checking specific expected values
- Run tests to verify (both assertions still pass, now with stricter checks)

The musician logs: `fixing: incorrect cross-reference in checkpoint-commit-pattern.md [ctx: 56%]` and then `fixing: narrowing test assertions in test/knowledge_base_test.dart [ctx: 57%]`.

### Step 5: Delegate Edge Case Test

For issue 3, the musician launches a subagent to add the missing edge case test:

The subagent is given:
- Task: Add a unit test for the empty input edge case of extractContent()
- Context: Project path, file to test, test file location, testing framework
- Requirements: Test with empty string input, test with null input if nullable, verify appropriate error handling or empty result
- Constraints: Only modify the test file, run tests to verify
- Deliverables: Tests added, results, coverage delta

The musician logs: `delegating edge case test to agent [ctx: 58%]`.

The subagent returns successfully:
- Tests added: 2 new edge case tests
- Test results: Both tests pass
- Coverage: Confirms empty input is now covered

The musician logs: `edge case test added [ctx: 60%]`.

### Step 6: Re-Run Verification

After all 3 issues are addressed, the musician runs the full test suite:
- All 44 tests pass
- 2 new edge case tests included
- No regressions detected
- Coverage improved

Status update: `all tests passing (44 tests, 2 new) [ctx: 61%]`.

### Step 7: Log Deviation

The feedback cycle represents a deviation from the optimal path (work didn't pass first review). The musician records this in its deviations log:

```
checkpoint 2: review_failed (Smoothness 6/9)
Issues: 3 (cross-ref error, broad assertions, missing edge case)
Resolution: 2 direct fixes, 1 delegated agent
Complexity: Medium (required additional testing work)
```

### Step 8: Re-Submit for Review

The musician prepares a resubmission message that:
1. Acknowledges all 3 issues
2. Describes how each was fixed (2 direct, 1 delegated)
3. Shows test results (all passing)
4. Reports context usage (now at 61%)
5. Notes that this is a retry after rejection

The musician updates the task state to `needs_review`, logs the resubmission, and sends a message to the conductor with all the details of the fixes applied, test results, and file modifications.

Status update: `resubmitting checkpoint 2 after feedback fixes [ctx: 62%]`.

### Step 9: Re-Enter Pause Mode

The musician enters pause mode again to wait for the conductor's response to the resubmission. The pause watcher polls for state changes.

### Step 10: Conductor Approves Resubmission

The conductor reviews the resubmission, confirms all 3 issues are resolved, and approves checkpoint 2. The task state is set to `review_approved` with a message confirming the checkpoint passed.

The pause watcher detects the state change and exits. The musician reads the approval, launches a new background watcher, logs: `checkpoint 2 approved [ctx: 63%]`, and resumes normal execution to move toward checkpoint 3.

### Summary

The musician experienced a rejection-feedback-resubmit cycle:
- Checkpoint 2 initially rejected (Smoothness: 6/9)
- 3 issues identified by conductor
- Musician applied 2 direct fixes + 1 delegated fix
- Re-ran tests (all passing, now 44 + 2 new)
- Resubmitted with detailed explanation
- Conductor approved resubmission
- Context cost: ~6-7% for the iteration
- Learning: The feedback cycle resulted in better test coverage and removed a file reference bug that would have caused problems later

This is a normal part of the musician workflow — work doesn't always pass first review, and the conductor's feedback helps catch issues early.

---

## Example: Context-Tight Break Point Proposal

This example walks through the musician detecting rising context pressure and negotiating with the conductor for scope adjustments.

### Scenario

The musician is at 52% context usage in Step 4 of task-03 (which has 5 steps total). Just completed an agent that consumed more context than expected. Looking ahead at the remaining work, the musician realizes it may not reach the final checkpoint without hitting the 80% context ceiling.

### Step 1: Context Threshold Triggered

System message indicates 52% context usage. This crosses the 50% evaluation threshold. The musician pauses to assess remaining work.

Status update: `step 4 agent 1 returned [ctx: 52%]` and `CONTEXT EVALUATION triggered at 52% [ctx: 52%]`.

### Step 2: Estimate Remaining Work

The musician reviews what's left:
- Step 4: 1 more agent remaining (~4% context)
- Step 5: 3 agents planned (~4% each = ~12% context)
- Checkpoint 3 verification: ~3% context
- **Total estimated remaining: ~19% context**

If all goes as planned: 52% + 19% = 71%. This is feasible but tight.

**However**, the musician notes that during Step 3, Agent 2 had to self-correct (rewrote part of the tokenizer due to a test failure). Self-correction typically costs 5-6x more context than normal execution. If such self-correction happens again in Step 5, the actual cost could be much higher:
- Step 5 agents might cost ~8% each instead of ~4% if self-correction continues
- Worst case: 52% + 4% + 24% + 3% = 83% → **exceeds 80% limit**

### Step 3: Set Error State & Send Context Warning

The musician recognizes the risk and escalates. It updates the task state to `error` and sends a detailed context warning message to the conductor:

```
CONTEXT WARNING: 52% usage
Self-Correction: YES (step 3, agent 2 — test failure in parser, rewrote tokenizer. ~6x context impact)
Agents Remaining: 4 (~4% each nominal, but ~8% each with self-correction risk = ~32% total)
Agents That Fit in 65% Budget: 2 (due to self-correction bloat)
Deviations: 1 (Medium — from checkpoint 2 feedback cycle)
Recommendation: Complete step 4 agent 2 + step 5 agents 1-2, then handoff
Awaiting conductor instructions
```

The musician is now requesting guidance: Can we proceed with reduced scope, or should we escalate differently?

### Step 4: Enter Pause Mode

The musician:
1. Terminates the background watcher
2. Launches a pause watcher
3. Waits for the conductor to respond

The task is now blocked, waiting for the conductor's decision on how to proceed.

### Step 5: Conductor Responds

The conductor reviews the context state and decides to accept the musician's recommendation with a modification. The conductor sets `fix_proposed` state and sends:

```
Context plan accepted with modification:
- Complete step 4 agent 2
- Complete step 5 agents 1 and 2 only
- Skip step 5 agent 3 (documentation — can be done by next session)
- Run checkpoint 3 verification on completed work
- Prepare handoff after checkpoint approval
Total: 3 more agents + checkpoint. Target exit at ~70%.
```

This is a scope reduction: Agent 3 of Step 5 (table of contents generation) is deferred to a future session.

### Step 6: Resume with Reduced Scope

The musician detects the `fix_proposed` message and reads the conductor's instructions:

1. Adjusts internal plan: Instead of 4 agents + checkpoint, now it's 3 agents + checkpoint
2. Launches background watcher again
3. Resumes Step 4 agent 2

Status update: `conductor fix_proposed: reduced scope — skip step 5 agent 3 [ctx: 53%]` and `step 4 agent 2 launched [ctx: 53%]`.

### Step 7: Execute Reduced Scope

The musician continues with the adjusted scope:
- Step 4 agent 2: Completes successfully (~4% cost)
- Step 5 agent 1: Completes successfully (~4% cost)
- Step 5 agent 2: Completes successfully (~4% cost)
- Checkpoint 3 verification: Runs all tests, confirms work is solid (~2% cost)

Context trajectory:
- After Step 4 agent 2: ~57%
- After Step 5 agent 1: ~61%
- After Step 5 agent 2: ~65%
- After checkpoint verification: ~67%

### Step 8: Checkpoint Approved

The musician submits checkpoint 3 for review at 67% context. The conductor approves it quickly (all work is clean, no issues detected).

Status: `checkpoint 3 approved [ctx: 68%]`.

### Step 9: Prepare for Handoff

With 68% context usage and the main work complete (agents 1-2 of Step 5, deferred agent 3), the musician prepares for clean exit and handoff. See the Clean Exit & Handoff example for the final steps.

### Summary

Context pressure escalation workflow:
- Detected rising context at 52%
- Identified self-correction risk (5-6x multiplier)
- Escalated to conductor with detailed analysis
- Received scope reduction approval (skip 1 agent)
- Resumed with reduced scope
- Completed work efficiently (~67% final)
- Prepared for clean handoff to next session

This demonstrates the musician's ability to detect and communicate resource constraints early, negotiate with the conductor, and adapt execution scope to stay within limits. The key insight: Self-correction is expensive, and planning must account for worst-case context costs.

---

## Example: Mid-Session Resumption

This example walks through a second musician session taking over after the first session exited cleanly at context exhaustion.

### Scenario

Session 1 ran task-03 to 72% context, completed the approved scope, and exited cleanly with a HANDOFF document. The conductor set `fix_proposed` state with instructions for the next session. The user launches Session 2.

### Step 1: SessionStart Hook

The SessionStart hook automatically extracts the session ID and injects it into the system prompt: `CLAUDE_SESSION_ID=xyz789-abc012-345`. This becomes available to the musician immediately.

### Step 2: Parse Task Identity

The musician recognizes the standardized launch prompt and extracts: Task ID is `task-03` from the context block. Session role: take over where Session 1 left off.

### Step 3: Atomic Claim

The musician attempts to claim the task. It queries the database for the task record and executes an UPDATE with guard clause:

The task is in `fix_proposed` state (set by conductor after Session 1 exited). The guard clause allows claiming from states: `watching`, `fix_proposed`, or `exit_requested`.

Guard passes. Result: `rows_affected = 1`. Claim succeeded. The musician records: `session_id=xyz789-abc012-345`, `started_at=now`, `worked_by=musician-task-03-S2`.

Note: The `-S2` suffix signals this is a resumed session, not a fresh start.

### Step 4: Read All temp/ Files

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

### Step 5: Read HANDOFF Document

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

### Step 6: Read Conductor Handoff Message

The musician queries the database for the most recent message from the conductor:

```
Session 1 exited cleanly. Resumption instructions:
- Step 5 agent 3 (table of contents) is the only remaining work
- Re-run checkpoint 3 verification to confirm S1's work is intact
- Then complete normally
```

Clear, actionable instructions.

### Step 7: Assess Health

The musician verifies that resumption is safe:

- **HANDOFF exists and is recent** — ✅ Yes, dated 2026-02-07 16:45:00 (today)
- **Deviations count is manageable** — ✅ 2 total (1 Medium, 1 Low) ≤ 2 allowed
- **No temp/comms mismatches** — ✅ Both status file and database are consistent
- **Conductor message is clear** — ✅ Specific instructions provided
- **No evidence of crash or unclean exit** — ✅ HANDOFF is present and structured

Assessment: **Clean handoff. Safe to continue.**

### Step 8: Re-Run Verification Tests

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

### Step 9: Write Verbose Resumption Status

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

### Step 10: Launch Background Watcher & Resume

The musician:
1. Launches a new background watcher (independent of Session 1's watcher, which stopped)
2. Reads the task instructions for step 5 agent 3
3. Launches the agent to generate table of contents and index

Status update: `step 5 agent 3 launched [ctx: 19%]`.

### Step 11: Complete Remaining Work

The musician continues with the HANDOFF instructions:
- Agent 3 returns: Table of contents and index generated (~4% cost)
- Final checkpoint verification: All tests pass, final review submitted
- Conductor approves completion

Final context: ~26% (well within limits for a fresh session).

### Step 12: Log Completion

The musician logs the successful resumption and completion, noting that the task is now fully complete.

### Summary

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

---

## Example: Error Recovery & Retry Logic

This example walks through the musician handling a subagent failure, retrying with adjustments, and deciding when to absorb work directly.

### Scenario

Step 3 Agent 1 of task-05 fails due to an unexpected file format issue. The file contains embedded HTML tables that the markdown processor can't parse.

### Step 1: Agent Fails

The musician launched Agent 1 to extract content from a markdown file. The agent returns with an error:

```
Error: File docs2/guidelines/conductor/process-patterns.md contains embedded HTML tables
that can't be parsed with the expected markdown processor. Unable to extract structured content.
```

Status update: `step 3 agent 1 FAILED: HTML table parsing error [ctx: 34%]`.

### Step 2: Assess & Retry (Attempt 1)

The musician analyzes the failure: This is a resolvable error (the agent wasn't given instructions for handling HTML). The musician adjusts the prompt to explicitly handle HTML tables and retries:

**Retry 1 — Updated prompt includes:**
- Task: Extract process patterns from source file
- **NOTE:** The file contains embedded HTML tables — parse these by reading the raw HTML `<table>` elements and converting to markdown format
- Constraints: When encountering HTML tables, convert to markdown table format

Status: `step 3 agent 1 retry 1 launched [ctx: 35%]`.

### Step 3: Retry 1 Fails

Agent 1 attempts the conversion but encounters a structural issue:

```
Error: HTML tables contain colspan attributes — markdown tables don't support merged cells.
Content would be lost in conversion.
```

Status: `step 3 agent 1 retry 1 FAILED: colspan not supported in markdown [ctx: 37%]`.

The problem is deeper: markdown fundamentally can't represent merged cells. Conversion would lose information.

### Step 4: Assess — Absorb or Retry?

The musician has used 1 of 2 allowed retries. The issue is structural, not a simple prompt adjustment. Options:

**Option A (Retry 2):** Try a different approach — preserve HTML tables as-is instead of converting
**Option B (Absorb):** Do the work directly (read source, manually create output)

The musician tries **Retry 2** with a revised approach:

**Retry 2 — New strategy:**
- For any HTML tables with complex formatting (colspan, rowspan): preserve them as HTML in the output file with a comment `<!-- preserved HTML table -->`
- Convert simple tables to markdown
- This avoids information loss

Status: `step 3 agent 1 retry 2 launched [ctx: 38%]`.

### Step 5: Retry 2 Succeeds (Partial)

Agent 1 returns successfully with a pragmatic solution:

```
Files created: docs/knowledge-base/conductor/process-patterns.md (234 lines)
Note: 2 HTML tables preserved as-is (complex formatting).
      3 simple tables converted to markdown.
```

The extraction is complete. Content is preserved. The approach is reasonable — preserve what needs preserving, convert what can be converted.

However, the musician notes this as a deviation (not the ideal approach, but acceptable):

```
temp/task-05-deviations:
  step 3 agent 1: HTML tables preserved instead of converted (Low — formatting choice, content intact)
```

Status: `step 3 agent 1 succeeded with deviation (2 retries) [ctx: 40%]`.

### Step 6: Alternative Path — Both Retries Fail

If Retry 2 had also failed, the musician would absorb the work:

1. Log: `step 3 agent 1 retry 2 FAILED — absorbing work [ctx: 40%]`
2. Read the source file manually
3. Create the output file directly by hand
4. Log the absorption: `step 3 agent 1 completed by musician (after 2 failed retries) [ctx: 50%]`
5. Note the higher context cost (~10% for direct work vs. ~2-3% for delegated work)

This is expensive but ensures work gets done.

### Step 7: Alternative Path — Unrecoverable Error

If the error were truly unrecoverable (e.g., source file missing, broken dependency), the musician would:

1. Recognize the error as unrecoverable
2. Terminate background watcher
3. Set task state to `error`
4. Record the error with details: "Source file does not exist: docs2/guidelines/conductor/process-patterns.md"
5. Send an error message to the conductor requesting investigation
6. Launch foreground pause watcher — musician blocks waiting for conductor to provide either:
   - A corrected file path
   - Alternative instructions
   - Guidance on skipping this work

Example message to conductor:

```
ERROR (Retry 1/5):
Context Usage: 35%
Self-Correction: NO
Error: Source file does not exist: docs2/guidelines/conductor/process-patterns.md
Report: docs/implementation/reports/task-05-error-retry-1.md
Key Outputs:
  - docs/implementation/reports/task-05-error-retry-1.md (created)
Suggested Investigation: File may have been moved or renamed by parallel task
Awaiting conductor fix proposal
```

The musician then enters pause mode and waits for `fix_proposed` state with instructions.

### Step 8: Recovery Decision Tree

The musician's decision logic for retries:

```
IF agent fails:
  ASSESS error type:
    IF retryable (bad instructions, unexpected format):
      IF retry_count < 2:
        Adjust prompt with new strategy
        Retry agent
        GOTO ASSESS error type
      ELSE:
        Absorb work directly (context cost ~10%)
    ELSE if unrecoverable (missing file, broken dep):
      Log error
      Send to conductor
      Enter pause mode
    ELSE if partially recoverable:
      Accept partial result
      Log as deviation
      Continue
```

### Summary

Error recovery workflow:
- Agent 1 failed on HTML table parsing
- Retry 1: Enhanced prompt with HTML handling → Still failed (structural issue)
- Retry 2: Changed strategy (preserve vs. convert) → Succeeded
- Result: Work completed with acceptable deviation
- Context cost: 6% (3 attempts, context accumulates)

Key principles:
- First retry: Adjust instructions
- Second retry: Change strategy entirely
- Third option: Do work directly
- Unrecoverable errors: Escalate immediately

The musician is pragmatic about retries — it adapts based on failure type and knows when to escalate or absorb work rather than retry endlessly.

---

## Example: Clean Exit & Handoff

This example walks through the musician preparing a clean exit when task work is complete and context is approaching its limit.

### Scenario

The musician has completed all conductor-approved work for task-03. Checkpoint 3 has been approved. The conductor confirmed that the scope reduction was accepted (Step 5 agent 3 was skipped). Context is at 72%, well-managed. Time to exit cleanly and prepare for the next session.

### Step 1: Final Work Complete

The musician confirms that all approved work is done:
- Step 1: Complete ✅
- Step 2: Complete ✅
- Step 3: Complete ✅
- Step 4: Complete ✅
- Step 5: Partial (agents 1-2 done, agent 3 skipped per conductor) ✅
- Checkpoint 3: Approved ✅

Status: `checkpoint 3 approved [ctx: 69%]`.

### Step 2: Prepare for Exit

Before setting terminal state, the musician must:
1. Ensure all background agents are stopped
2. Create a handoff document for the next session
3. Write a completion report
4. Update temp/ files
5. Send final message to conductor
6. ONLY THEN set task state to `exited`

### Step 3: Exit All Active Subagents

The musician verifies no subagents are still running:
- Background watcher: Terminate using TaskStop
- No delegated agents are pending (all have returned or been deferred)
- No active processes

All clean.

### Step 4: Create HANDOFF Document

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

### Step 5: Write Completion Report

The musician writes a detailed summary report to `docs/implementation/reports/task-03-handoff-s1.md` containing:
- Deliverables list (files created/modified, line counts)
- Test status (all tests passing, count of tests)
- Deviations encountered (2: 1 Medium, 1 Low)
- Self-correction details (step 3 agent 2)
- Remaining work (step 5 agent 3)
- Recommendations for next session

Status: `completion report written [ctx: 71%]`.

### Step 6: Update temp/status

The musician appends final status entries to `temp/task-03-status`:

```
HANDOFF written: temp/task-03-HANDOFF [ctx: 71%]
report written: docs/implementation/reports/task-03-handoff-s1.md [ctx: 72%]
clean exit preparing [ctx: 72%]
```

This creates a continuous log of the session's work from bootstrap through exit.

### Step 7: Write Final Message to Conductor

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

### Step 8: Set Terminal State (LAST STEP)

The musician performs one final database operation to set the task state to `exited`:

```
UPDATE orchestration_tasks
SET state = 'exited', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';
```

**This is the absolute last database write.** After this, the musician must not access the database. The Stop hook monitors this `exited` state and allows the session to terminate cleanly.

### What Happens Next

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

### Summary

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

---

## Script: validate-musician-state.sh

```bash
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
```

---

## Script: verify-temp-files.sh

```bash
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
```

---

## Script: check-context-headroom.sh

```bash
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
```

---

## Document History

- **2026-02-08:** Initial design document created (Phase 1-3, references, examples, scripts)
- **2026-02-11:** Comprehensive rewrite — synchronized all content with live skill,
  fixed 6 contradictions, added 11 missing features, added Design Rationale section
