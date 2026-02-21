<skill name="musician-rag-proposal-template" version="2.0">

<metadata>
type: reference
parent-skill: musician
tier: 3
</metadata>

<sections>
- active-pattern-recognition
- checkpoint-proposal-review
- pre-screening-procedure
- proposal-file-structure
</sections>

<section id="active-pattern-recognition">
<context>
# Reference: RAG Proposal Template

This reference describes how musicians identify, pre-screen, and propose new
knowledge-base entries during task execution.
</context>

<core>
## Active Pattern Recognition

Pattern recognition is continuous — not a discrete step. While executing task
instructions, watch for knowledge-worthy signals in everything you touch:

**What to watch for:**
- A technique that solved a non-obvious problem
- A workaround that future sessions would benefit from knowing
- An anti-pattern that caused wasted time or context
- A decision with rationale worth preserving (why X over Y)
- A reusable code pattern applicable beyond this task
- A testing strategy or debugging approach that proved effective
- An architectural insight discovered during implementation
- A behavior that worked well (or didn't) worth documenting

**Sources — watch these continuously:**
- Files you're creating or modifying — do they contain reusable patterns?
- Subagent results — did a delegated task reveal something transferable?
- Error recovery — did you solve something that others will encounter?
- Self-correction — what went wrong and what fixed it?
- Deviations from plan — do they reveal a gap in existing knowledge?
- Sections you're modifying repeatedly — is there a pattern in the churn?

When you notice something, note it in `temp/task-XX-status` (e.g.,
`potential RAG: widget testing pattern discovered [ctx: 35%]`) and continue
working. Create the proposal at the next natural pause — don't interrupt flow.
</core>
</section>

<section id="checkpoint-proposal-review">
<guidance>
## Checkpoint Proposal Review

At each checkpoint, before submitting for conductor review, take a
deliberate "look back" at work since the last checkpoint:

1. Review what was accomplished — scan completed steps and their outcomes
2. Check `temp/task-XX-status` for any "potential RAG" notes you flagged
3. Consider the bigger picture: do the pieces assembled reveal a pattern
   that wasn't visible step-by-step?
4. Ask: did I learn something about the codebase, tooling, or workflow that
   isn't captured in the knowledge base?

This review catches patterns that emerge from accumulated work — things that
aren't obvious in the moment but become clear in retrospect.

**When in doubt, create the proposal.** The conductor deduplicates and
triages — a rejected proposal costs nothing, but a missed pattern is lost
knowledge.
</guidance>
</section>

<section id="pre-screening-procedure">
<core>
## Pre-Screening Procedure

Before creating a RAG proposal, check for existing overlap:

1. Query `query_documents` with the proposed topic at 0.4 relevance threshold
2. Review all results:
   - Score < 0.3: Strong match exists — read the file. Does it already cover
     this? If yes, consider proposing an update instead of a new file.
   - Score 0.3–0.4: Partial match — the proposal should explain how the new
     file differs from the existing one.
   - No results at 0.4: No overlap — proceed with new file proposal.
3. Record all matches in the proposal's RAG Match List section
</core>
</section>

<section id="proposal-file-structure">
<core>
## Proposal File Structure

RAG proposals are written to `docs/implementation/proposals/`.

### Filename

`rag-{brief-topic}.md` (e.g., `rag-widget-testing-patterns.md`)

### Template

```markdown
---
type: rag-addition
task_id: task-XX
created: YYYY-MM-DD
target_category: {category}
target_filename: {filename}.md
---

# RAG Proposal: {Descriptive Title}

## Reasoning

{Why this belongs in the knowledge base. What pattern was discovered, what
problem it solves, why future sessions would benefit from this knowledge.}

## RAG Match List (0.4 threshold)

| Existing File | Score | Relevance |
|---|---|---|
| {category/filename.md} | {score} | {Brief relationship explanation} |

{If no matches: "No existing entries matched at 0.4 threshold."}

## Proposed RAG File

Target path: `docs/knowledge-base/{target_category}/{target_filename}`

<!-- BEGIN RAG FILE -->
---
id: {kebab-case-id}
created: YYYY-MM-DD
category: {category}
parent_topic: {Logical Grouping}
tags: [{tag1}, {tag2}, {tag3}]
---

<!-- Context: {1-2 sentence explanation of why this file exists and what
triggered its creation.} -->

# {Title}

{Full file content. This section between the RAG FILE delimiters is extracted
verbatim by the conductor — write it exactly as it should appear in the
final knowledge-base file.}

<!-- END RAG FILE -->
```

### Field Reference

**Proposal frontmatter:**

| Field | Value |
|---|---|
| `type` | Always `rag-addition` |
| `task_id` | Current task (e.g., `task-03`) |
| `created` | Today's date (YYYY-MM-DD) |
| `target_category` | Valid KB category (see below) |
| `target_filename` | Kebab-case, matches `id` field + `.md` |

**Valid categories:** `conductor`, `implementation`, `reference`, `testing`,
`api`, `database`, `plans`, `templates`

**RAG file frontmatter (inside delimiters):**

| Field | Value |
|---|---|
| `id` | Kebab-case, matches `target_filename` without `.md` |
| `created` | Same date as proposal |
| `category` | Must match `target_category` |
| `parent_topic` | Logical grouping (used as section header in compiled docs) |
| `tags` | Lowercase descriptive terms for cross-category discovery |

**RAG file content rules:**
- Context comment: HTML comment explaining origin and purpose
- Single concept per file — one focused topic
- Self-contained — understandable without external context
- 50–300 lines typical, ~500 max
- Cross-reference related KB files using paths relative to `knowledge-base/` root
</core>
</section>

</skill>
