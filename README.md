# Musician: Perform the Score Under the Conductor's Baton

An orchestral musician doesn't interpret the full score. They receive their individual part from the copyist, take their seat in the section, and watch the conductor. The conductor sets the tempo, cues entries, signals dynamics, and corrects course mid-performance. The musician's job is to execute their part faithfully while staying responsive to those cues — playing autonomously within their line, but never in isolation from the ensemble.

The `musician` skill follows the same relationship. It receives self-contained task instructions (extracted by the Copyist), claims its assignment through the orchestration database, and executes phase-by-phase in a dedicated external session. Throughout execution it reports status and checkpoints back to the Conductor, responds to review feedback and corrections, and manages its own context budget — performing its part autonomously while staying connected to the larger production.

## Musician vs Raw Claude Session

| | Raw Claude session | Musician |
|---|---|---|
| **State tracking** | None — session dies, progress lost | Database-driven: claim, heartbeat, checkpoint, resume |
| **Context management** | Hope you finish before the window fills | Threshold protocol: estimate at 50%, warn at 65%, mandatory exit at 75% |
| **Error recovery** | Start over | Conductor review cycles, correction attempts, Repetiteur escalation |
| **Delegation** | Manual | Auto-delegates ~30k+ cost work to subagents with budget tracking |
| **Resumption** | Re-explain everything | Handoff files carry state across session succession |
| **Verification** | Trust the output | External validation required for every category |

## Musician vs Conductor vs Subagents

| | Conductor | Musician | Subagent |
|---|---|---|---|
| **Context budget** | 1M tokens | 170k tokens (exit at 75%) | Within Musician's budget |
| **Owns** | Plan decomposition, task dispatch, review | Phase execution, checkpoint, delegation | Single focused unit of work |
| **Launches** | Musicians, Copyist, Repetiteur | Subagents (Task tool) | Nothing |
| **Reports to** | User | Conductor | Musician |
| **Persistence** | Full session | Database state + handoff files | Ephemeral |
| **Implementation work** | Never | Integration + cross-cutting | Focused/isolated tasks |

## How to Invoke

Launched by the Conductor in a dedicated terminal session. The Conductor provides the task ID, feature name, session suffix, and instruction file path via the launch prompt.

For direct invocation:

```
/musician
```

Direct mode is useful for testing or running a single task outside the full orchestration pipeline. The skill prompts for the task ID and instruction file path.

## Execution Lifecycle

1. **Bootstrap** — Parse launch prompt, validate task ID against database, claim task atomically (UPDATE with guard clause, verify 1 row affected).
2. **Watcher start** — Launch background message watcher via Task tool (`general-purpose` agent, `run_in_background=True`). Watcher continuity is mandatory throughout the session.
3. **Phase execution** — Process task instruction file phase-by-phase. Each phase: read instructions, execute steps, delegate where appropriate, verify results.
4. **Checkpoint** — After each phase, write status to `temp/task-XX-status`, update database state, run all verification tests, send review message to Conductor.
5. **Review cycle** — Terminate background watcher, launch foreground pause watcher. Wait for Conductor review. Respond to corrections. Resume next phase on approval.
6. **Completion or exit** — On final phase approval: set state to `complete`. On context exhaustion: write handoff file, set `context_exhaustion_warning` state, exit cleanly for successor session (`-S2`, `-S3`, etc.).

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

## Context and Watcher Guardrails

### Context Thresholds

| Threshold | Action |
|---|---|
| **Always** | Check context usage on every system message. Log to `temp/task-XX-status`. |
| **>50%** | Estimate context cost before every file read. No speculative reads. |
| **65%** | Context warning. Set `state='error'`, `last_error='context_exhaustion_warning'`. Prepare handoff file. Finish current step only. |
| **75%** | Mandatory exit. Stop all work. Write handoff, set state to `exited`, exit cleanly. |

Session budget: 170k tokens. Thresholds use heuristic estimation, not exact counts. Errs conservative — 80% is the danger zone for logic poisoning and hallucinations.

### Delegation Trigger

Default to delegation (subagent via Task tool) for any unit of work estimated at ~30k+ tokens of context cost. Two modes: `Task()` for one-shot single-file work, Teams for multi-step coordinated work. The Musician retains integration, cross-file assembly, and holistic testing. Musician always reviews delegated work — review budget is ~2x the delegation cost.

### Watcher Continuity

A background message watcher or pause-based polling cycle must be active at all times. The watcher monitors `orchestration_messages` for Conductor directives: corrections, approvals, `exit_requested`, and shutdown signals. Watcher gaps mean missed messages.

**Timing constants:**

| Constant | Value |
|---|---|
| Background poll interval | 15 seconds |
| Pause poll interval | 10 seconds |
| Heartbeat refresh threshold | 60 seconds |
| Conductor stale threshold | 9 minutes |
| Pause timeout | 15 minutes |

## Review and Messaging Contract

### Checkpoint Message Fields

Every review request to the Conductor includes:

| Field | Content |
|---|---|
| **Status** | Current phase, what was completed |
| **Key Outputs** | Files created/modified with annotations: `(created)`, `(modified)`, `(rag-addition)` |
| **Smoothness** | Self-assessment score (0-9 scale) |
| **Agents Remaining** | Percentage of subagent budget remaining |
| **Self-Correction** | YES/NO — flags 6x context bloat risk |
| **Deviations** | Count + severity of plan deviations |
| **Issues** | Blockers, questions for Conductor |
| **Next** | What the next phase will do (or "final phase complete") |

