# Musician README Deep Dive

**Date:** 2026-02-26  
**Scope:** Audit `musician/README.md` for completeness and freshness, compare against current `musician/skill/` behavior and Lethe README style at `/home/kyle/claude/skills_staged/kyle-skills/lethe/README.md`.

## Executive Findings

1. **Yes, Musician already has a README** at `musician/README.md`.
2. The current README is **stale** and materially out of date:
   - It was added on **2026-02-19** and has not changed since.
   - Major behavior/spec updates landed on **2026-02-24** in `skill/SKILL.md` and references.
3. The current README does **not** match the depth or format quality of Lethe's README.
4. A README refresh is needed to reflect current v2 behavior, current repo layout, and operational guardrails.

## Evidence Snapshot

- Line count comparison:
  - `musician/README.md`: **31 lines**
  - `musician/skill/SKILL.md`: **472 lines**
  - `lethe/README.md`: **339 lines**
- Git history highlights:
  - `README.md` created: **2026-02-19** (`1fb0377`)
  - Skill updates after README creation: **2026-02-24** (`5fdd913`, `0cd23fa`, `e2e43b0`, `955150b`, `14d2d6c`)

## Drift Analysis (README vs Current Musician)

## 1) Structural Drift

- README structure block is outdated:
  - Mentions `SKILL.md`, `examples/`, `references/`, `scripts/` at repo root.
  - Current layout is `skill/SKILL.md`, `skill/examples/`, `skill/references/`, `skill/scripts/`.
- README usage text references `docs/tasks/` as instruction source, but current bootstrap flow is prompt/query-driven and path-based from orchestration messages.

## 2) Behavioral Drift (Missing Core Protocols)

Current README omits core v2 behavior now codified in `skill/SKILL.md`, including:

- **Watcher continuity is mandatory** (background or pause watcher always active).
- **Context threshold protocol:** >50% estimate-before-read, 65% context warning + handoff prep, 75% mandatory exit.
- **Exact context-warning contract:** `state='error'`, `last_error='context_exhaustion_warning'`, `message_type='context_warning'`.
- **`exit_requested` handling** in review flow.
- **Delegation model update:** default-to-delegation at ~30k+ context cost, Task()/Teams split, explicit review budget expectations.
- **No proactive pings:** conductor monitors `temp/task-XX-status` passively via subagent reads.
- **Proposal system constraints:** musician can query RAG but cannot ingest data/files directly.
- **Template strictness:** Copyist `<template follow="exact">` reproduction requirement.
- **Expanded review message schema:** includes `Key Outputs` and `Agents Remaining` percentage format.

## 3) Operational Drift

README does not document:

- Validation scripts in `skill/scripts/` and when to run them.
- `temp/` conventions and why project-relative temp paths are mandatory.
- State machine expectations and terminal-write ordering.
- Resumption/HANDOFF mechanics across session succession (`-S2`, `-S3`, etc.).

## Lethe Mimic Gap (Style + Coverage)

Lethe README sets a clear target quality bar with:

1. Narrative intro and positioning.
2. Comparison table for conceptual clarity.
3. Practical sections: installation, usage, configuration, internals, safety, structure, planned features.
4. Explicit operational guardrails and failure handling.

Musician README currently has only:

- What It Does
- Structure
- Usage
- Origin

It lacks the architecture depth, operational protocol detail, and maintainability sections that Lethe provides.

## Recommended README vNext Outline (Lethe-Style, Musician-Specific)

Use this structure for rewrite:

1. **Title + positioning intro**
   - What Musician is in the orchestra stack.
2. **Musician vs Conductor vs Subagents**
   - Comparison table (ownership boundaries, context budget, outputs).
3. **How to invoke**
   - `/musician` and launch context assumptions.
4. **Execution lifecycle**
   - Bootstrap -> claim -> execute -> checkpoint -> pause/resume -> complete/exit.
5. **Context and watcher guardrails**
   - Threshold table (50/65/75), heartbeat constants, pause timeout.
6. **Review and messaging contract**
   - Required checkpoint fields and state transitions.
7. **Task-instruction contract (Copyist vocabulary)**
   - Section mapping table and `<template follow="exact">` rule.
8. **RAG and proposal policy**
   - Query-only for musician, proposal flow to conductor.
9. **Validation scripts**
   - `validate-musician-state.sh`, `check-context-headroom.sh`, `verify-temp-files.sh`.
10. **Project structure**
   - Accurate current tree rooted at `skill/` and `docs/`.
11. **Change log highlights**
   - Brief timeline from 2026-02-18 through 2026-02-26.
12. **Known limits / planned improvements**
   - Keep this small but explicit.

## Proposed Content Sources (to keep README accurate)

- Core behavior: `skill/SKILL.md`
- SQL/state contracts: `skill/references/database-queries.md`, `skill/references/state-machine.md`
- Watcher protocol: `skill/references/watcher-protocol.md`
- Delegation model: `skill/references/subagent-delegation.md`
- Verification policy: `skill/references/checkpoint-verification.md`
- Real examples: `skill/examples/*.md`
- Historical rationale: `docs/archive/2026-02-18-musician-skill-redesign-design.md`

## Acceptance Checklist for README Refresh

- [ ] Paths in structure section match current repo layout (`skill/...`).
- [ ] Context thresholds and watcher protocol are fully documented.
- [ ] Review/checkpoint message schema includes all required fields.
- [ ] Copyist section vocabulary table is represented.
- [ ] RAG restrictions and proposal routing are explicit.
- [ ] Validation scripts are documented with example invocations.
- [ ] Change-log snapshot includes all post-README behavior updates from 2026-02-24.
- [ ] README tone/format mirrors Lethe: concise narrative + dense operational tables.

## Bottom Line

The Musician README exists but is currently a legacy stub relative to the actual skill spec. It should be rewritten (not lightly edited) to align with the current v2 operational contract and to match the Lethe README quality/style standard.
