# Reference study: 99

Reviewed 2026-11-08 at revision c17422457027c913c76c75a921fca1e623d2678e.

The README explicitly describes a move from replacing selected code toward search/work and a Worker abstraction. It still documents visual replacement and multiple CLI providers. This confirms a direction change, not cessation of maintenance.

- [README](https://github.com/ThePrimeagen/99/blob/c17422457027c913c76c75a921fca1e623d2678e/README.md)
- [Inspected providers](https://github.com/ThePrimeagen/99/blob/c17422457027c913c76c75a921fca1e623d2678e/lua/99/providers.lua)
- [Visual bounds tests to inspect next](https://github.com/ThePrimeagen/99/blob/c17422457027c913c76c75a921fca1e623d2678e/lua/99/test/visual_context_bounds_spec.lua)

Useful patterns: provider-specific command building, separated stdout/stderr/completion, request-scoped cancellation, exactly-once completion, and native Neovim surfaces. Historical inline-edit behavior is worth studying during implementation.

The inspected provider implementation retrieves responses from a temporary file and some providers use broad permission/trust flags. 73 will instead validate proposals and retain editor-owned application. Those flags were not copied. 99's prompt completion for @files/#rules is distinct from AI code ghost text (now outside 73 scope).

## Reuse status

No 99 code copied. The recursive tree inspected at this revision had no path with a license filename. This is not a legal conclusion about the entire history, but no copying grant has been established. Until verified, use behavior as a reference and implement original code.

## Other references

- [Pi v1.5.0](https://github.com/earendil-works/pi/tree/v1.5.0)
- [Omp v18.18.0](https://github.com/can1357/oh-my-pi/tree/v18.18.0)
- [Neovim API](https://neovim.io/doc/user/api/)
- [Neovim LSP](https://neovim.io/doc/user/lsp)

Check installed-version APIs before implementation. 73 does not depend on 99.

Reviewed current upstream README on 2026-11-12: visual replacement, stop-all requests, and in-flight throbbers informed 73's interaction changes. Current 99 also emphasizes search/work. No source implementation was copied.
