<skill name="musician-example-context-break-point" version="2.0">

<metadata>
type: example
parent-skill: musician
tier: 3
</metadata>

<sections>
- scenario
- context-threshold-and-estimation
- escalation-to-conductor
- conductor-response
- reduced-scope-execution
- summary
</sections>

<section id="scenario">
<context>
# Example: Context-Tight Break Point Proposal

This example walks through the musician detecting rising context pressure and negotiating with the conductor for scope adjustments.

## Scenario

The musician is at 52% context usage in Step 4 of task-03 (which has 5 steps total). Just completed an agent that consumed more context than expected. Looking ahead at the remaining work, the musician realizes it may not reach the final checkpoint without hitting the 80% context ceiling.
</context>
</section>

<section id="context-threshold-and-estimation">
<core>
## Step 1: Context Threshold Triggered

System message indicates 52% context usage. This crosses the 50% evaluation threshold. The musician pauses to assess remaining work.

Status update: `step 4 agent 1 returned [ctx: 52%]` and `CONTEXT EVALUATION triggered at 52% [ctx: 52%]`.

## Step 2: Estimate Remaining Work

The musician reviews what's left:
- Step 4: 1 more agent remaining (~4% context)
- Step 5: 3 agents planned (~4% each = ~12% context)
- Checkpoint 3 verification: ~3% context
- **Total estimated remaining: ~19% context**

If all goes as planned: 52% + 19% = 71%. This is feasible but tight.

**However**, the musician notes that during Step 3, Agent 2 had to self-correct (rewrote part of the tokenizer due to a test failure). Self-correction typically costs 5-6x more context than normal execution. If such self-correction happens again in Step 5, the actual cost could be much higher:
- Step 5 agents might cost ~8% each instead of ~4% if self-correction continues
- Worst case: 52% + 4% + 24% + 3% = 83% → **exceeds 80% limit**
</core>
</section>

<section id="escalation-to-conductor">
<core>
## Step 3: Set Error State & Send Context Warning

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

## Step 4: Enter Pause Mode

The musician:
1. Terminates the background watcher
2. Launches a pause watcher
3. Waits for the conductor to respond

The task is now blocked, waiting for the conductor's decision on how to proceed.
</core>
</section>

<section id="conductor-response">
<core>
## Step 5: Conductor Responds

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

## Step 6: Resume with Reduced Scope

The musician detects the `fix_proposed` message and reads the conductor's instructions:

1. Adjusts internal plan: Instead of 4 agents + checkpoint, now it's 3 agents + checkpoint
2. Launches background watcher again
3. Resumes Step 4 agent 2

Status update: `conductor fix_proposed: reduced scope — skip step 5 agent 3 [ctx: 53%]` and `step 4 agent 2 launched [ctx: 53%]`.
</core>
</section>

<section id="reduced-scope-execution">
<core>
## Step 7: Execute Reduced Scope

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

## Step 8: Checkpoint Approved

The musician submits checkpoint 3 for review at 67% context. The conductor approves it quickly (all work is clean, no issues detected).

Status: `checkpoint 3 approved [ctx: 68%]`.

## Step 9: Prepare for Handoff

With 68% context usage and the main work complete (agents 1-2 of Step 5, deferred agent 3), the musician prepares for clean exit and handoff. See the Clean Exit & Handoff example for the final steps.
</core>
</section>

<section id="summary">
<context>
## Summary

Context pressure escalation workflow:
- Detected rising context at 52%
- Identified self-correction risk (5-6x multiplier)
- Escalated to conductor with detailed analysis
- Received scope reduction approval (skip 1 agent)
- Resumed with reduced scope
- Completed work efficiently (~67% final)
- Prepared for clean handoff to next session

This demonstrates the musician's ability to detect and communicate resource constraints early, negotiate with the conductor, and adapt execution scope to stay within limits. The key insight: Self-correction is expensive, and planning must account for worst-case context costs.
</context>
</section>

</skill>
