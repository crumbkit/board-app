# Installing a release

- Each release is copied once to `~/.local/share/board/releases/<id>`.
  Afterwards only `uv sync` writes there, a `.venv` per plugin.
  `~/.local/share/board/current` points at the installed one.
- Before it changes anything, the installer checks that `uv` and
  `~/.local/bin` are on `PATH`, and that every path it links is a link or
  absent. Otherwise it stops and changes nothing.
- Plugin links in `~/.local/share/board/plugins` and skill links in
  `~/.claude/skills` go through `current`, so one link switches them all.
  Plugins the release does not ship are left alone; a link into
  `current` for a plugin the release dropped is removed.
- `board` and `attention-sign` are copied into `~/.local/bin`. A different
  copy already there is kept as `~/.local/share/board/<name>.prev`.
- Every bundled plugin is enabled in the personal board. Other known boards
  re-enable the plugins they already enable, which refreshes their schemas.
- `install --hooks` adds the `board` marketplace in Claude Code afresh,
  installs its plugins, then removes the GitHub `attention` marketplace.
- When another `board` comes before `~/.local/bin` on `PATH`, the install
  ends with an error, since the old `board` would still run.

## Not built

- Plugins fetch their Python packages when installed, so an install needs
  the network. attention fetches board-plugin from the private board
  repository on GitHub, so it also needs access to it.
- attention uses board-plugin at the commit its own lock pins, from GitHub,
  not the copy in the release.
- Old releases are never deleted.
