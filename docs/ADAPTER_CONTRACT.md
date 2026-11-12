# Draft adapter contract v0

The wire protocol and streaming events below remain a design specification. The first editor slice implements a smaller local Lua callback described at the end of this document. This document is the initial shared source of truth for 73 and Pithos.

## Capabilities

Independent booleans: ask, edit, insert, stream, cancel, sessions, project_context, unsaved_buffers. Include adapter/version/protocol identity and executable availability. Missing capabilities fail explicitly. Public compatibility claims require conformance tests.

## Request

```json
{
  "protocol": "73/0",
  "id": "unique-request-id",
  "operation": "edit",
  "instruction": "Handle an empty result explicitly",
  "workspace_root": "/project",
  "document": {
    "uri": "file:///project/service.go",
    "filetype": "go",
    "revision": 42,
    "content_hash": "sha256-of-exact-buffer-text",
    "text": "exact unsaved buffer text",
    "range": {"start": [10, 0], "end": [15, 0]},
    "cursor": [10, 0]
  },
  "context": [],
  "session_id": null
}
```

Zero-based UTF-8 byte coordinates; exclusive end. Insertions have equal endpoints. Revision echoes the editor's changedtick. The local implementation hashes buffer lines joined by LF, with one final LF when the buffer's `endofline` option is set; disk encoding and `fileformat` do not alter this canonical text. Each context snippet carries origin, revision where available, and selection reason. Buffer numbers remain editor-local.

## Events

- started: admitted request and optional negotiated session identity.
- text_delta: provisional answer/explanation, never source edits.
- proposal: request/document/revision/hash plus one range and replacement text in the first milestone.
- completed: final answer/proposal reference and optional usage.
- failed: machine-readable code and human-readable error.
- cancelled: terminal acknowledgement; late proposals are discarded even before acknowledgement.

Exactly one terminal event. Handle partial frames, malformed replies, process exit, concurrent requests, and output after cancellation. Protocol stdout must not contain diagnostic logging.

## Ownership

The harness uses supplied unsaved content and returns answers/proposals without writing workspace files for inline operations. It must disclose inability to honor that restriction. 73 validates request identity, bounds, UTF-8 boundaries, and snapshot freshness, then previews. Only explicit editor acceptance applies changes, without saving. No multi-file edits in v0. Ordinary Ask is also no-write. Delegated orchestration is a separate explicit later operation.

Cancellation affects only the owning request/process tree.

## Required conformance cases

Unsaved text; changed/unloaded buffers; multibyte ranges; wrong IDs; malformed framing; empty replacements; zero-length insertions; out-of-scope writes; cancellation and late output; process failures; concurrent buffers; exactly-once terminal events; one-step undo; no forced save.

## Implemented local request callback

Register a descriptor with the supported operation capabilities (`ask`, `edit`, `insert`) set to true and `request(request, respond)`. Each operation checks its own capability.
`request` receives a deep copy of the request above (without `session_id`); context is currently empty. It returns an optional cancellation function and calls `respond(proposal, error)` at most once. The callback can run synchronously or asynchronously; 73 schedules validation and preview onto Neovim's main loop. Duplicate and late callbacks are ignored. This is a trusted in-process Lua interface, not a sandbox for third-party Lua code.

A proposal contains `id`, `uri`, `revision`, `content_hash`, `range`, and string `replacement`. Identity fields must echo the request document, and the range must match the requested range exactly. Empty replacement strings are valid. Answers and replacements must contain valid UTF-8 without NUL bytes; malformed sequences, overlong encodings, surrogates, and code points above U+10FFFF are rejected before rendering or insertion. The Pi adapter now implements restricted subprocess transport, output limits, a request deadline, and bounded process-group shutdown. It uses the inspected Pi no-tools/no-extension profile; this is not an OS sandbox. Live inference is not yet verified. Streaming content is not displayed.

`require('73').edit(instruction, { range = range })` originates in the current buffer. Omit options to capture the active visual selection. The returned handle exposes `status()` (state plus optional error), `accept()`, `reject()`, `cancel()`, and `show()`. Edit/Insert states are `prompting`, `pending`, `ready`, `preview`, `accepted`, `cancelled`, and `failed`. Acceptance is allowed only from `preview`, against an unchanged, loaded, modifiable source buffer. Cancelling one buffer does not cancel another buffer's request.

