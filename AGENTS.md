# Working on 73

Read README.md and docs/PRODUCT.md first; read docs/ADAPTER_CONTRACT.md before adapter changes.

- Distinguish implemented behavior from plans.
- The plugin owns snapshots, selection ranges, previews, acceptance, and undo.
- Harnesses return proposals; they do not modify workspace files during inline requests.
- Use argv process invocation, not shell interpolation of prompts.
- Do not bypass harness permissions to make an adapter work.
- Code completion is outside 73; keep it in a separate plugin.
- Use fake adapters and temporary buffers in tests; no live provider calls.
- Test stale snapshots, cancellation, malformed proposals, Unicode ranges, and undo as editing is implemented.
- Check licenses and retain notices before copying external code.
- After Lua changes run: nvim --headless -u NONE -i NONE -l tests/smoke.lua
- Do not change user Neovim configuration, install globally, commit, publish, or create remote repositories unless requested.
