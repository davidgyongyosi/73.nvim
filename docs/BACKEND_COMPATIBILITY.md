# Backend compatibility investigation

Updated 2026-11-12. An experimental Pi RPC adapter is implemented; live inference is not verified. This report separates source inspection, offline startup checks, and work still needed before making a compatibility claim.

## Evidence

| Target | Inspected version | Evidence | Result |
|---|---|---|---|
| Installed Pi | `pi --version`: 1.5.0 | CLI help plus optional offline RPC probe | Startup interface verified; no model requests made |
| Local Pithos fork | Pi baseline `f9a26365568127461c47a07a37dcb42c140a3ac5` | Local source checkout | No fork-specific runtime behavior or native 73 proposal protocol established |
| Other harnesses | None in this investigation | None | Not verified |

The upstream baseline source references are [RPC documentation](https://github.com/earendil-works/pi/blob/f9a26365568127461c47a07a37dcb42c140a3ac5/packages/coding-agent/docs/rpc.md), [JSON events](https://github.com/earendil-works/pi/blob/f9a26365568127461c47a07a37dcb42c140a3ac5/packages/coding-agent/docs/json.md), [SDK initialization](https://github.com/earendil-works/pi/blob/f9a26365568127461c47a07a37dcb42c140a3ac5/packages/coding-agent/src/core/sdk.ts), [resource loading](https://github.com/earendil-works/pi/blob/f9a26365568127461c47a07a37dcb42c140a3ac5/packages/coding-agent/src/core/resource-loader.ts), and [RPC command types](https://github.com/earendil-works/pi/blob/f9a26365568127461c47a07a37dcb42c140a3ac5/packages/coding-agent/src/modes/rpc/rpc-types.ts). These were inspected in the local Pithos checkout at that commit. No external implementation code was copied.

## Implemented launch profile

Invoke the executable with an argv array, with these fixed arguments:

```text
--mode rpc --no-session --no-tools --no-extensions --no-mcp
--no-skills --no-prompt-templates --no-themes --no-context-files
--no-approve --offline
```

`--offline` disables startup network operations, not inference itself. It must not be described as a network sandbox. `--no-approve` declines project-local trust; do not substitute a broad approval flag. Do not append arbitrary caller arguments that can re-enable tools or extensions.

Source inspection shows `--no-tools` becomes `noTools: "all"`, producing empty initial tools and an empty tool allowlist including MCP. Disabling extensions is independently necessary: extension code can execute during loading, even without model tools. The profile also disables MCP, prompts, skills, themes, and automatic context loading. 73 should supply its own authoritative unsaved snapshot.

This is a restriction of harness features, not an OS filesystem sandbox. The RPC API still offers explicit commands such as `bash` and `export_html`; a 73 adapter must never expose or dispatch those for inline requests. Installed executables and provider implementations remain trusted software. Credential/cache writes outside the workspace are a separate concern from source-file mutation.

## Offline probe

Run explicitly, separately from the Neovim smoke suite:

```sh
python3 scripts/probe-pi-interface.py
# Optionally pass an explicit Pi executable path.
```

The probe uses temporary agent configuration and a temporary workspace, removes provider credentials and Node preload hooks from the child environment, disables startup networking/telemetry, and never sends a prompt. It queries state and available commands, sends an idle abort, and closes stdin. Test extensions would write a sentinel if discovered. Pi 1.5.0 returned successful responses, no commands or messages, no session file, exited successfully, and left workspace contents unchanged without loading those extensions.

This does **not** demonstrate actual model output, prevention of a model-triggered tool call, cancellation of an active inference, process-tree cleanup, or compatibility with a different executable version. The RPC state response does not expose the active tool list, so that part of the assessment is source-based.

## Adapter implementation and validation

1. Use one isolated RPC process per inline request initially, launched through Neovim's argv process API. Send instruction and unsaved snapshot as a JSONL `prompt` record on stdin, never as shell text or an `@file` argument. Check the supported version/profile before dispatch.
2. Parse LF-delimited records across partial chunks, accepting CRLF without treating Unicode separators as delimiters. Bound record sizes and total output; keep stderr separate.
3. Correlate command IDs. A successful `prompt` response is admission, not completion. `agent_end` can precede retries; wait for `agent_settled`, reject aborts/provider errors, and extract the final authoritative assistant message.
4. Ask for a strict answer/replacement JSON payload. The adapter should attach the captured request identity and exact requested range, rather than letting the model choose an edit location. Validate payload shape before passing it to the existing editor-owned preview pipeline.
5. On cancellation, discard late output immediately, request abort, close stdin, and enforce a bounded shutdown deadline. Verify cleanup before claiming process-tree cancellation support.
6. Test framing, malformed output, provider errors, early exit, retry sequences, timeout, cancellation, and concurrent requests with a fake subprocess. No live-provider calls belong in the test suite.

Pithos can initially use its inherited Pi RPC surface if its executable meets the verified profile. A native Pithos proposal protocol would be a later integration, not a prerequisite for proving this path. The adapter and fake-process tests are implemented in `lua/73/adapters/pi.lua` and `tests/pi.lua`. Live usability is not established by this report.

## Implemented behavior (2026-11-12)

`require('73.adapters.pi').new(opts)` supports Ask/Edit/Insert. Each request first invokes `--version` and refuses anything except `1.5.0`. It then launches the fixed restriction flags above plus a fixed system prompt and optional provider/model. No arbitrary extra arguments are accepted. Prompts are JSONL on stdin. The model returns only an `answer` or `replacement` JSON field; the adapter restores request identity and the exact range from the captured request.

The adapter accepts fragmented LF/CRLF records, requires a matching successful prompt admission, and waits for `agent_settled` plus a final assistant message with stop reason `stop`. Retry starts clear prior candidate messages. Tool execution or extension UI activity fails the request. Invalid JSON, unexpected payload fields, aborts, provider failures, early exits, and truncated output fail closed. Diagnostics are counted toward the output limit but stderr is not surfaced, to avoid echoing potentially sensitive provider output.

The total request deadline includes the version check. Default limits are 120 seconds and 4 MiB of output per subprocess. Each subprocess is launched as a separate Unix process group. On cancellation/completion/failure the adapter closes stdin (sending abort in RPC mode), ignores late output, and kills the process group after the 500 ms default grace period. Editor exit also kills the request's current process group. These mechanics are tested with fake processes including an uncooperative descendant. Descendants deliberately escaping the process group are outside this guarantee. Windows is not supported by this adapter yet.

The smoke suite exercises success for all operations, bounded insertion through editor preview/accept/undo, empty replacements, UTF-8 and Unicode line separators, partial frames, retries, version mismatch, wrong IDs, malformed/truncated output, failed admission, provider errors, tool activity, missing settlement, size limits, deadlines, cancellation, concurrent processes, and subprocess cleanup. Shell-looking instruction strings are preserved as data. All subprocesses are local fake Neovim executables; the suite does not invoke installed Pi or any provider.

Remaining: a deliberately performed live-provider acceptance check, permission behavior during a real model turn, and broader executable-version coverage. Buffer-local progress/errors and cancellation commands are now implemented. The [manual live-check procedure](LIVE_CHECK.md) is prepared but has not been performed. The existing offline startup probe remains separate from tests. Installed Pi authentication is reused only when a user explicitly invokes the experimental adapter; this implementation does not install a harness or modify credentials.
