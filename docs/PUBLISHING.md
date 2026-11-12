# Publishing 73

A Neovim plugin is normally distributed as a Git repository. There is no required central package registry: plugin managers clone the repository and add it to Neovim's runtime path. `lua/` contains the API, `plugin/` registers commands, and `doc/` supplies help.

For a release:

1. Run `nvim --headless -u NONE -i NONE -l tests/smoke.lua` and review CI on the commit.
2. Update README installation/version and CHANGELOG; keep experimental limitations explicit.
3. Commit the intended source, tests, license and docs; exclude temporary files and credentials.
4. Push to GitHub and create a version tag such as `v0.1.0-alpha.1`.
5. Create a GitHub prerelease for that tag with behavior, checks and limitations.
6. Share the repository link and lazy.nvim installation snippet. Users may pin the tag, a commit, or track the default branch.

Subsequent alpha changes should get a new tag rather than moving an existing release tag. Hosted CI and hands-on backend use provide evidence beyond offline tests. A screenshot or short demo is useful for promotion but is not needed for installation.
