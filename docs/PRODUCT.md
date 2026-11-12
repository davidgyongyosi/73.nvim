# Product scope

A developer edits Go and TypeScript/TSX in Neovim: select code, ask a question or request a precise change, review the proposal, and keep editing. Small questions must not become autonomous implementations. Pithos is preferred but not required.

## Required interactions

| Action | Expected behavior | Acceptance criteria |
|---|---|---|
| Ask about selection/location | Explain using supplied code and relevant project context | No mutation, no forced save; unsaved buffer included |
| Edit selection | Propose a bounded replacement | Preview by default; optional automatic acceptance; one undo step; surrounding text unchanged |
| Insert at cursor | Propose new code from an instruction | Exact insertion anchor; preview; no automatic save |
| Delegate, later | Separate inspectable engineering session | Explicit activation; bounded Ask/Edit never silently escalates |

## Editor correctness

Record buffer identity, changedtick, content identity, selection, cursor, and project root before dispatch. The unsaved buffer is authoritative; disk content is not an acceptable substitute. Coordinates are zero-based UTF-8 byte positions with exclusive ends; convert LSP position encodings explicitly. Preserve charwise/linewise selection semantics and Neovim's inclusive/exclusive selection setting. Initially refuse blockwise selections rather than silently widening scope.

Reject proposals if the buffer changed, unloaded, or no longer matches the snapshot. Streaming content is preview only. Acceptance (explicit by default, automatic when enabled) uses Neovim APIs, does not save, and creates one undoable change. Cancellation is per-request; late responses cannot mutate code or supersede newer UI.

## Context

Use selected/enclosing code, prefix/suffix, filetype, recent edits, relevant open buffers, existing Neovim LSP facts/diagnostics, then targeted repository retrieval. Track origin and revision. Budget context; do not send the entire repository on each keystroke. Resolve root from the originating buffer, not just global cwd.

## Out of scope

Email, calendar, phone notifications, replacing Neovim, automatic multi-file work for an inline request, and code completion. A dedicated completion plugin may run alongside 73.

## Measurements

Evaluate real Go/TSX work: time to first suggestion, acceptance and stale/discard rates, and typing disruption. Set numerical targets after measuring a baseline.
