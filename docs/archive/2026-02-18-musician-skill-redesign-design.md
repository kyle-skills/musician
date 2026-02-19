# Musician Skill Redesign — Design Document

**Date:** 2026-02-18
**Status:** Approved
**Type:** Skill redesign (two-phase)
**Scope:** Musician skill structural migration + content overhaul + Copyist alignment

---

## 1. Problem Statement

The Musician skill (275 lines, pure markdown) has accumulated 11 documented issues
(Obsidian notes) around context awareness, subagent usage, authority signal weakness,
and operational timing. Additionally, the Copyist skill has been migrated to the hybrid
XML/Markdown document structure, and the Musician needs both structural migration and
content alignment with the new Copyist task instruction format.

The Conductor skill is NOT updated yet and is out of scope for this work.

---

## 2. Phase Structure

Two independent phases, each plannable and executable separately:

| Phase | Scope | Description |
|-------|-------|-------------|
| **Phase 1** | Structural migration | Convert all Musician skill files to hybrid document structure (Tier 2/3). No content changes. |
| **Phase 2** | Content + alignment | Apply all 11 content changes and align with Copyist task instruction format. |

---

## 3. Phase 1: Structural Migration

### 3.1 SKILL.md → Tier 2

The main SKILL.md gets Tier 2 treatment (hybrid doc spec classifies musician/copyist
as "simple skill" — single workflow, <300 lines).

**Transformation:**
- Add `<sections>` index listing all section IDs
- Wrap each H2 section in `<section id="kebab-case">`
- Classify content inside sections with authority tags:
  - Rules, constraints, non-negotiable requirements → `<mandatory>`
  - Steps, deliverables, workflow content → `<core>`
  - Recommendations, best practices → `<guidance>`
  - Background information, explanations → `<context>`
- Preserve all existing content — same words, new structure
- Existing inline emphasis (CRITICAL, NEVER, bold) preserved inside their new tag wrappers
- Version bumped to 2.0

**Section ID mapping (current H2 → section ID):**

| Current Heading | Section ID |
|----------------|------------|
| Core Principles | `core-principles` |
| Bootstrap Sequence | `bootstrap-sequence` |
| Execution Workflow | `execution-workflow` |
| Context Monitoring & Escalation | `context-monitoring` |
| Checkpoint Verification Protocol | `checkpoint-verification` |
| Review & Conductor Communication | `review-communication` |
| Message Format Standards | `message-formats` |
| Temporary File Management | `temp-file-management` |
| Proposal System | `proposal-system` |
| Clean Exit & Resumption | `clean-exit-resumption` |
| Key References | `key-references` |
| Deviations & Escalation Thresholds | `deviations` |
| Tool Access & Capabilities | `tool-access` |

Plus a new first section: `mandatory-rules` (collected mandatory block).

### 3.2 Reference Files → Tier 3

7 reference files, each wrapped in `<skill>` envelope:

```xml
<skill name="musician-[reference-name]" version="2.0">
<metadata>
type: reference
parent-skill: musician
tier: 3
</metadata>
<sections>...</sections>
...
</skill>
```

All text inside authority tags (Tier 3 strict rule). Current headings become sections.

**Files:**
- `references/checkpoint-verification.md`
- `references/database-queries.md`
- `references/rag-proposal-template.md`
- `references/resumption-state-assessment.md`
- `references/state-machine.md`
- `references/subagent-delegation.md`
- `references/watcher-protocol.md`

### 3.3 Example Files → Tier 3

8 example files, same `<skill>` wrapper and Tier 3 discipline. Examples are primarily
`<core>` content with `<context>` for setup/explanation.

**Files:**
- `examples/example-bootstrap-first-execution.md`
- `examples/example-checkpoint-flow.md`
- `examples/example-clean-exit.md`
- `examples/example-context-break-point.md`
- `examples/example-error-recovery.md`
- `examples/example-pause-feedback-cycle.md`
- `examples/example-resumption.md`
- `examples/example-subagent-launch.md`

