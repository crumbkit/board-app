# The Board release in Board.app

The Mac app carries one Board release in `Contents/Resources/board`. An agent
installs it with `install`; `INSTALL.md` beside it tells the agent how.

## What a release holds

- `bin/board`, built from board, and `bin/attention-sign`, built from this
  repository.
- `plugins/<name>`: every plugin on board's main, and attention from
  board-attention, without their tests.
- `python/board-plugin`: the library board's plugins depend on by path.
- `.claude-plugin/marketplace.json`: one Claude Code marketplace, `board`,
  with the hooks of controls, plans, runs and effects, and attention-approve.
- `release.json`: the three commits, and the release id made from them.
- `install` and `INSTALL.md`, from `Install/`.

## Building one

- `bin/bundle [board-ref] [attention-ref]` writes `Bundle/board`. Each ref
  defaults to `origin/main` of `~/Code/board` and `~/Code/board-attention`;
  `BOARD_SRC` and `ATTENTION` name other checkouts. It reads them through git,
  so their working trees do not matter. It refuses to run while `Sources/` or
  `Install/` has uncommitted changes.
- The Mac app ships `Bundle/board` when it exists. `Bundle/` is not committed.
- It needs cargo, jq and the Swift toolchain.
- `Install/test` installs `Bundle/board` into a scratch home, with a stub
  `claude`, and checks the links, binaries, refusals and enabled plugins. It
  does not check that the real `claude` accepts the hook commands.

## Installing one

- Each release is copied once to `~/.local/share/board/releases/<id>`.
  Afterwards only `uv sync` writes there, a `.venv` per plugin.
  `~/.local/share/board/current` points at the installed one.
- Before it changes anything, the installer checks that every path it links
  is a link or absent. Otherwise it stops and changes nothing.
- Plugin links in `~/.local/share/board/plugins` and skill links in
  `~/.claude/skills` go through `current`, so one link switches them all.
  Plugins the release does not ship, such as a private plugin, are left alone; a link into
  `current` for a plugin the release dropped is removed.
- `board` and `attention-sign` are copied into `~/.local/bin`.
- Every bundled plugin is enabled in the personal board. Other known boards
  re-enable the plugins they already enable, which refreshes their schemas.
- `install --hooks` adds the `board` marketplace in Claude Code afresh,
  installs its plugins, then removes the GitHub `attention` marketplace.
  `bin/bundle` gives each hook plugin the version `<version>+<commits>`,
  because Claude Code caches a plugin by version.

## Not built

- attention uses board-plugin at the commit its own lock pins, from GitHub,
  not the copy in the release.
- The hook commands are tested only against a stub `claude`.

- Plugins fetch their Python packages when installed, so an install needs
  the network. attention fetches board-plugin from the private board
  repository on GitHub, so it also needs access to it.

- Old releases are never deleted.
- Bundled binaries are not signed with the app's identity.
- Nothing checks that a newer release is in a newer app.
