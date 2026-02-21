<skill name="musician-watcher-protocol" version="2.0">

<metadata>
type: reference
parent-skill: musician
tier: 3
</metadata>

<sections>
- overview
- heartbeat-mechanism
- background-watcher
- pause-watcher
- mode-transitions
- watcher-lifecycle-tracking
- message-deduplication
</sections>

<section id="overview">
<context>
# Reference: Watcher Protocol Detail

## Overview

The musician uses two watcher agents that run asynchronously to monitor for conductor messages and state changes. Both watcher modes include a heartbeat refresh mechanism to signal the musician's aliveness to the conductor.
</context>

<mandatory>
**Agent type requirement:** All watchers MUST be launched as `subagent_type="general-purpose"` agents via the Task tool. Never use Bash agents for watchers. Watchers need comms-link MCP access to query and update the orchestration database — Bash agents cannot access MCP tools, so they cannot perform database operations.

**Invariant:** A watcher must always be running while the task is active. Background watcher during execution, pause watcher during conductor wait. When either exits (message detected, state change, or timeout), the musician processes the event and immediately launches the appropriate replacement. This holds until terminal state (`complete` or `exited`).
</mandatory>
</section>

<section id="heartbeat-mechanism">
<core>
## Heartbeat Mechanism (Both Modes)

Every poll cycle, check if the task's heartbeat is older than 60 seconds. If so, update it to the current time. The conductor considers a task stale after 9 minutes without a heartbeat, so frequent heartbeat refreshes ensure the musician's liveness is always detected if the watcher is running.

If the watcher dies (session crashes), the heartbeat becomes stale and the conductor detects the failure. This mechanism is the musician's way of saying "I'm still here and working."
</core>
</section>

<section id="background-watcher">
<core>
## Background Watcher (During Active Work)

**When launched:** At bootstrap and after resuming from pause mode. Use `Task(subagent_type="general-purpose", run_in_background=True)`.

**Runs:** In the background while the musician performs implementation work.

**Polling cycle:**
1. Query the database for new messages from the conductor addressed to this task
2. Check the task's heartbeat age and refresh if older than 60 seconds
3. Sleep for 15 seconds
4. Repeat

If a new message is detected, the watcher immediately exits. The musician detects the watcher exit, reads the message from the database, decides whether to interrupt current work (urgent) or continue (informational), and immediately relaunches the background watcher.

**Key behavior:** The background watcher uses message ID-based tracking to avoid processing the same message twice. After querying and processing a message, it updates its internal state to track that message ID, then only queries for messages with higher IDs on subsequent polls.
</core>
</section>

<section id="pause-watcher">
<core>
## Pause Watcher (During Conductor Wait)

**When launched:** When the musician sets its state to `error` or `needs_review` and must wait for an conductor response. Use `Task(subagent_type="general-purpose")` (foreground, NOT `run_in_background`).

**Runs:** In the foreground, blocking the musician from proceeding.

**Polling cycle:**
1. Query the task state from the database
2. Check the task's heartbeat age and refresh if older than 60 seconds
3. Sleep for 10 seconds
4. Repeat until state change

The pause watcher exits when the task's state changes to something other than `error` or `needs_review`. This is how the musician detects that the conductor has responded. Once detected, the watcher exits. The musician then reads the new state and latest message from the database.

**Timeout behavior:** If the pause watcher has been waiting more than 15 minutes, before declaring the conductor unresponsive, it checks the conductor's own heartbeat. If the conductor's heartbeat is fresh (within 9 minutes), the conductor is alive but busy, so the watcher continues waiting. If the conductor's heartbeat is stale (older than 9 minutes), the conductor may have crashed, and the watcher returns a timeout indicator so the musician can escalate.
</core>
</section>

<section id="mode-transitions">
<core>
## Mode Transitions

**Working → Pause (checkpoint or error reached):**
1. Musician sets state (`needs_review` or `error`) and sends a message
2. Terminate the background watcher if running
3. Exit all active subagents to free resources
4. Launch the pause watcher in foreground mode
5. Musician blocks until pause watcher returns

**Pause → Resume (conductor responds):**
1. Pause watcher detects state change and exits
2. Musician processes the response (apply feedback, adjust scope, etc.)
3. Launch a new background watcher
4. Resume execution

**Timeout handling:**
1. If pause watcher times out after 15 minutes, check conductor health first
2. If conductor is alive but slow: retry the pause watcher
3. If conductor appears down: update temp/ status files, set state to `error`, send timeout message, and relaunch pause watcher for recovery
4. If timeout happens twice: write HANDOFF, exit cleanly
</core>
</section>

<section id="watcher-lifecycle-tracking">
<core>
## Watcher Lifecycle Tracking

Maintain two variables to track watcher task IDs: `background_watcher_id` and `pause_watcher_id`. Before launching any new watcher, terminate all previous watchers using the Task tool's stop capability. This ensures clean lifecycle management and prevents orphaned watchers.
</core>

<mandatory>
**Critical rule:** Never have two watchers of the same type running simultaneously. Each transition between modes must explicitly terminate the old watcher before launching the new one.
</mandatory>
</section>

<section id="message-deduplication">
<core>
## Message Deduplication

The background watcher must deduplicate messages to avoid processing the same message twice. Instead of using timestamps (which can be identical for multiple messages), use message ID (auto-incrementing integer).

**Implementation:**
- Track `last_processed_message_id` as an integer, initialized to 0
- Query for messages where `id > last_processed_message_id`
- After processing each message, update `last_processed_message_id` to that message's ID

This approach is safer than timestamp-based tracking because message IDs are guaranteed unique and monotonically increasing, avoiding race conditions where identical timestamps cause messages to be missed or processed twice.
</core>
</section>

</skill>
