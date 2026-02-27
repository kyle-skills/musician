# Musician README Rewrite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite `musician/README.md` from a 31-line stub to a comprehensive ~300-350 line Lethe-style reference document.

**Architecture:** Single-file rewrite of `README.md` built section-by-section from the approved design (`docs/designs/2026-02-26-musician-readme-rewrite-design.md`). Content is sourced from `skill/SKILL.md` and `skill/references/*.md` — the README surfaces operational detail, it doesn't invent it.

**Tech Stack:** Markdown, shell (validation scripts)

---

### Task 1: Write Intro and Comparison Tables

**Files:**
- Modify: `README.md`
- Reference: `docs/designs/2026-02-26-musician-readme-rewrite-design.md` (Section 1)
- Reference: `skill/SKILL.md:27-31` (context block for accurate positioning language)

**Step 1: Read current README and design doc Section 1**

Read `README.md` (current 31-line stub) and the design doc's Section 1 for the approved intro structure.

**Step 2: Write the title, metaphor paragraphs, and two comparison tables**

Replace the entire README with:

- `# Musician: Perform the Score Under the Conductor's Baton`
- Paragraph 1: Real-world orchestral musician role. Focus on the conductor-following relationship — receiving the part, watching for cues, entries, dynamics, corrections. Playing autonomously within their line but never in isolation.
- Paragraph 2: Bridge to technical. Receives task instructions from Copyist, claims via database, executes phase-by-phase in dedicated external session, reports status/checkpoints to Conductor, responds to review feedback, manages context budget.
- Table 1: **Musician vs Raw Claude Session** — rows: State tracking, Context management, Error recovery, Delegation, Resumption, Verification
- Table 2: **Musician vs Conductor vs Subagents** — columns: Conductor, Musician, Subagent. Rows: Context budget, Owns, Launches, Reports to, Persistence, Implementation work

Use exact values from SKILL.md (170k budget, 50/65/75% thresholds, 30k delegation trigger, atomic claim pattern).

**Step 3: Verify tables render correctly**

Visually check that markdown tables are well-formed. Confirm column alignment.

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README intro with orchestral metaphor and comparison tables"
```

---

### Task 2: Write How to Invoke and Execution Lifecycle

**Files:**
- Modify: `README.md`
- Reference: `docs/designs/2026-02-26-musician-readme-rewrite-design.md` (Sections 2-3)
- Reference: `skill/SKILL.md` sections: `bootstrap-sequence`, `execution-workflow`

**Step 1: Read design doc Sections 2-3 and SKILL.md bootstrap/execution sections**

Pull accurate bootstrap steps, phase execution model, checkpoint flow, and review cycle details from source.

**Step 2: Append How to Invoke section**

- Launched by Conductor in dedicated terminal session (no kitty reference — generic terminal language)
- Conductor provides: task ID, feature name, session suffix, instruction file path
- Direct invocation via `/musician` for testing/single-task use

**Step 3: Append Execution Lifecycle section**

Six-step numbered lifecycle:
1. Bootstrap (parse prompt, validate, atomic claim with guard clause)
2. Watcher start (background or pause-based, mandatory continuity)
3. Phase execution (sequential, per-phase: read → execute → delegate → verify)
4. Checkpoint (temp/task-XX-status, database update, review message)
5. Review cycle (wait, respond to corrections, resume on approval)
6. Completion or exit (completed state vs context exhaustion handoff)

Include the ASCII lifecycle diagram from the design doc.

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add invocation and execution lifecycle sections to README"
```

---

### Task 3: Write Context Guardrails and Review Contract

**Files:**
- Modify: `README.md`
- Reference: `docs/designs/2026-02-26-musician-readme-rewrite-design.md` (Sections 4-5)
- Reference: `skill/SKILL.md` section: `context-monitoring`
- Reference: `skill/references/watcher-protocol.md`
- Reference: `skill/references/state-machine.md`
- Reference: `skill/SKILL.md` sections: `checkpoint-verification`, `review-communication`, `message-formats`

**Step 1: Read source references for accurate threshold values and state transitions**

Confirm exact threshold percentages, delegation trigger, watcher requirements, checkpoint fields, and state machine transitions from authoritative sources.

**Step 2: Append Context and Watcher Guardrails section**

Three subsections:
- **Context Thresholds** table: >50% (estimate before reads), 65% (warning + handoff prep), 75% (mandatory exit). Note 170k budget, heuristic estimation.
- **Delegation Trigger**: ~30k+ context cost defaults to subagent. Musician retains integration + cross-cutting.
- **Watcher Continuity**: Background or pause-based polling always active. Monitors `orchestration_messages` for directives.

**Step 3: Append Review and Messaging Contract section**