### Smoothness Scale

| Score | Meaning |
|---|---|
| 0 | Perfect execution — zero deviations, all tests pass first try |
| 1-2 | Minor clarifications, self-resolved |
| 3-4 | Some deviations, documented |
| 5-6 | Significant issues, conductor input needed |
| 7-8 | Major blockers, multiple review cycles |
| 9 | Failed or incomplete, needs redesign |

### State Transitions

| From | To | Trigger |
|---|---|---|
| `watching` | `working` | Successful atomic claim |
| `working` | `needs_review` | Checkpoint reached, tests pass |
| `working` | `error` | Unrecoverable failure or context exhaustion warning |
| `review_approved` | `working` | Musician resumes after approval |
| `review_failed` | `working` | Musician applies feedback |
| `fix_proposed` | `working` | Musician applies proposed fix |
| `exit_requested` | `exited` | Clean handoff on conductor request |
| `working` | `complete` | Final phase approved (terminal) |
| `working` | `exited` | Context exhaustion handoff (terminal) |
| `error` | `exited` | Retry exhaustion after 5 failed retries (terminal) |

Every state transition includes `last_heartbeat = datetime('now')`. Terminal states (`complete`, `exited`) are irreversible.

## Task-Instruction Contract

Musicians execute instruction files produced by the Copyist. These files use Tier 3 `<task-instruction>` format with a mandatory section skeleton.

### Template Strictness

Instructions carry `<template follow="exact">`. Every section heading from the template must appear in order. The Musician processes sections sequentially — skipping or reordering breaks the execution model.

### Section Vocabulary

| Section | Musician reads for |
|---|---|
| **`mandatory-rules`** | Rules to internalize before proceeding |
| **`danger-files`** | Shared resource coordination constraints |
| **`objective`** | Goal and success criteria |
| **`prerequisites`** | Pre-flight checks — fail fast if any fail |
| **`bootstrap`** | Claim SQL and monitoring setup |
| **`execution`** | Ordered implementation steps |
| **`rag-proposals`** | Proposal creation directives |
| **`verification`** | All checks must pass |
| **`testing`** | Specified test suites |
| **`completion`** | Commit, update DB, generate report |
| **`error-recovery`** | Recovery paths for failures |
| **`success-criteria`** | Final checklist before completion |

## RAG and Proposal Policy

Musicians can **query** the local-rag MCP server to search existing documents via `query_documents`. Musicians **cannot** call `ingest_data` or `ingest_file` — that authority belongs to the Conductor.

When a Musician identifies a need for new documentation, architectural decisions, patterns, or scope changes, it writes a **proposal** to `docs/implementation/proposals/`. Seven proposal types: PATTERN, ANTI_PATTERN, MEMORY, CLAUDE_MD, RAG, MEMORY_MCP, DOCUMENTATION. The Conductor evaluates proposals during review. Musicians never act on proposals unilaterally.

## Validation Scripts

Run before committing changes to the Musician skill:

| Script | Purpose |
|---|---|
| `skill/scripts/validate-musician-state.sh` | Database state consistency for active tasks |
| `skill/scripts/check-context-headroom.sh` | Context budget estimation |
| `skill/scripts/verify-temp-files.sh` | Temp file path validation |

```bash
bash skill/scripts/validate-musician-state.sh
```

## Project Structure

```
musician/
├── skill/
│   ├── SKILL.md                              # Skill definition (entry point)
│   ├── references/
│   │   ├── checkpoint-verification.md        # External verification categories
│   │   ├── database-queries.md               # SQL patterns for state management
│   │   ├── rag-proposal-template.md          # Proposal format and recognition guidance
│   │   ├── resumption-state-assessment.md    # Handoff structure and state reconciliation
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
│       ├── check-context-headroom.sh         # Context budget estimation
│       ├── validate-musician-state.sh        # Database state consistency check
│       └── verify-temp-files.sh              # Temp file path validation
└── docs/
    ├── archive/                              # Historical design documents
    ├── designs/                              # Skill design specifications
    ├── plans/                                # Implementation plans
    └── working/                              # Active design work
```

## Known Limits

- **Context estimation is approximate** — the 50/65/75% thresholds use heuristic estimation, not exact token counts. Errs conservative.
- **Single-task sessions** — each Musician session handles one task. Parallel execution is the Conductor's responsibility (multiple Musicians).
- **No direct RAG ingestion** — Musicians can query but not write to the knowledge base.
- **No user interaction** — Musicians never use `AskUserQuestion`. All communication flows through `orchestration_messages` to the Conductor.

## Planned Improvements

- Arranger integration for direct plan-to-execution pipeline
- Improved context estimation using token counting where available
- Richer handoff files for multi-session task continuity

## Usage

Launched by the Conductor in a dedicated terminal session when tasks need implementation. Can also be invoked directly via `/musician`.

## Origin

Part of [The Elevated Stage](https://github.com/The-Elevated-Stage) orchestration system. Design docs: `docs/archive/2026-02-18-musician-skill-redesign-design.md`.
