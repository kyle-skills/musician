<skill name="musician-example-error-recovery" version="2.0">

<metadata>
type: example
parent-skill: musician
tier: 3
</metadata>

<sections>
- scenario
- agent-fails
- assess-and-retry-attempt-1
- retry-1-fails
- assess-absorb-or-retry
- retry-2-succeeds-partial
- alternative-path-both-retries-fail
- alternative-path-unrecoverable-error
- recovery-decision-tree
- summary
</sections>

<section id="scenario">
<context>
# Example: Error Recovery & Retry Logic

This example walks through the musician handling a subagent failure, retrying with adjustments, and deciding when to absorb work directly.

## Scenario

Step 3 Agent 1 of task-05 fails due to an unexpected file format issue. The file contains embedded HTML tables that the markdown processor can't parse.
</context>
</section>

<section id="agent-fails">
<core>
## Step 1: Agent Fails

The musician launched Agent 1 to extract content from a markdown file. The agent returns with an error:

```
Error: File docs2/guidelines/conductor/process-patterns.md contains embedded HTML tables
that can't be parsed with the expected markdown processor. Unable to extract structured content.
```

Status update: `step 3 agent 1 FAILED: HTML table parsing error [ctx: 34%]`.
</core>
</section>

<section id="assess-and-retry-attempt-1">
<core>
## Step 2: Assess & Retry (Attempt 1)

The musician analyzes the failure: This is a resolvable error (the agent wasn't given instructions for handling HTML). The musician adjusts the prompt to explicitly handle HTML tables and retries:

**Retry 1 — Updated prompt includes:**
- Task: Extract process patterns from source file
- **NOTE:** The file contains embedded HTML tables — parse these by reading the raw HTML `<table>` elements and converting to markdown format
- Constraints: When encountering HTML tables, convert to markdown table format

Status: `step 3 agent 1 retry 1 launched [ctx: 35%]`.
</core>
</section>

<section id="retry-1-fails">
<core>
## Step 3: Retry 1 Fails

Agent 1 attempts the conversion but encounters a structural issue:

```
Error: HTML tables contain colspan attributes — markdown tables don't support merged cells.
Content would be lost in conversion.
```

Status: `step 3 agent 1 retry 1 FAILED: colspan not supported in markdown [ctx: 37%]`.

The problem is deeper: markdown fundamentally can't represent merged cells. Conversion would lose information.
</core>
</section>

<section id="assess-absorb-or-retry">
<core>
## Step 4: Assess — Absorb or Retry?

The musician has used 1 of 2 allowed retries. The issue is structural, not a simple prompt adjustment. Options:

**Option A (Retry 2):** Try a different approach — preserve HTML tables as-is instead of converting
**Option B (Absorb):** Do the work directly (read source, manually create output)

The musician tries **Retry 2** with a revised approach:

**Retry 2 — New strategy:**
- For any HTML tables with complex formatting (colspan, rowspan): preserve them as HTML in the output file with a comment `<!-- preserved HTML table -->`
- Convert simple tables to markdown
- This avoids information loss

Status: `step 3 agent 1 retry 2 launched [ctx: 38%]`.
</core>
</section>

<section id="retry-2-succeeds-partial">
<core>
## Step 5: Retry 2 Succeeds (Partial)

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
</core>
</section>

<section id="alternative-path-both-retries-fail">
<core>
## Step 6: Alternative Path — Both Retries Fail

If Retry 2 had also failed, the musician would absorb the work:

1. Log: `step 3 agent 1 retry 2 FAILED — absorbing work [ctx: 40%]`
2. Read the source file manually
3. Create the output file directly by hand
4. Log the absorption: `step 3 agent 1 completed by musician (after 2 failed retries) [ctx: 50%]`
5. Note the higher context cost (~10% for direct work vs. ~2-3% for delegated work)

This is expensive but ensures work gets done.
</core>
</section>

<section id="alternative-path-unrecoverable-error">
<core>
## Step 7: Alternative Path — Unrecoverable Error

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
</core>
</section>

<section id="recovery-decision-tree">
<core>
## Step 8: Recovery Decision Tree

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
</core>
</section>

<section id="summary">
<context>
## Summary

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
</context>
</section>

</skill>
