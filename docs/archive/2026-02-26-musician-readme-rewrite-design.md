# Musician README Rewrite Design

**Date:** 2026-02-26
**Status:** Approved
**Scope:** Full rewrite of `musician/README.md` to match Lethe README quality/depth standard with Elevated Stage orchestral intro pattern.

## Design Decisions

- **Intro style:** Lethe-style (two paragraphs). First paragraph establishes the real-world orchestral musician role focused on the conductor-following relationship. Second paragraph bridges to the technical skill.
- **Title subtitle:** "Perform the Score Under the Conductor's Baton"
- **Comparison tables:** Two tables. First: Musician vs Raw Claude Session (justifies why). Second: Musician vs Conductor vs Subagents (shows where it fits).
- **Depth:** Lethe-depth (~300-350 lines). Musician is the most complex orchestration skill; the README serves as standalone reference.
- **Terminal references:** Generic "dedicated terminal session" — no kitty-specific language. Terminal compatibility is the Conductor's concern.
- **Proposals:** Written to `docs/implementation/proposals/` directory, not just inline in checkpoint messages.

## Section Outline

### 1. Title + Intro

```
# Musician: Perform the Score Under the Conductor's Baton
```

**Paragraph 1 (real-world musician):** An orchestral musician doesn't interpret the full score. They receive their individual part from the copyist, take their seat in the section, and watch the conductor. The conductor sets the tempo, cues entries, signals dynamics, and corrects course mid-performance. The musician's job is to execute their part faithfully while staying responsive to those cues — playing autonomously within their line, but never in isolation from the ensemble.

**Paragraph 2 (bridge to technical):** The `musician` skill follows the same relationship. It receives self-contained task instructions (extracted by the Copyist), claims its assignment through the orchestration database, and executes phase-by-phase in a dedicated external session. Throughout execution it reports status and checkpoints back to the Conductor, responds to review feedback and corrections, and manages its own context budget — performing its part autonomously while staying connected to the larger production.

**Table 1: Musician vs Raw Claude Session**

| | Raw Claude session | Musician |
|---|---|---|
| **State tracking** | None — session dies, progress lost | Database-driven: claim, heartbeat, checkpoint, resume |
| **Context management** | Hope you finish before the window fills | Threshold protocol: estimate at 50%, warn at 65%, mandatory exit at 75% |
| **Error recovery** | Start over | Conductor review cycles, correction attempts, Repetiteur escalation |
| **Delegation** | Manual | Auto-delegates 30k+ cost work to subagents with budget tracking |
| **Resumption** | Re-explain everything | Handoff files carry state across session succession |
| **Verification** | Trust the output | External validation required for every category |

**Table 2: Musician vs Conductor vs Subagents**

| | Conductor | Musician | Subagent |
|---|---|---|---|
| **Context budget** | 1M tokens | 170k tokens (exit at 75%) | Within Musician's budget |
| **Owns** | Plan decomposition, task dispatch, review | Phase execution, checkpoint, delegation | Single focused unit of work |
| **Launches** | Musicians, Copyist, Repetiteur | Subagents (Task tool) | Nothing |
| **Reports to** | User | Conductor | Musician |
| **Persistence** | Full session | Database state + handoff files | Ephemeral |
| **Implementation work** | Never | Integration + cross-cutting | Focused/isolated tasks |

### 2. How to Invoke

Launched by the Conductor in a dedicated terminal session. The Conductor provides the task ID, feature name, session suffix, and instruction file path via the launch prompt.

For direct invocation: `/musician`. Direct mode is useful for testing or running a single task outside the full orchestration pipeline. The skill prompts for the task ID and instruction file path.

### 3. Execution Lifecycle

Six-step lifecycle:

1. **Bootstrap** — Parse launch prompt, validate task ID against database, claim task atomically (UPDATE with guard clause, verify 1 row affected).
2. **Watcher start** — Launch background message watcher or pause-based polling. Watcher continuity is mandatory throughout the session.
3. **Phase execution** — Process task instruction file phase-by-phase. Each phase: read instructions, execute steps, delegate where appropriate, verify results.
4. **Checkpoint** — After each phase, write status to `temp/task-XX-status`, update database state, send review message to Conductor.
5. **Review cycle** — Wait for Conductor review. Respond to corrections. Resume next phase on approval.
6. **Completion or exit** — On final phase approval: set state to `completed`. On context exhaustion: write handoff file, set `context_exhaustion_warning`, exit cleanly for successor session.

Include ASCII lifecycle diagram:

```
Bootstrap → Claim → Watcher Start → Phase Loop ──→ Checkpoint → Review
                                         ↑                         │
                                         └─────── approved ────────┘
                                                                    │
                                            correction ─────────────┘
                                                                    │
                                         Context exit ──→ Handoff ──→ Successor
                                         Final phase ──→ Complete
```

### 4. Context and Watcher Guardrails

**Context Thresholds table:**

| Threshold | Action |
|---|---|
| >50% | Estimate context cost before every file read. Skip reads that aren't essential. |
| 65% | Context warning. Prepare handoff file. Finish current phase if possible. |
| 75% | Mandatory exit. Write handoff, set `context_exhaustion_warning` state, send exit message. |