### 3.4 Scripts

No structural changes. Scripts are bash, not Claude-consumed markdown.

### 3.5 Phase 1 Success Criteria

- All 16 markdown files reformatted to appropriate tier
- `<sections>` index present in every Tier 2/3 file
- All section IDs match their index entries
- Tier 3 files: no naked markdown outside authority tags
- Content diff shows zero semantic changes (only structural additions)

---

## 4. Phase 2: Content Changes + Copyist Alignment

### 4.A Context Monitoring Overhaul

**Replaces:** Current gradual escalation (50% monitor, 70-80% warn, >80% escalate)

**New three-threshold model:**

| Threshold | Action |
|-----------|--------|
| **Always** | Check context usage on every system message response. Log to `temp/task-XX-status`. |
| **>50%** | Estimate context cost before every file read. Include estimate in status log. No speculative reads. |
| **65%** | Prepare handoff: write HANDOFF doc, update temp/ status, finish current step only, no new work steps. |
| **75%** | Mandatory exit. Stop all work immediately. Complete HANDOFF, set state to `exited`. |

**Framing:** 80% is NOT "20% remaining" — it is the danger zone for logic poisoning.
Hallucinations increase, instruction adherence drops, and partial work is worse than
no work. Sessions are cheap to restart; context exhaustion can lock up an entire project.

**Inline reinforcement:** Every section involving file reads or work gets inline
`<mandatory>` reminding about context checks. This is one of the two most heavily
reinforced rules (alongside message-watcher).

### 4.B Delegation Model (Subagent → Teammates/Hybrid)

**Replaces:** Optional delegation based on <500 LOC / isolated criteria.

**New model — Default to delegation, hybrid Task/Teams:**

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

**Delegation threshold:** 30k+ tokens estimated context cost → delegate.
Mode choice: simple (one step, one file) → Task(). Complex (multiple steps, own TDD
cycle) → Teams.

**Universal rule:** Musician ALWAYS thoroughly reviews delegated work, regardless of
delegation mode. Review budget: ~2x the delegation cost.

**Self-review failure:** If self-review finds issues beyond simple one-line edits,
the fix MUST go to a fresh agent/teammate. Opus in the same context can enter tunnel
vision — chasing its own errors in circles. Fresh context eliminates this.

**TDD scoping:** Musician practices TDD for integration work it keeps. Subagents/teammates
get TDD requirements in their delegation prompts and can invoke the TDD skill directly.

### 4.C Timing and Monitoring

**Watcher heartbeat refresh:** 60 seconds (changed from 8 minutes). Watcher refreshes
heartbeat on every cycle if >60s since last refresh.

**Watcher relaunch urgency:** Inline `<mandatory>` at every execution step:
"If background watcher is not running, relaunch IMMEDIATELY before any other action."
This is one of the two most heavily reinforced rules.

**Completion cleanup:** Explicit step in completion section: terminate background
watcher (TaskStop) BEFORE setting terminal state.

### 4.D Bootstrap Refinements

**Reorder for comms-link warm-up:**

Current: Parse task → Session ID → Claim → Read instructions → Init temp → Watcher

New:
1. Parse task identity (from launch prompt)
2. Session ID validation (from system prompt)
3. Read task instruction file path from launch prompt
4. Read available reference docs (non-DB ops while comms-link warms up)
5. Atomic task claim via comms-link (now ready)
6. Init temp files
7. Launch background watcher
8. Begin execution

**Memory graph check:** Before first tool use in execution, check memory graph for
tool-specific guidance: `search_nodes("[tool-name] guidance")`.

### 4.E Smoothness Scale

**Replaces:** Brief 0-9 mention without granular definitions.

