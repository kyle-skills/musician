<skill name="musician-example-checkpoint-flow" version="2.0">

<metadata>
type: example
parent-skill: musician
tier: 3
</metadata>

<sections>
- scenario
- verification-steps
- review-and-pause
- approval-and-resume
- summary
</sections>

<section id="scenario">
<context>
# Example: Verification Checkpoint Flow

This example demonstrates the verification checkpoint protocol when the musician reaches a checkpoint with multiple agents' work to validate.

## Scenario

The musician has completed Step 2 (multiple subagents contributed). Task instructions mark this as Checkpoint 1. Context is at 35%.
</context>
</section>

<section id="verification-steps">
<core>
## Step 1: Reach Checkpoint

Musician has all subagent work integrated locally. Now runs comprehensive verification.

## Step 2: Run Tests

Run unit tests for all files modified in Step 2. Run integration tests for affected modules. Result: All 47 tests passing. 3 new tests added by subagents.

## Step 3: Test the Tests

Verify each new test can fail. Check assertions aren't trivially true (all mocked away). Confirm coverage addresses modified code. Status: All new tests valid.

## Step 4: Coverage Check

Run coverage tool. Result: 85% coverage on modified code (baseline was 82%). Coverage increased → good sign. No untested new functions.

## Step 5: Self Code Review

Scan all modified files. Check for debug prints (found 0), commented code (found 1 block — remove it), TODO markers (found 2 — both addressed in task, OK to leave). Naming conventions match project style.

## Step 6: Integration Check

Verify compilation with no errors. Check imports: no cycles. Multiple subagents' outputs integrate cleanly. No conflicts on shared files.
</core>
</section>

<section id="review-and-pause">
<core>
## Step 7: Prepare Review Request

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

## Step 8: Send Review + Enter Pause Mode

Execute UPDATE: set state='needs_review', send message to orchestration_messages. Terminate background watcher. Exit all active subagents. Launch foreground pause watcher — musician blocks.
</core>
</section>

<section id="approval-and-resume">
<core>
## Step 9: Pause Watcher Detects Response

After 2 minutes, conductor reviews and updates state to 'review_approved'. Pause watcher detects the state change and exits.

## Step 10: Process Approval

Musician reads approval message (no required changes). Logs: `checkpoint 1 approved [ctx: 35%]`.

## Step 11: Resume

Launch new background watcher. Resume execution with Step 3.
</core>
</section>

<section id="summary">
<context>
## Summary

Checkpoint verification takes ~1-2 minutes and consumes ~2-3% context. The musician validates all work before reporting, ensuring only verified code reaches conductor review. If tests had failed, musician would fix and re-submit before reporting.
</context>
</section>

</skill>