Session budget: 170k tokens. Thresholds use heuristic estimation.

**Delegation trigger:** Default to delegation for ~30k+ token work. Musician retains integration and cross-cutting.

**Watcher continuity:** Background message watcher or pause-based polling must be active at all times. Monitors `orchestration_messages` for Conductor directives.

### 5. Review and Messaging Contract

**Checkpoint message fields table:**

| Field | Content |
|---|---|
| Status | Current phase, what was completed |
| Key Outputs | Files created/modified, tests passing, artifacts produced |
| Smoothness | Self-assessment score (0-9 scale from task instructions) |
| Agents Remaining | Percentage of subagent budget remaining |
| Issues | Blockers, deviations, questions for Conductor |
| Next | What the next phase will do (or "final phase complete") |

**State transitions table:**

| From | To | Trigger |
|---|---|---|
| `pending` | `in_progress` | Successful atomic claim |
| `in_progress` | `in_progress` | Phase checkpoint (heartbeat updated) |
| `in_progress` | `paused` | Waiting for Conductor review |
| `paused` | `in_progress` | Conductor approval received |
| `in_progress` | `completed` | Final phase approved |
| `in_progress` | `error` | Context exhaustion or unrecoverable failure |

Every state transition includes `last_heartbeat = datetime('now')`.

### 6. Task-Instruction Contract

Instructions use Tier 3 `<task-instruction>` format with `<template follow="exact">`.

**Section vocabulary table:**

| Section | Musician reads for |
|---|---|
| Objective | What success looks like |
| Context | Background, constraints, architecture notes |
| Prerequisites | What must be true before starting |
| Steps | Ordered implementation work |
| Verification | How to confirm each step succeeded |
| Checkpoint | What to report to Conductor and when |
| Error Handling | Recovery paths for anticipated failures |
| Handoff | What to leave for a successor session |

### 7. RAG and Proposal Policy

Musicians can **query** local-rag. Musicians **cannot** ingest data/files — that authority belongs to the Conductor.

When a Musician identifies a need for new documentation, architectural decisions, or scope changes, it writes a **proposal** in the `docs/implementation/proposals/` directory. The Conductor evaluates proposals during review. Musicians never act on proposals unilaterally.

### 8. Validation Scripts

| Script | Purpose |
|---|---|
| `skill/scripts/validate-musician-state.sh` | Database state consistency for active tasks |
| `skill/scripts/check-context-headroom.sh` | Context budget estimation |
| `skill/scripts/verify-temp-files.sh` | Temp file path validation |

### 9. Project Structure

Accurate tree reflecting current layout:

```
musician/
├── skill/
│   ├── SKILL.md                              # Skill definition (entry point)
│   ├── references/
│   │   ├── checkpoint-verification.md        # External verification categories
│   │   ├── database-queries.md               # SQL patterns for state management
│   │   ├── rag-proposal-template.md          # Proposal format for RAG/doc needs
│   │   ├── resumption-state-assessment.md    # Handoff and successor bootstrap
│   │   ├── state-machine.md                  # State transitions and terminal states
│   │   ├── subagent-delegation.md            # Delegation model and budget tracking
│   │   └── watcher-protocol.md               # Message watcher lifecycle
│   ├── examples/
│   │   ├── example-bootstrap-first-execution.md
│   │   ├── example-checkpoint-flow.md
│   │   ├── example-clean-exit.md
│   │   ├── example-context-break-point.md
│   │   ├── example-error-recovery.md
│   │   ├── example-pause-feedback-cycle.md
│   │   ├── example-resumption.md
│   │   └── example-subagent-launch.md
│   └── scripts/
│       ├── validate-musician-state.sh
│       ├── check-context-headroom.sh
│       └── verify-temp-files.sh
└── docs/
    ├── archive/                              # Historical design documents
    ├── designs/                              # Skill design specifications
    └── working/                              # Active design work
```

### 10. Known Limits

- Context estimation is approximate — thresholds use heuristic estimation, not exact token counts. Errs conservative.
- Single-task sessions — each Musician handles one task. Parallel execution is the Conductor's responsibility.
- No direct RAG ingestion — Musicians can query but not write to the knowledge base.

### 11. Planned Improvements

- Arranger integration for direct plan-to-execution pipeline
- Improved context estimation using token counting where available
- Richer handoff files for multi-session task continuity

### 12. Usage + Origin

Launched by the Conductor in a dedicated terminal session. Can also be invoked directly via `/musician`.

Part of [The Elevated Stage](https://github.com/The-Elevated-Stage) orchestration system. Design docs: `docs/designs/2026-02-18-musician-skill-redesign-design.md`.

## Content Sources

Implementation should pull accurate values from:

- Core behavior: `skill/SKILL.md`
- SQL/state contracts: `skill/references/database-queries.md`, `skill/references/state-machine.md`
- Watcher protocol: `skill/references/watcher-protocol.md`
- Delegation model: `skill/references/subagent-delegation.md`
- Verification policy: `skill/references/checkpoint-verification.md`
- Examples: `skill/examples/*.md`
- Historical rationale: `docs/archive/2026-02-18-musician-skill-redesign-design.md`

## Acceptance Criteria

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
