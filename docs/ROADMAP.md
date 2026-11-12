# Milestones

## 0 — Bootstrap (done)

Loadable plugin, metadata registry, health/status commands, product/contract documentation, and dependency-free smoke checks. No AI integrations yet.

## 1 — Safe editor slice

Implemented: fake adapter, unsaved selection → replacement proposal → preview → accept/reject → undo. Tests cover stale buffers, cancellation/late callbacks, malformed proposals, Unicode ranges, and undo. Questions about a selection/location display read-only answers. Prompt-driven insertions capture an exact cursor anchor and share preview/accept/undo. All three operations support optional instruction prompts, with snapshots captured before prompting. Explicit byte ranges support empty replacements and zero-length insertions.

Minimum version: the full smoke suite passes locally on Neovim 0.10.0 and 0.12.6 on macOS arm64. CI is configured for Linux/macOS with 0.10.0 and stable; hosted execution is still pending. Public Ask/Edit/Insert commands, actionable capability health checks, and true whole-line acceptance are implemented. Broader interactive testing remains. No live model has been connected.

## 2 — Real adapters

Implement Pithos and one verified fallback among upstream Pi, Claude Code, or Codex. Inspect actual supported interfaces before selecting the fallback. Publish a tested capability matrix, not a list of installed executables.

Investigation completed: local Pithos remains the Pi 1.5.0 baseline. Restricted Pi RPC startup passed an offline probe; no prompt was sent. See [evidence, limitations, and the proposed adapter](BACKEND_COMPATIBILITY.md). Implemented: opt-in Pi 1.5.0 RPC adapter with fixed restricted flags, version gating, strict payload parsing, timeouts, cancellation, process-group cleanup, and fake-subprocess tests. Implemented: buffer-local progress, cancellation/status commands, one-time failure notifications, cancellation on buffer unload, and deferred results that avoid interrupting typing or newer UI (`:SeventyThreeShow`). Next: explicit live-provider acceptance testing using the [temporary-workspace procedure](LIVE_CHECK.md). No provider calls have been made by the tests.

## 3 — Richer context and explicit delegation

Existing editor LSP context, targeted retrieval, and a deliberately invoked larger-session interface. Preserve bounded behavior for ordinary Ask/Edit.

Open: first fallback backend, UI/keymaps, hosted CI results, and any licensed historical 99 code worth adapting.

Code completion is outside the project scope and belongs to a separate plugin.
