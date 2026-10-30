# Installing Board from Board.app

This directory is one Board release. `release.json` names the commits it was
built from. Run `install` from here to install it or to replace an older one:

```bash
/Applications/Board.app/Contents/Resources/board/install
```

## What it changes

- Copies the release to `~/.local/share/board/releases/<id>` once, gives
  each plugin a `.venv` there with `uv sync`, and points
  `~/.local/share/board/current` at it.
- Points `~/.local/share/board/plugins/<name>` at each plugin, and
  `~/.claude/skills/<name>` at each plugin that has a `SKILL.md`. Plugins it
  does not ship, such as one from another repository, stay as they are. A link
  into `current` for a plugin this release no longer ships is removed.
- Installs `board` and `attention-sign` in `~/.local/bin`. It keeps each
  replaced binary as `~/.local/share/board/<name>.prev`.
- Enables every plugin in the personal board. In each other board that
  `~/.config/board/config.json` lists, it re-enables the plugins that board
  already enables, so their schemas match the new plugins. Each change is a
  commit on the branch that board has checked out.

`install --hooks` also installs the Claude Code hooks from a marketplace named
`board`. It removes the `attention` marketplace from GitHub, which this
replaces, after the new hooks are in. It changes Claude Code's settings, so
ask the owner before you run it.

## Before you run it

- `uv` must be on `PATH`, and so must `~/.local/bin`.
- It needs the network, and access to the crumbkit/board repository on
  GitHub, which attention fetches a package from.
- Check what is installed now: `board --version`, and
  `ls -l ~/.local/share/board/plugins`.

## When it stops

- `<path> is not a link`: something other than this installer put a file
  there. Nothing was changed. Show the owner the path. Do not delete it.
- `<path> comes before ~/.local/bin/board on PATH`: an older binary, often in
  `~/.cargo/bin`, runs first. Show the owner the path.
- A `plugin enable` error names its code and the next step. Follow it, then
  run `install` again. Running it again is safe.

## After it runs

- Check with `board plugin list --fields name,description`.
- Older releases in `~/.local/share/board/releases`
  and the old source clone under `~/.local/share/board/src/` can be deleted once the
  owner agrees.
