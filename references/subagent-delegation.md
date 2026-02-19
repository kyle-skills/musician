<skill name="musician-subagent-delegation" version="2.0">

<metadata>
type: reference
parent-skill: musician
tier: 3
</metadata>

<sections>
- delegation-decision-matrix
- subagent-prompt-structure
- subagent-prompt-rules
- handling-subagent-results
- retry-policy
- expected-subagent-output
- subagent-context-budget
</sections>

<section id="delegation-decision-matrix">
<core>
# Reference: Subagent Delegation

## Delegation Model — Default to Delegation

The musician defaults to delegating work. The question is not "should I delegate?" but "which delegation mode?"

**Threshold:** 30k+ tokens estimated context cost → delegate.

**Mode 1: Task() for one-shot work**
- Single-file creation/modification
- Isolated, self-contained work units
- Agent can invoke skills (TDD, subagent-driven-development)
- Musician reviews output thoroughly before integration

**Mode 2: Teams for complex delegation**
- Multi-step delegations that benefit from teammate coordination
- Musician creates team, spawns named teammates
- Teammates work independently with full skill access
- Teammates report back via SendMessage
- Musician reviews ALL teammate output before accepting

**Mode choice:** Simple (one step, one file) → Task(). Complex (multiple steps, own TDD cycle) → Teams.

**Musician keeps:** Integration work, cross-file assembly, holistic testing, and anything requiring full session history.
</core>

<mandatory>
Musician ALWAYS thoroughly reviews delegated work, regardless of delegation mode. Review budget: ~2x the delegation cost. If self-review finds issues beyond simple one-line edits, the fix MUST go to a fresh agent/teammate — Opus in the same context can enter tunnel vision chasing its own errors.
</mandatory>
</section>

<section id="subagent-prompt-structure">
<core>
## Subagent Prompt Structure

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
</core>
</section>

<section id="subagent-prompt-rules">
<mandatory>
## Subagent Prompt Rules

1. **Always use `model="opus"`** — Opus is required for subagents to self-test their work. This cannot be changed after launch.
2. **Never paste full task instructions** — Extract only the specific steps being delegated
3. **List specific files** — Don't make the agent search; provide exact file paths
4. **Include test command** — The agent needs to know how to verify its own work
5. **Define scope boundaries explicitly** — State what NOT to touch
6. **Minimize orchestration context** — The agent doesn't need to know about the database, conductor, or watcher pattern
</mandatory>
</section>

<section id="handling-subagent-results">
<core>
## Handling Subagent Results

When a subagent returns:

1. Read the summary of files modified, tests added, issues encountered
2. Quick verification that claimed deliverables exist
3. **Do NOT run tests yet** — Tests are batched at checkpoints
4. Log to status file: `step N agent M returned [ctx: XX%]`
5. If agent reports scope concerns: assess whether this is a deviation (log to deviations file if Medium or higher severity)
6. If agent failed: decide whether to retry (same prompt), adjust prompt, or do it yourself
</core>
</section>

<section id="retry-policy">
<core>
## Retry Policy

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
- If work is small and well-defined (Task()-scope): **Musician absorbs it** (faster than more retries)
- If work is complex or ambiguous (Teams-scope): **Escalate to conductor** (needs different approach or priority decision)
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
        ├─ Small + well-defined (Task()-scope) → Absorb: musician does it directly
        └─ Complex or ambiguous (Teams-scope) → Escalate: message conductor for guidance
```
</core>
</section>

<section id="expected-subagent-output">
<core>
## Expected Subagent Output

Subagents return natural language summaries (no JSON schema required). Expected content:

- Files modified (with paths)
- Code changes (key snippets or descriptions)
- Tests created and their results
- Issues encountered or scope concerns
</core>

<mandatory>
The musician is responsible for verifying all claims. Don't just accept the summary — spot-check files, re-run tests at checkpoint, verify coverage. Subagent summaries are a starting point for integration, not a source of truth.
</mandatory>
</section>

<section id="subagent-context-budget">
<context>
## Subagent Context Budget

Each subagent receives its own context window (not shared with musician). Typical costs:

- Prompt + file reads: ~5-15k tokens
- Implementation: ~10-30k tokens
- Testing: ~5-10k tokens
- Total per subagent: ~20-55k tokens

The musician's cost per subagent is minimal (~1-2k tokens for launch + result reading), which is why delegation preserves musician headroom. Estimate ~8% context cost per subagent when planning how many to launch.
</context>
</section>

</skill>