| Score | Meaning | When to use |
|-------|---------|-------------|
| 0 | Perfect execution | Zero deviations, all tests pass first try, no self-corrections |
| 1 | Near-perfect | One minor clarification, self-resolved instantly |
| 2 | Minor bumps | 1-2 small deviations, documented, no impact on deliverables |
| 3 | Some friction | Minor issues required small adjustments |
| 4 | Noticeable deviations | Multiple deviations documented, all resolved |
| 5 | Significant issues | Conductor input was/would be needed for decisions |
| 6 | Multiple problems | Several issues, some required creative solutions |
| 7 | Major blockers | Blocked on something, required multiple attempts |
| 8 | Near-failure | Major blockers, fundamental issues with approach |
| 9 | Failed/incomplete | Cannot complete as specified, needs redesign |

Direction: **0 = smoothest, 9 = roughest.** Always explicit.

### 4.F Authority Distribution

Both collected `<mandatory>` block at top AND inline `<mandatory>` reinforcements
throughout. The two most heavily reinforced rules:

1. **Context monitoring** — appears inline at every step that reads files or does work
2. **Message-watcher running** — appears inline at every execution step

### 4.G Copyist Alignment

**New section:** Task Instruction Processing

After bootstrap loads the task instruction file, the musician processes it by
recognizing the Copyist's section vocabulary:

| Section ID | Musician action |
|------------|----------------|
| `mandatory-rules` | Read fully, internalize all rules before proceeding |
| `objective` | Understand goal and success criteria |
| `prerequisites` | Execute pre-flight checks, fail fast if any fail |
| `bootstrap` | Execute claim SQL and monitoring setup from templates |
| `execution` | Follow steps in order, delegate per subagent model |
| `rag-proposals` | Create proposals as directed |
| `review-checkpoint` | Execute review protocol (parallel tasks only) |
| `post-review-execution` | Continue work after approval (parallel only) |
| `verification` | Run all checks, all must pass |
| `testing` | Run specified tests |
| `completion` | Commit, update DB, generate report |
| `deliverables` | Verify all deliverables present |
| `error-recovery` | Follow if errors occur at any point |
| `reference` | Available for context, not required reading |

**Message field count:** Standardize on **10 fields** (includes both `Proposal` and
`Reason`). Update all cross-references in Copyist and Musician to match.

### 4.H Phase 2 Success Criteria

- All 11 Obsidian items addressed
- Context thresholds updated to new three-threshold model
- Delegation model reflects hybrid Task/Teams approach
- Smoothness scale has granular definitions
- Inline `<mandatory>` reinforcements present for context monitoring and watcher
- Task instruction processing section added with Copyist section vocabulary
- Message fields standardized to 10 across Musician and Copyist
- Watcher heartbeat refresh at 60 seconds
- Bootstrap reordered for comms-link warm-up

---

## 5. Files Affected

### Phase 1 (structural only)
- `skills_staged/musician/SKILL.md` — Tier 2 migration
- `skills_staged/musician/references/*.md` (7 files) — Tier 3 migration
- `skills_staged/musician/examples/*.md` (8 files) — Tier 3 migration

### Phase 2 (content + alignment)
- `skills_staged/musician/SKILL.md` — All content changes
- `skills_staged/musician/references/watcher-protocol.md` — Heartbeat timing
- `skills_staged/musician/references/subagent-delegation.md` — Delegation model
- `skills_staged/musician/references/checkpoint-verification.md` — Context thresholds
- `skills_staged/musician/references/database-queries.md` — Message field count
- `skills_staged/musician/references/state-machine.md` — Context exit states
- Possibly `skills_staged/copyist/SKILL.md` — Message field count update (10 fields)
- Possibly `skills_staged/copyist/references/schema-and-coordination.md` — Field count

---

## 6. What's NOT In Scope

- Conductor skill (not updated yet, will follow separately)
- Orchestration DB schema changes
- New reference files (fold new content into existing files)
- Script changes (Phase 1); script changes may be needed in Phase 2 for validation
- Live skill deployment (changes go to `skills_staged/`)
