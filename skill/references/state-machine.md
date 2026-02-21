<skill name="musician-state-machine" version="2.0">

<metadata>
type: reference
parent-skill: musician
tier: 3
</metadata>

<sections>
- states-the-musician-sets
- states-the-conductor-sets
- valid-state-transitions
- guard-clause-rules
- terminal-states
</sections>

<section id="states-the-musician-sets">
<core>
# Reference: Musician State Machine

## States the Musician Sets

The musician manages its own state transitions in the orchestration database:

- **`working`** — Task has been claimed and execution is in progress
- **`needs_review`** — A checkpoint has been reached and verification tests passed; awaiting conductor approval
- **`error`** — An unrecoverable failure occurred; awaiting conductor instructions
- **`complete`** — All task steps are done and the conductor has approved completion (terminal state)
- **`exited`** — The musician has prepared a clean handoff for context exhaustion (65%+ triggers handoff prep, 75% triggers mandatory exit) or other early termination (terminal state)
</core>
</section>

<section id="states-the-conductor-sets">
<core>
## States the Conductor Sets

The conductor responds with these states:

- **`watching`** — Task created, not yet claimed by any musician
- **`review_approved`** — Checkpoint review passed; musician proceeds with next steps
- **`review_failed`** — Checkpoint review rejected; musician applies feedback and re-submits
- **`fix_proposed`** — Conductor has a specific fix or adjustment; musician applies it and re-submits
- **`exit_requested`** — Conductor requests musician to prepare handoff and exit
</core>
</section>

<section id="valid-state-transitions">
<core>
## Valid State Transitions

Musician initiates these transitions:

```
watching → working              (atomic claim succeeds at bootstrap)
working → needs_review          (checkpoint reached, tests pass)
working → error                 (unrecoverable failure, timeout)
review_approved → working       (implicit; musician resumes work)
review_approved → needs_review  (completion review after final step)
review_failed → needs_review    (re-submit after applying feedback)
fix_proposed → working          (implicit; musician resumes after fix)
fix_proposed → needs_review     (re-submit after applying proposed fix)
working → complete              (TERMINAL: after conductor approves)
working → exited                (TERMINAL: clean handoff for context exhaustion)
error → exited                  (TERMINAL: unrecoverable failure)
```
</core>
</section>

<section id="guard-clause-rules">
<core>
## Guard Clause Rules

The atomic claim uses a guard clause to prevent double-claiming:

```
WHERE state IN ('watching', 'fix_proposed', 'exit_requested')
```

States that **allow** claiming: `watching`, `fix_proposed`, `exit_requested`

States that **block** claiming: `working`, `complete`, `exited`, `review_approved`, `review_failed`, `error`, `needs_review`
</core>

<context>
The conductor always intermediates crash recovery. If a session crashes in `review_approved`, `needs_review`, `error`, or `review_failed`, the conductor detects the stale heartbeat, reviews state, sends a handoff message, and sets `fix_proposed`. New sessions only need to claim from the 3 conductor-prepared states.

If the guard blocks (no rows matched), the session cannot claim the task. Fallback: create a `fallback-{session_id}` row with state `exited` so the hook allows clean session exit.
</context>
</section>

<section id="terminal-states">
<mandatory>
## Terminal States

Once a task reaches `complete` or `exited`, it cannot transition back to an active state. These are absolute end states. The musician must treat these writes as irreversible.
</mandatory>
</section>

</skill>
