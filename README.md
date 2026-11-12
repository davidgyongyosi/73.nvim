# 73.nvim

AI assistance at the cursor. Keep your hands on the code.

73 is a Neovim plugin project for selection questions, inline replacements, prompt-driven insertions. The editor experience belongs to 73; the harness is interchangeable. The name comes from fitting an arrow to a bowstring: prepare a precise change, then choose when to release it.

## Current status

**v0.1.0-alpha.2 — Ask/Edit/Insert with experimental Claude Code and Pi adapters.** 73 owns unsaved-buffer snapshots, bounded proposals, unified-diff previews, explicit acceptance, cancellation, and undo. A fake adapter supports offline development. The Claude Code adapter defaults to Sonnet with tools disabled; Pi supports its inspected 1.5.0 profile. Automated tests use fake transports; live-provider validation remains pending.

Code completion is outside 73's scope. Use a dedicated Neovim completion plugin alongside it; 73 installs no insert-mode completion hooks or mappings.

Implemented adapters: Claude Code and upstream Pi 1.5.0. Native Pithos and Codex integrations remain planned. Additional harnesses can implement adapters. Installed executables alone do not establish compatibility.

## Install the alpha

Requires Neovim 0.10+ and an authenticated Claude Code CLI on PATH for this example. Model inference uses your existing account and may incur usage costs. The alpha API may change. Code completion is supplied by your separate plugin.

```lua
-- lazy.nvim
{
  'davidgyongyosi/73.nvim',
  tag = 'v0.1.0-alpha.2',
  config = function()
    local ai = require('73')
    ai.register_adapter('claude', require('73.adapters.claude').new({ model = 'sonnet' }))
    ai.setup({ harness = 'claude', parallel = true, auto_apply = false })
    -- Optional mappings; use a prefix free in your configuration.
    vim.keymap.set('x', '<leader>aiv', function() ai.edit() end, { desc = '73 Edit selection' })
    vim.keymap.set('n', '<leader>aia', function() ai.ask() end, { desc = '73 Ask' })
    vim.keymap.set('n', '<leader>aix', ai.cancel_all, { desc = '73 Cancel all' })
  end,
}
```

Run `:checkhealth 73`, then try `:SeventyThreeAsk Explain this code` in a scratch buffer. Select code and invoke the visual edit mapping, or use `:SeventyThreeEdit` for the current line. Review the diff and press `a` to accept or `q` to reject. Accepted edits are undoable and never save automatically. `:SeventyThreeProvider` selects among registered adapters. Auto-apply is opt-in via `:SeventyThreeAutoApply`.

