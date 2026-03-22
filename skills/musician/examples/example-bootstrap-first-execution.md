<skill name="musician-example-bootstrap-first-execution" version="2.0">

<metadata>
type: example
parent-skill: musician
tier: 3
</metadata>

<sections>
- scenario
- bootstrap-steps
- first-execution-step
- summary
</sections>

<section id="scenario">
<context>
# Example: Bootstrap & First Execution

This example walks through a fresh musician session claiming task-03 (parallel phase) and beginning its first step.

## Scenario

The conductor has created task-03 with instructions at `docs/tasks/task-03.md`. The user launches a musician session targeting this task.
</context>
</section>

<section id="bootstrap-steps">
<core>
## Step 1: SessionStart Hook Fires

The SessionStart hook automatically extracts the session ID and provides it to the musician via the system prompt context: `CLAUDE_SESSION_ID=abc123-def456-789`.

## Step 2: Parse Task Identity

The musician recognizes the standardized launch prompt (skill invocation + embedded SQL query + context block). It extracts `task-03` as the task ID from the context block.

## Step 3: Atomic Task Claim

Execute UPDATE with guard clause. The task is in `watching` state (set by conductor), so guard allows the claim. Result: `rows_affected = 1`. Claim succeeded. Record: `session_id=abc123-def456-789`, `started_at=now`, `worked_by=musician-task-03`.

If `rows_affected = 0`, execute Guard Block Fallback: insert `fallback-abc123-def456-789` with state `exited` and send claim_blocked message.

## Step 4: Read Task Instructions

Run the SQL query from the launch prompt to retrieve the task instruction message (`task_id = 'task-03'`, `message_type = 'instruction'`). Extract the file path `docs/tasks/task-03.md` and read the full task instruction file.

## Step 5: Initialize temp/ Files

Create `temp/task-03-status` with initial bootstrap entries:
- `bootstrap started [ctx: 5%]`
- `task claimed, session: abc123-def456-789 [ctx: 7%]`
- `instructions loaded: docs/tasks/task-03.md [ctx: 12%]`

Create `temp/task-03-deviations` (empty initially).

## Step 6: Launch Background Watcher

Start background message watcher using `Task(subagent_type="general-purpose", run_in_background=True)`. The watcher must be a general-purpose agent (not Bash) because it needs comms-link MCP to query the orchestration database. Watcher polls every 15 seconds for new messages from conductor. Musician continues immediately.
</core>
</section>

<section id="first-execution-step">
<core>
## Step 7: Begin First Step

Read Step 1 from task instructions. Evaluate: "Extract 3 testing pattern files from docs2/ to knowledge-base/". Scope is <500 LOC, isolated → delegate to subagent.

Launch subagent with structured prompt including Task, Context, Requirements, Constraints, Deliverables sections. Log: `step 1 agent 1 launched [ctx: 15%]`.

When subagent returns, log: `step 1 agent 1 returned [ctx: 17%]`. Update heartbeat. Do NOT run tests yet (batched at checkpoints).
</core>
</section>

<section id="summary">
<context>
## Summary

Bootstrap takes ~5 minutes and consumes ~12-15% context. Execution begins in Step 1 after background watcher is launched. The musician is now ready for checkpoint verification when Step 1 completes or when context thresholds are hit.
</context>
</section>

</skill>
