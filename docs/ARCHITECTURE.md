# Architecture

```text
Neovim buffers / selections / existing LSP clients
                     |
             context snapshots
                     |
          capability + request routing
                     |
       conversational adapter (Pithos / Pi / other)
                     |
             answers / proposals
                     |
       73 preview, acceptance, undo
```

73 owns editor state, UI, request identity, lifecycle, and application of changes. Harnesses own reasoning and permitted tools. Each adapter translates a verified supported interface; a CLI executable name is not a protocol.

Current implementation: adapter registration/selection, unsaved-buffer snapshots, UTF-8 byte range validation, a local Lua Ask/Edit/Insert request callback, cancellation/supersession, read-only answers, instruction prompts, replacement/insertion previews, freshness checks, and explicit acceptance with undo. Supplied adapters are an opt-in fake and an experimental restricted Pi 1.5.0 RPC implementation. Live inference has not been verified. Pi transport handles framing, bounded output, deadlines, and Unix process-group cleanup. Code completion is provided by a separate plugin.

An adapter advertises only demonstrated capabilities. If it cannot prevent direct source writes, it cannot advertise safe inline editing merely because a prompt says not to write. Use a verified restricted mode or deliberate isolation; otherwise omit the capability. Ask also requires no-write behavior.

73 should reuse Neovim's existing language servers. Detached delegated sessions may need their own servers later; do not spawn duplicates for every inline request.

## Adapter targets

| Backend | Planned integration | Current status |
|---|---|---|
| Pithos | Initially inherited Pi RPC; native proposals later | Inherited Pi profile can use experimental adapter; no native integration |
| Upstream Pi | Restricted RPC process per request | 1.5.0 adapter implemented and fake-process tested; no live model turn verified |
| Claude Code | Verified structured/noninteractive interface | Planned |
| Codex | Verified programmatic interface | Planned |
| Others | Third-party adapters | Local Lua Ask/Edit/Insert callback; no verified external integrations |

Keep tested executable versions, permissions, cancellation, streaming, and session semantics in each adapter's compatibility record.

See [backend compatibility evidence](BACKEND_COMPATIBILITY.md) for the inspected Pi baseline, restricted launch profile, and remaining runtime checks.