Report problems through [GitHub issues](https://github.com/davidgyongyosi/73.nvim/issues), including Neovim/OS/harness versions, relevant configuration, and a minimal reproduction. Remove credentials and private source from reports.

## Local development

Neovim 0.10+; the full smoke suite passes locally on 0.10.0 and 0.12.6 (macOS arm64). A Linux/macOS CI matrix for 0.10.0 and stable is configured, but hosted runs have not occurred yet. No third-party Lua dependencies.

```lua
-- lazy.nvim local development entry
{
  dir = vim.fn.expand('~/Projects/73.nvim'),
  config = function()
    require('73').setup({})
  end,
}
```

Run `:SeventyThreeInfo` or `:checkhealth 73`. Use `:SeventyThreeStatus` for the current buffer’s latest request and `:SeventyThreeCancel` to cancel it. These also work inside its preview. Use `:SeventyThreeShow` to open a result that is waiting for review. No default mappings are installed.

```sh
# From this repository; no network or user configuration required.
nvim --headless -u NONE -i NONE -l tests/smoke.lua
```

## Planned workflow

Select code and ask a question without source changes. Select code and request a replacement, then preview and accept/reject it. Place the cursor and describe an insertion. Explicitly open a larger delegated session only when wanted.

Unsaved buffers are authoritative. Responses must not overwrite newer changes. Accepting a proposal creates one undoable edit and does not save automatically.

## Commands

After selecting a harness, these work without custom mappings:

| Command | Scope |
|---|---|
| `:SeventyThreeAsk [instruction]` | Current cursor; an explicit Ex range selects whole lines |
| `:SeventyThreeEdit [instruction]` | Current whole line, or an explicit Ex range such as `:10,15SeventyThreeEdit` |
| `:SeventyThreeInsert [instruction]` | Captured cursor position; no Ex range |
| `:SeventyThreeStatus`, `:SeventyThreeCancel`, `:SeventyThreeShow` | Inspect, cancel, or open the current source buffer's result |

Omit the instruction to open a prompt. Ex ranges always select complete lines, including ranges entered from visual mode. For an exact characterwise selection, use the Lua visual mappings below. Linewise acceptance replaces whole lines: an omitted final newline cannot join the next source line, and an empty replacement deletes the selected lines. Characterwise edits retain their exact byte-range behavior.

`:checkhealth 73` reports selected callbacks, fake adapters, and Pi executable availability without launching a process or checking credentials. Finding an executable is not a claim of provider readiness; the Pi version gate still runs when a request starts.

## Try the editing slice locally

After loading the plugin, run this Lua in a scratch session (it does not need to go in your config):

```lua
local seventy_three = require('73')
seventy_three.register_adapter('demo', require('73.adapters.fake').new('replacement text'))
seventy_three.setup({ harness = 'demo' })
vim.keymap.set('x', '<leader>73', function()
  _G.last_73_edit = seventy_three.edit()
end)
vim.keymap.set({ 'n', 'x' }, '<leader>7a', function()
  _G.last_73_request = seventy_three.ask()
end)
vim.keymap.set('n', '<leader>7i', function()
  _G.last_73_request = seventy_three.insert()
end)
```

Select text characterwise or linewise and press `<leader>73`, then enter an instruction. The fake adapter always proposes `replacement text`; it does not interpret your instruction. The preview shows a unified diff. Press `a` to accept or `q` / Escape to reject. Closing the preview also rejects it. Use normal `u` in the source buffer to undo an accepted change. Blockwise selections are refused.

Use `<leader>7a` to ask about a selection or cursor, or `<leader>7i` to propose an insertion immediately before the cursor character. The fake answer explicitly says no model was called. Question windows have only close actions. All three methods accept an instruction string to skip the prompt; dismissing or submitting an empty prompt cancels the request. The original buffer and range are captured before prompting, and changes while prompting invalidate the request.

Prompting and pending requests show a short virtual-text indicator in the source buffer; this does not change source text or undo history. Failures notify once and remain available through `:SeventyThreeStatus`. Unloading the source buffer cancels its active request.

A response opens automatically only when it belongs to the newest request and you are still in the original window, buffer, and cursor position in normal mode. Otherwise it waits with a “result ready” indicator. Return to its source buffer and run `:SeventyThreeShow`; opening it rechecks snapshot freshness. A ready proposal cannot be accepted until its preview has opened.

For development, the returned handle offers `status()`, `cancel()`, `reject()`, `show()`, and `accept()`; answers also support `close()`. `status()` returns the state and an optional failure message. With parallel mode disabled, a new request in the same buffer cancels its predecessor. No default mappings are installed. The fake adapter starts no processes; the Pi adapter starts a process only when explicitly requested.

## Experimental Pi adapter

The adapter currently supports **Pi 1.5.0 on Linux/macOS** and refuses other version strings. Its subprocess behavior is tested with fake executables, including cancellation and descendant cleanup. No real model turn has been verified yet. It uses your existing Pi authentication and model selection; provider inference may incur costs. Setup itself does not launch Pi or send code.

```lua
local seventy_three = require('73')
seventy_three.register_adapter('pi', require('73.adapters.pi').new({
  executable = 'pi',
  -- model = 'your-provider/your-model', -- optional; otherwise Pi's configured default
  timeout_ms = 120000,
}))
seventy_three.setup({ harness = 'pi' })
```

Use the Ask/Edit/Insert mappings above after configuring this adapter. Each operation checks `--version`, then starts a separate RPC process with tools, extensions, MCP, context-file discovery, and session persistence disabled. Code and instructions travel over stdin. This restricts harness features; it is not an OS filesystem sandbox. Only the current unsaved document and instruction are supplied; repository retrieval and conversations are not implemented.

Model output must be a strict JSON answer or replacement. Invalid output fails without opening a proposal; use `:SeventyThreeStatus` for the reason. Options also include `provider` (requires `model`), `shutdown_ms` (default 500), and `max_output_bytes` (default 4 MiB across stdout/stderr per subprocess). Arbitrary CLI flags are deliberately unsupported. A Pithos executable can use this adapter only if it still exposes the inspected Pi 1.5.0 profile; native Pithos proposals are not implemented.

A [manual live-check procedure](docs/LIVE_CHECK.md) opens a synthetic temporary workspace without your Neovim config. Opening it does not send a request; the check has not yet been performed.

## Documentation

- [Product and acceptance criteria](docs/PRODUCT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Draft adapter contract](docs/ADAPTER_CONTRACT.md)
- [Milestones](docs/ROADMAP.md)
- [Backend compatibility investigation](docs/BACKEND_COMPATIBILITY.md)
- [99 reference study](docs/REFERENCES.md)
- [Development rules](AGENTS.md)

This project is independently publishable from Pithos. All scaffold code is original; no 99 or Omp implementation was copied. MIT license applies to the new scaffold. No package-name availability is claimed.

## Automatic acceptance

`setup({ harness = 'pi', auto_apply = true })` enables automatic acceptance for future Edit/Insert requests. Default is false. `:SeventyThreeAutoApply` toggles it; a per-request `auto_apply = false` retains preview. Automatic edits remain bounded to the captured selection, reject stale buffers, create one undo step, and never save. Ask remains read-only. Working indicators animate and show elapsed seconds.

Parallel selections: `setup({ harness = 'pi', parallel = true })` allows several selection requests in the same buffer. Non-overlapping proposals are rebased only across changes accepted by 73; original response identity is still validated. Overlapping targets are cancelled, and unrelated buffer changes remain stale. Each accepted proposal has a separate undo boundary. `:SeventyThreeCancelAll` cancels outstanding work across buffers. Without `parallel`, a new same-buffer request supersedes the previous one.

Automatic acceptance is opt-in through `auto_apply = true` or `:SeventyThreeAutoApply`. It applies only validated Edit/Insert proposals, never saves, and preserves stale-buffer checks and undo. Per-request `auto_apply = false` forces review. Pending requests show an animated indicator with elapsed seconds. Requests capture their acceptance policy when started; toggling affects future requests.

## Switching providers

Register `claude` with `require('73.adapters.claude').new({ model = 'sonnet' })` and retain any Pi descriptor. Configure `setup({ harness = 'claude', parallel = true })`. `:SeventyThreeProvider` opens the provider picker; `:SeventyThreeProvider pi` switches directly. Selection affects future requests; in-flight requests retain their original adapter. Auto-apply settings are preserved.

The experimental Claude adapter uses existing Claude authentication, disables model tools, and returns structured answers/replacements over stdout. It sends the authoritative unsaved snapshot over stdin, with output limits, a deadline, cancellation, and no permission-bypass flags. Tests use fake transport; actual Claude inference remains unverified.