Two subsections:
- **Checkpoint Message Fields** table: Status, Key Outputs, Smoothness (0-9), Agents Remaining (percentage), Issues, Next
- **State Transitions** table: pending→in_progress (claim), in_progress→paused (review wait), paused→in_progress (approval), in_progress→completed (final approval), in_progress→error (exhaustion/failure). Note heartbeat on every transition.

**Step 4: Cross-check values against SKILL.md**

Verify every threshold, field name, and state value matches the authoritative source. Fix any discrepancies.

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add context guardrails and review contract to README"
```

---

### Task 4: Write Task-Instruction Contract, RAG Policy, and Validation Scripts

**Files:**
- Modify: `README.md`
- Reference: `docs/designs/2026-02-26-musician-readme-rewrite-design.md` (Sections 6-8)
- Reference: `skill/SKILL.md` section: `task-instruction-processing`
- Reference: `skill/SKILL.md` section: `proposal-system`
- Reference: `skill/references/checkpoint-verification.md`
- Reference: `skill/scripts/validate-musician-state.sh`
- Reference: `skill/scripts/check-context-headroom.sh`
- Reference: `skill/scripts/verify-temp-files.sh`

**Step 1: Read task-instruction and proposal sections from SKILL.md**

Confirm Tier 3 format, `<template follow="exact">` rule, and section vocabulary.

**Step 2: Append Task-Instruction Contract section**

- Tier 3 `<task-instruction>` format, `<template follow="exact">` rule
- Section vocabulary table: Objective, Context, Prerequisites, Steps, Verification, Checkpoint, Error Handling, Handoff — with "Musician reads for" column

**Step 3: Append RAG and Proposal Policy section**

- Query-only for Musicians via `query_documents`
- No `ingest_data` or `ingest_file`
- Proposals written to `docs/implementation/proposals/`
- Conductor evaluates during review; Musicians never act unilaterally

**Step 4: Append Validation Scripts section**

Table of three scripts with purpose:
- `validate-musician-state.sh` — database state consistency
- `check-context-headroom.sh` — context budget estimation
- `verify-temp-files.sh` — temp file path validation

Include example invocation: `bash skill/scripts/validate-musician-state.sh`

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add task-instruction contract, RAG policy, and validation scripts to README"
```

---

### Task 5: Write Project Structure, Known Limits, and Closing Sections

**Files:**
- Modify: `README.md`
- Reference: `docs/designs/2026-02-26-musician-readme-rewrite-design.md` (Sections 9-12)

**Step 1: Verify current file tree matches design doc structure**

Run `find` or `ls -R` on `skill/` and `docs/` to confirm the project structure tree is accurate against the actual repo layout.

**Step 2: Append Project Structure section**

Accurate tree with inline comments for each file's purpose. Include:
- `skill/SKILL.md`, `skill/references/` (all 7 files), `skill/examples/` (all 8 files), `skill/scripts/` (all 3 files)
- `docs/archive/`, `docs/designs/`, `docs/working/`, `docs/plans/`

**Step 3: Append Known Limits section**

Three bullet points:
- Approximate context estimation (heuristic, errs conservative)
- Single-task sessions (parallel is Conductor's responsibility)
- No direct RAG ingestion (query only)

**Step 4: Append Planned Improvements section**

Three bullet points:
- Arranger integration
- Improved context estimation
- Richer handoff files

**Step 5: Append Usage and Origin sections**

- Usage: Launched by Conductor in dedicated terminal session. Direct via `/musician`.
- Origin: Part of The Elevated Stage. Link to design doc.

**Step 6: Final review pass**

Read the complete README top to bottom. Check:
- All section headings present and ordered per design
- No kitty-specific terminal references
- All values match SKILL.md sources
- Markdown renders cleanly (tables, code blocks, lists)

**Step 7: Commit**

```bash
git add README.md
git commit -m "docs: complete README rewrite with structure, limits, and closing sections"
```

---

### Task 6: Acceptance Verification

**Files:**
- Read: `README.md` (complete)
- Reference: `docs/designs/2026-02-26-musician-readme-rewrite-design.md` (Acceptance Criteria)

**Step 1: Run through acceptance checklist**

Verify each item from the design doc:

- [ ] Paths in structure section match current repo layout
- [ ] Context thresholds and watcher protocol fully documented
- [ ] Review/checkpoint message schema includes all required fields
- [ ] Copyist section vocabulary table represented
- [ ] RAG restrictions and proposal routing explicit (proposals to `docs/implementation/proposals/`)
- [ ] Validation scripts documented with example invocations
- [ ] README tone/format mirrors Lethe: concise narrative + dense operational tables
- [ ] No kitty-specific terminal references
- [ ] Two comparison tables present (vs raw session, vs tier roles)
- [ ] Orchestral metaphor intro with conductor-following angle

**Step 2: Fix any failures**

Address any checklist items that don't pass.

**Step 3: Final commit if fixes were needed**

```bash
git add README.md
git commit -m "docs: address acceptance criteria findings in README"
```
