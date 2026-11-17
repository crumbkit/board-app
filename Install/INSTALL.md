# Installing Board from Board.app

This directory is one Board release. `release.json` names the crumbkit/board
and board-app commits it was built from. Board.app offers to install it when
the app opens and `~/.local/share/board/current` names another release. To
install it by hand, or to replace an older one, run `install` from here:

```bash
/Applications/Board.app/Contents/Resources/board/install
```

## What it changes

1. Checks this Mac, and stops before it changes anything when a check fails.
   `docs/bundle-install.md` in board-app lists the checks.
2. Copies the release to `~/.local/share/board/releases/<id>` once.
3. Installs `board` and `attention-sign` in `~/.local/bin`, keeping each
   replaced binary as `~/.local/share/board/<name>.prev`. Every Board plugin
   is built into `board`, so it removes the plugin links an older release
   made in `~/.local/share/board/plugins`, and the links of the Python
   attention plugin from stemmacorp/board-attention. It leaves every other
   link there alone.
4. Removes the skill links an older release made in `~/.claude/skills`, then
   runs `board skills install`, which writes the skills that match the new
   `board`.
5. Enables every built-in plugin in the personal board. In each other board
   that `~/.config/board/config.json` lists, it enables again the built-in
   plugins that board already enables, so their schemas match the new
   `board`. Each change is a commit on the branch that board has checked out.
   A board whose `.board/board.json` still names `controls` is left as it is;
   `MIGRATING.md` says how to move it to `rules`.

`install --hooks` also does these, and Board.app always runs it so:

6. Installs every Claude Code mod in this release's marketplace, named
   `board`. It adds the marketplace again each time, which points it at this
   release and keeps the mods already installed from it. A mod the person
   disabled in Claude Code is enabled again.
7. Then uninstalls `board-controls@board`, now `board-rules@board`, and
   `attention-approve@attention`, now `board-attention@board`, and removes the
   GitHub `attention` marketplace.

It changes Claude Code's settings, so ask the owner before you run it.

Last, it moves `~/.local/share/board/current` to the new release. An install
that stopped leaves `current` where it was, so Board.app offers it again.

## Before you run it

- `~/.local/bin` must be on `PATH`. `claude` must be on `PATH` for
  `--hooks`; without it the install ends with no mods installed.
- Check what is installed now: `board --version`, and
  `readlink ~/.local/share/board/current`.

## When it stops

- `<path> is a folder, not a link the installer made`, or `<path> is a link
  to <target>, which is not the old attention plugin`: something other than
  this installer put it there. Nothing was changed. Show the owner the path.
  Do not delete it.
- `<path> is not a skill board wrote`: a folder at a Board skill's name in
  `~/.claude/skills` came from elsewhere. Nothing was changed. Show the owner.
- `<path> ships no skills`: the release was built wrongly. Nothing was
  changed. Build it again with `bin/bundle`.
- `these were not enabled`: each `plugin enable` error names its code and the
  next step. Follow it, then run `install` again.
- `<path> comes before ~/.local/bin/board on PATH`: an older binary, often in
  `~/.cargo/bin`, would run first. Nothing was changed. Show the owner the
  path.

Running `install` again is always safe.

## After it runs

- Check with `board plugin list --fields name,enabled`.
- `~/.config/attention/board` is left from the Python attention plugin, and
  nothing reads it now. The old source clone under `~/.local/share/board/src/`
  can be deleted once the owner agrees.
- Every release installed stays in `~/.local/share/board/releases`, and
  nothing deletes the old ones. Any release other than the one `current`
  names can be deleted by hand once the owner agrees.
- `board skills install --dir ~/.agents/skills` writes the skills for an
  agent that reads that directory, such as Codex.
- For each board that still names `controls`, follow `MIGRATING.md`.