Ranges use existing lines and byte columns through the line's byte length; a row beyond the last buffer line is not accepted. Linewise selections end at the next line's column zero when available, or at the final line's end. The buffer's final-newline option is preserved. `document.selection` is `line` for visual-line or Ex-line selections and `character` for exact byte ranges. Linewise proposals still echo the exact range, but acceptance uses whole-line replacement: one terminating LF is stripped from the supplied line list, no LF is required to preserve the following source line, and an empty replacement deletes the selected lines. The original line bounds remain editor-owned. Advanced Lua callers can supply `opts.linewise = { first = zero_based_first_row, last = exclusive_row }` together with a matching `opts.range`; mismatched bounds are refused. Root detection searches ancestors of the originating file for `.git`, falls back to its directory, and uses the current directory for unnamed buffers. Replacement previews show a unified diff with three context lines, including insertion/deletion and missing-final-newline markers.

`ask(instruction, opts)` captures a visual selection when active, otherwise a zero-length cursor range. Answers echo `id`, `uri`, `revision`, and `content_hash`, and contain string `answer` instead of `replacement`; responses containing a replacement are rejected. Fresh answers appear in a read-only scratch window with no accept mapping. The handle enters `answered`; `close()` transitions it to `closed`. Ask never applies source edits. Stale answers are discarded before display.

`insert(instruction, opts)` captures a zero-length range at the cursor (immediately before the character in normal mode). An explicit `opts.range` must also be zero-length. Cursor movement does not move the captured anchor; source changes invalidate it. Insert uses the same proposal format, preview, explicit acceptance, and undo behavior as Edit.

Omitting `instruction` in any of the three methods opens `vim.ui.input`. The source snapshot and range are captured before opening the prompt. Nil or whitespace-only input cancels. Changes while prompting cause failure before adapter dispatch. Requests share one per-buffer lifecycle across Ask/Edit/Insert, including prompts. A superseded prompt callback cannot dispatch a request. The adapter is selected when the operation starts, not when the prompt finishes. Prompting/pending requests show source-buffer virtual text without changing the snapshot. Failures notify once. `:SeventyThreeStatus` and `require("73").request_status()` expose the latest per-buffer state and error; `:SeventyThreeCancel` and `require("73").cancel()` cancel its current request, including from its preview. Unloading the source buffer cancels pending work immediately. Status records retain only request ID, operation, state, and error; buffer wipe removes them.

A validated response enters `ready` before display. Auto-opening requires the newest global request, the original window/buffer/cursor, and normal mode. A background, older, or typing-time response remains ready without changing focus. `:SeventyThreeShow`, `require('73').show()`, or `handle.show()` opens it from the source buffer in normal mode, after another freshness check. Ready answers become `answered`; ready proposals become `preview`. Acceptance while ready is refused. Cancellation, supersession, or buffer unload discards ready results as well as pending ones. Returning to the source does not auto-open a deferred result.

## Public commands and diagnostics

`:SeventyThreeAsk [instruction]` uses the current cursor unless an Ex line range is supplied. `:SeventyThreeEdit [instruction]` uses the current whole line by default, or the supplied line range. `:SeventyThreeInsert [instruction]` uses the cursor and does not accept a line range. Missing instructions use the same snapshot-before-prompt lifecycle as Lua calls. Ex ranges never infer characterwise marks; exact visual selections continue to use the Lua API. Setup errors at command entry are reported as warnings instead of escaping the command callback.

Descriptors may include an optional `metadata` table. Built-in fake adapters identify themselves as development-only; Pi identifies the executable and inspected version. `status().selected` exposes copies of the selected descriptors' advertised capabilities, implemented callback availability, and metadata. Implementation availability means only that the required local callback exists for that advertised operation, not that a provider has been verified. Health checks inspect these fields and executable availability without starting a process or accessing provider credentials.


Parallel selections: `setup({ harness = 'pi', parallel = true })` allows several selection requests in the same buffer. Non-overlapping proposals are rebased only across changes accepted by 73; original response identity is still validated. Overlapping targets are cancelled, and unrelated buffer changes remain stale. Each accepted proposal has a separate undo boundary. `:SeventyThreeCancelAll` cancels outstanding work across buffers. Without `parallel`, a new same-buffer request supersedes the previous one.

Automatic acceptance is opt-in through `auto_apply = true` or `:SeventyThreeAutoApply`. It applies only validated Edit/Insert proposals, never saves, and preserves stale-buffer checks and undo. Per-request `auto_apply = false` forces review. Pending requests show an animated indicator with elapsed seconds. Requests capture their acceptance policy when started; toggling affects future requests.

Claude uses `--print --output-format json --json-schema ... --tools ""` with normal permission mode and no session persistence. The prompt snapshot is sent over stdin. Structured answers/replacements are validated before request identity is attached. The experimental adapter has bounded output, a timeout, cancellation, and editor-exit cleanup; fake transport tests do not establish real model compatibility.

`select_provider(name)` switches among registered request implementations without resetting editor options. `providers()` lists selectable names. `:SeventyThreeProvider [name]` selects directly or opens a picker. In-flight requests retain their selected adapter.
