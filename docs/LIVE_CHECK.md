# Deliberate live acceptance check

This procedure is manual and separate from the offline smoke suite. It has **not been performed yet**. It sends synthetic fixture code to the configured Pi provider only when an Ask/Edit/Insert mapping is invoked; ordinary provider charges may apply. The demo uses existing Pi authentication and does not change it.

From the 73 repository, start a fresh Neovim with no user configuration:

```sh
nvim -u NONE -i NONE -c "lua dofile('scripts/live-check.lua')"
```

Optionally set `SEVENTYTHREE_MODEL` to an existing Pi model identifier before launching. Otherwise the adapter uses Pi's configured default. Pi must report version 1.5.0. Opening the demo itself performs no provider request.

The script creates a temporary directory and a small Lua fixture. Its first line on disk says `disk-73`, while the unsaved buffer says `unsaved-73`. The working directory is that temporary directory. Only this synthetic document is sent, not this repository. No mappings are installed in your user configuration. The default leader in this clean session is backslash.

1. Press `<leader>7a` and ask: “What is the exact string value assigned to marker?” Expect an answer describing `unsaved-73`. Close it with `q`. Run `:SeventyThreeCheckDisk`; the fixture must be unchanged.
2. Visually select the function, press `<leader>7e`, and request subtraction instead of addition. Inspect the preview, reject with `q`, and verify the source buffer is unchanged.
3. Repeat the edit, accept with `a`, then press `u` in the source buffer. One undo must restore the prior text. Run `:SeventyThreeCheckDisk` again; acceptance must not save.
4. Move to an insertion point, press `<leader>7i`, and ask for a short Lua comment. Review its exact location, accept, and undo. Recheck disk.
5. Start an Ask and run `:SeventyThreeCancel` before completion. Expect cancelled status and no late answer. Repeat an Edit but change the source while waiting. Expect a stale-buffer failure and no applied change.
6. Start a request, move the cursor or switch buffers, and wait. The result must not steal focus. Return to the source in normal mode and run `:SeventyThreeShow`. If the source changed after the result arrived, opening it must fail as stale.
7. Inspect `:SeventyThreeStatus` after each failure or cancellation. Working/prompting text should clear. Do not save the fixture during these checks.

Record Neovim, OS, Pi, provider/model, operations attempted, observed output/latency, disk checks, cancellation, and failures. Do not mark the adapter verified based only on a successful answer. In particular this manual test is evidence for the observed runs, not a general proof of model/tool permission enforcement.

Exit with `:qa!`. The temporary directory is left available for inspection until normal temporary-file cleanup. Nothing is committed, published, or installed by this procedure. Automated tests remain `nvim --headless -u NONE -i NONE -l tests/smoke.lua` and use only fake adapters/processes.
