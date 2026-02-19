<skill name="musician-example-subagent-launch" version="2.0">

<metadata>
type: example
parent-skill: musician
tier: 3
</metadata>

<sections>
- scenario
- evaluate-delegation
- launch-agent-1
- agent-1-returns
- integrate-agent-1-results
- launch-agent-2
- agent-2-returns
- integration-assessment
- handle-agent-failure-alternative-path
- summary
</sections>

<section id="scenario">
<context>
# Example: Subagent Launch & Integration

This example walks through the musician delegating a two-part task and integrating the results.

## Scenario

The musician is at Step 2 of task-03, which involves creating a new knowledge-base file with content synthesized from 2 source documents. The step requires 2 specialized agents: Agent 1 extracts and reformats content from an existing guidelines document, and Agent 2 adds cross-references to 3 related knowledge-base files.
</context>
</section>

<section id="evaluate-delegation">
<core>
## Step 1: Evaluate Delegation

The musician reads Step 2's requirements:
- Agent 1: Extract and reformat content from `docs2/guidelines/reference/quality-assurance.md` into a new knowledge-base file. ~200 LOC, single file, isolated.
- Agent 2: Add cross-references to 3 existing knowledge-base files. ~50 LOC across 3 files, simple edits.

Both are under 500 LOC, isolated, and self-contained. The musician decides to delegate both.
</core>
</section>

<section id="launch-agent-1">
<core>
## Step 2: Launch Agent 1

The musician launches the first subagent with a structured prompt that includes:
- Task description: Extract and reformat the quality assurance guidelines into a knowledge-base file.
- Context: Current project, working branch, source and target file paths.
- Requirements: Extract all actionable patterns, reformat into knowledge-base style with clear headers and code examples, add frontmatter with category and tags.
- Constraints: Don't modify the source file, only create the target file, follow existing knowledge-base file structure.
- Deliverables: Return file created, line count, section headers, and any unclear content.

The musician updates its status log: `step 2 started [ctx: 19%]` and `step 2 agent 1 launched [ctx: 20%]`.
</core>
</section>

<section id="agent-1-returns">
<core>
## Step 3: Agent 1 Returns

Agent 1 returns successfully:
- File created: `docs/knowledge-base/implementation/quality-assurance-patterns.md` (287 lines)
- Sections: 8 patterns extracted (error handling, test design, code review, etc.)
- All code examples preserved
- Frontmatter added with tags

The musician logs: `step 2 agent 1 returned [ctx: 22%]`. It does NOT run tests yet (tests are batched at checkpoints).
</core>
</section>

<section id="integrate-agent-1-results">
<core>
## Step 4: Integrate Agent 1 Results

The musician:
1. Verifies the file was created and is readable
2. Checks the line count and structure against expectations
3. Updates the task progress record with the file path and status

The musician does not make modifications; Agent 1 handled the full scope. Status update: `step 2 agent 1 integrated [ctx: 23%]`.
</core>
</section>

<section id="launch-agent-2">
<core>
## Step 5: Launch Agent 2

The musician now launches the second subagent with a structured prompt for cross-reference work:
- Task description: Add cross-references from the new quality-assurance-patterns file to 3 related knowledge-base files (error-handling-patterns, test-design-patterns, code-review-guidelines).
- Context: Project path, new file location, target files to reference.
- Requirements: Identify logical connection points, add inline references with proper markdown link syntax, ensure bidirectional references where appropriate.
- Constraints: Only modify the 3 target files, don't change the source file, keep edits focused and minimal.
- Deliverables: Return files modified, number of references added, any issues encountered.

The musician logs: `step 2 agent 2 launched [ctx: 24%]`.
</core>
</section>

<section id="agent-2-returns">
<core>
## Step 6: Agent 2 Returns

Agent 2 returns successfully:
- Files modified: 3 (error-handling-patterns, test-design-patterns, code-review-guidelines)
- Cross-references added: 7 total (2-3 per file)
- All references use consistent markdown link format
- No conflicts encountered

The musician logs: `step 2 agent 2 returned [ctx: 26%]`.
</core>
</section>

<section id="integration-assessment">
<core>
## Step 7: Integration Assessment

The musician checks:
1. Both agents completed without errors
2. All required deliverables present and valid
3. File structure is consistent with existing knowledge-base patterns
4. No conflicting changes

Assessment: Both agents succeeded, integration is clean. The musician updates its status: `step 2 agents 1-2 integrated successfully [ctx: 27%]`.
</core>
</section>

<section id="handle-agent-failure-alternative-path">
<core>
## Step 8: Handle Agent Failure (Alternative Path)

If Agent 2 had failed (e.g., conflicting edits or broken links), the musician would:
1. Log the failure: `step 2 agent 2 FAILED — [error reason]`
2. Assess: Is this a retry-able error or structural issue?
3. Retry 1: Adjust the prompt with more specific constraints (e.g., "Avoid editing lines 45-60 due to pending changes")
4. If Retry 1 succeeds, integrate results
5. If Retry 2 fails, escalate to conductor with error details
</core>
</section>

<section id="summary">
<context>
## Summary

Both subagents completed successfully. The musician went from delegation decision → Launch Agent 1 → Integrate → Launch Agent 2 → Integrate, consuming ~7-8% context. Step 2 is now ready for verification testing at the checkpoint. The musician logs the step completion and moves to the next phase of task execution.
</context>
</section>

</skill>
