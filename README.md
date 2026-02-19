# Musician

Executes phased task instructions in an external Claude session. The Musician is the implementation tier in a three-tier orchestration model: Conductor (coordination) > **Musician** (implementation) > Subagents (focused work).

## What It Does

- Bootstraps into a task by claiming it atomically via the orchestration database
- Processes task instruction files phase-by-phase
- Delegates focused work to subagents; retains integration and cross-cutting work
- Monitors context usage and checkpoints progress for resumption
- Communicates status and review requests back to the Conductor
- Supports clean exit and mid-session resumption

## Structure

```
musician/
  SKILL.md              # Skill definition (entry point)
  docs/archive/         # Historical design documents and redesign notes
  examples/             # Bootstrap, checkpoint, resumption, error recovery examples
  references/           # State machine, subagent delegation, watcher protocol
  scripts/              # Context headroom checks, state validation, temp file verification
```

## Usage

Launched by the Conductor in a dedicated terminal session. Reads task instruction files from `docs/tasks/` and operates autonomously until completion or checkpoint.

## Origin

Design docs: [kyle-skills/orchestration](https://github.com/kyle-skills/orchestration) `docs/designs/sequential-task-design.md`, `parallel-task-design.md`
