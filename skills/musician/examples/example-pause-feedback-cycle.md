<skill name="musician-example-pause-feedback-cycle" version="2.0">

<metadata>
type: example
parent-skill: musician
tier: 3
</metadata>

<sections>
- scenario
- conductor-rejects-review
- pause-watcher-detects-rejection
- process-feedback
- apply-direct-fixes
- delegate-edge-case-test
- re-run-verification
- log-deviation
- re-submit-for-review
- re-enter-pause-mode
- conductor-approves-resubmission
- summary
</sections>

<section id="scenario">
<context>
# Example: Conductor Pause & Feedback Cycle

This example walks through the musician receiving rejection feedback from the conductor, applying fixes, and resubmitting.

## Scenario

The musician submitted checkpoint 2 of task-03 to the conductor for review. The conductor evaluated the work and found issues that need to be fixed before approval.
</context>
</section>

<section id="conductor-rejects-review">
<core>
## Step 1: Conductor Rejects Review

The conductor identifies issues with the checkpoint submission:
- Issue 1: A knowledge-base file contains an incorrect cross-reference to a deleted file
- Issue 2: Two test assertions are too broad (testing truthiness rather than specific values)
- Issue 3: Missing coverage for an edge case (empty input to extractContent())

The conductor sets the task state to `review_failed` and sends a detailed rejection message listing all 3 issues and requesting resubmission after fixes.
</core>
</section>

<section id="pause-watcher-detects-rejection">
<core>
## Step 2: Pause Watcher Detects Rejection

The pause watcher detects the state change to `review_failed` and exits. The musician detects the exit, reads the rejection message from the database, and processes the full list of issues.

The musician reads the message, launches a new background watcher (maintaining watcher continuity), and updates its status: `review_failed — 3 issues to address [ctx: 55%]`.
</core>
</section>

<section id="process-feedback">
<core>
## Step 3: Process Feedback

The musician analyzes all 3 issues and decides how to address each:

1. **Incorrect cross-reference** — This is a direct file edit. The musician can fix this directly (~10 LOC, familiar with the file structure from earlier work).
2. **Broad test assertions** — The musician knows the test context and can fix this directly by making assertions check specific values.
3. **Missing edge case coverage** — This requires writing a new unit test. The musician decides to delegate this to a subagent (isolated, focused task).
</core>
</section>

<section id="apply-direct-fixes">
<core>
## Step 4: Apply Direct Fixes

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
</core>
</section>

<section id="delegate-edge-case-test">
<core>
## Step 5: Delegate Edge Case Test

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
</core>
</section>

<section id="re-run-verification">
<core>
## Step 6: Re-Run Verification

After all 3 issues are addressed, the musician runs the full test suite:
- All 44 tests pass
- 2 new edge case tests included
- No regressions detected
- Coverage improved

Status update: `all tests passing (44 tests, 2 new) [ctx: 61%]`.
</core>
</section>

<section id="log-deviation">
<core>
## Step 7: Log Deviation

The feedback cycle represents a deviation from the optimal path (work didn't pass first review). The musician records this in its deviations log:

```
checkpoint 2: review_failed (Smoothness 6/9)
Issues: 3 (cross-ref error, broad assertions, missing edge case)
Resolution: 2 direct fixes, 1 delegated agent
Complexity: Medium (required additional testing work)
```
</core>
</section>

<section id="re-submit-for-review">
<core>
## Step 8: Re-Submit for Review

The musician prepares a resubmission message that:
1. Acknowledges all 3 issues
2. Describes how each was fixed (2 direct, 1 delegated)
3. Shows test results (all passing)
4. Reports context usage (now at 61%)
5. Notes that this is a retry after rejection

The musician updates the task state to `needs_review`, logs the resubmission, and sends a message to the conductor with all the details of the fixes applied, test results, and file modifications.

Status update: `resubmitting checkpoint 2 after feedback fixes [ctx: 62%]`.
</core>
</section>

<section id="re-enter-pause-mode">
<core>
## Step 9: Re-Enter Pause Mode

The musician enters pause mode again to wait for the conductor's response to the resubmission. The pause watcher polls for state changes.
</core>
</section>

<section id="conductor-approves-resubmission">
<core>
## Step 10: Conductor Approves Resubmission

The conductor reviews the resubmission, confirms all 3 issues are resolved, and approves checkpoint 2. The task state is set to `review_approved` with a message confirming the checkpoint passed.

The pause watcher detects the state change and exits. The musician reads the approval, launches a new background watcher, logs: `checkpoint 2 approved [ctx: 63%]`, and resumes normal execution to move toward checkpoint 3.
</core>
</section>

<section id="summary">
<context>
## Summary

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
</context>
</section>

</skill>
