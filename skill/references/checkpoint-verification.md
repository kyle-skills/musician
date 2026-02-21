<skill name="musician-checkpoint-verification" version="2.0">

<metadata>
type: reference
parent-skill: musician
tier: 3
</metadata>

<sections>
- checkpoint-types
- context-thresholds
- verification-protocol
- verification-decision-matrix
- always-injected-test-validation
- test-selection-at-checkpoints
- flaky-test-handling
- test-failure-analysis-decision-tree
- subagent-test-validation-at-checkpoints
- coverage-targets
</sections>

<section id="checkpoint-types">
<core>
# Reference: Checkpoint Verification Checklist

## Checkpoint Types

**Task Instruction Checkpoints:** Defined in the task instructions, these are scheduled verification points where the musician verifies work and reports to the conductor.

**Context Worry Checkpoints:** Musician-initiated early breaks triggered when context usage makes reaching the next scheduled checkpoint risky. Same verification protocol applies.
</core>
</section>

<section id="context-thresholds">
<mandatory>
## Context Monitoring Thresholds

Context monitoring is non-negotiable. Check context usage on every system message response.

| Threshold | Action |
|-----------|--------|
| **Always** | Check context usage on every system message response. Log to `temp/task-XX-status`. |
| **>50%** | Estimate context cost before every file read. Include estimate in status log. No speculative reads. |
| **65%** | Prepare handoff: write HANDOFF doc, update temp/ status, finish current step only, no new work steps. |
| **75%** | Mandatory exit. Stop all work immediately. Complete HANDOFF, set state to `exited`. |

80% is NOT "20% remaining" — it is the danger zone for logic poisoning. Hallucinations increase, instruction adherence drops, and partial work is worse than no work. Sessions are cheap to restart; context exhaustion can lock up an entire project.

If both a context threshold and a task instruction checkpoint trigger simultaneously, context check takes priority. Context exhaustion leads to `exited` state (clean handoff), not `error`.
</mandatory>
</section>

<section id="verification-protocol">
<core>
## Verification Protocol (Every Checkpoint)

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
</core>
</section>

<section id="verification-decision-matrix">
<core>
## Verification Decision Matrix

| All Tests Pass | Coverage OK | Code Clean | Decision |
|---|---|---|---|
| Yes | Yes | Yes | Report `needs_review` |
| Yes | No (<80%) | Yes | Improve coverage first, then report |
| Yes | No (80-90%) | Yes | Note coverage gap, still report |
| No | — | — | Fix failures first, don't report yet |
| Yes | Yes | No | Clean up, then report |
</core>
</section>

<section id="always-injected-test-validation">
<mandatory>
## Always-Injected Test Validation

Even if task instructions don't mention testing at a checkpoint, the musician ALWAYS:
1. Runs the test suite
2. Verifies new code has tests
3. Validates that tests can fail

This is non-negotiable.
</mandatory>
</section>

<section id="test-selection-at-checkpoints">
<core>
## Test Selection at Checkpoints

When running tests, include tests from these categories:

1. **Unit tests for modified files** — All tests for files created/modified since last checkpoint
2. **Integration tests for affected modules** — Tests for modules containing modified files
3. **Checkpoint-specific tests** — Tests explicitly listed in task instructions
4. **Previously failed tests** — Any test that was fixed during this checkpoint (verify it still passes)

Run categories in order. If any fails, stop and fix before proceeding.
</core>
</section>

<section id="flaky-test-handling">
<core>
## Flaky Test Handling

If a test fails during checkpoint verification:

1. Re-run the same test 3 times
2. If all 3 pass: Test is flaky, mark as such in review message but proceed
3. If all 3 fail: Consistent failure, analyze and fix before reporting
4. If inconsistent (some pass, some fail): Definitively flaky, mark as such and escalate to conductor
</core>

<mandatory>
Never suppress flaky tests — they're symptoms of real issues (race conditions, timing sensitivity). Document them so the conductor can decide on a permanent fix strategy.
</mandatory>
</section>

<section id="test-failure-analysis-decision-tree">
<core>
## Test Failure Analysis Decision Tree

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
</core>
</section>

<section id="subagent-test-validation-at-checkpoints">
<mandatory>
## Subagent Test Validation at Checkpoints

Re-run ALL subagent-reported tests at checkpoint — don't trust reported pass status. Subagents may have stale test state, incomplete runs, or environment differences. At each checkpoint:

1. Re-run every test the subagent claims passed
2. Run musician-level integration tests beyond subagent unit tests
3. Verify subagent test results match reality (same pass count, no new failures)
</mandatory>
</section>

<section id="coverage-targets">
<core>
## Coverage Targets

- **Minimum:** 80% coverage on modified code
- **Target:** 90% coverage
- **Enforcement:** If coverage drops below 80% after checkpoint: Improve before reporting. If coverage drops >5% from baseline but stays >80%: Explain in review why.
</core>
</section>

</skill>
