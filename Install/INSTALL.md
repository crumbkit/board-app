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
   `docs/bundle-install.md` in crumbkit/board-app lists the checks. When
   `~/.config/board/config.json` names no personal board, it also checks that
   `git` runs, that the board folder is missing, empty, an empty git
   repository or an existing board, and that git has a name and an email for
   commits. It then sets a name or email git lacks with `git config --global`
   from `--git-name` and `--git-email`. It never changes a value already set.
2. Copies the release to `~/.local/share/board/releases/<id>` once.
3. Installs `board` and `board-sign` in `~/.local/bin`, keeping each
   replaced binary as `~/.local/share/board/<name>.prev`. An `attention-sign`
   already there stays installed. Every Board plugin
   is built into `board`, so it removes the plugin links an older release
   made in `~/.local/share/board/plugins`, and the links of the Python
   attention plugin from stemmacorp/board-attention. It leaves every other
   link there alone.
4. Sets up your boards. When the config names no personal board, it creates
   the board folder, `~/Board` unless `--board-folder` names another, runs
   `git init` there when the folder is not a git repository, and runs
   `board init --personal`. That makes the folder a board, enables tasks,
   evals, runs, rules, plans and share, and names it `personal` in the
   config. When the config names a personal board whose folder is missing,
   it warns, names the path and creates nothing. Then, in each board the
   config lists, it enables again the built-in plugins that board already
   enables, so their schemas match the new `board`. Each change is a commit
   on the branch that board has checked out. A board whose
   `.board/board.json` still names `controls` is left as it is;
   `MIGRATING.md` says how to move it to `rules`.
5. Removes the skill links an older release made in `~/.claude/skills`, then
   runs `board skills install --plugins` with every plugin some known board
   enables. Board's skills of other plugins already there are kept.
6. Updates the Claude Code mods already installed from Board's marketplace,
   `board`, that this release still ships: it adds the marketplace again
   from this release, then runs `claude plugin update` for each. It installs,
   enables and disables none, so each mod keeps its on or off state and no
   new mod is added. An installed mod this release no longer ships is left
   and named in the step's summary.

A plugin a later release adds is not enabled in any board. Run
`board plugin enable <name>` in the board that should have it.

`install --hooks` changes step 6 and adds step 7. It changes Claude Code's
settings, so ask the owner before you run it. Board.app never passes it.

6. Installs every Claude Code mod in the `board` marketplace. A mod the
   person disabled in Claude Code is enabled again.
7. Then uninstalls `board-controls@board`, now `board-rules@board`, and
   `attention-approve@attention`, now `board-attention@board`, and removes the
   GitHub `attention` marketplace.

Last, it moves `~/.local/share/board/current` to the new release. An install
that stopped leaves `current` where it was, so Board.app offers it again.

The installer does not add this Mac's key to `~/.config/board/allowed_signers`.
Board.app's sheet does that after Install, with Touch ID; `SIGNING.md` beside
this file says how, and gives the commands for a Mac without the app.

## Arguments

- `--board-folder <path>`: where a new personal board goes. Left out, it is
  `~/Board`. It is read only when the config names no personal board.
- `--git-name <name>` and `--git-email <email>`: the git identity to set,
  each only when git has none. An email needs one `@`, text on both sides
  and no spaces.
- `--hooks`: as above.

## Before you run it

- `~/.local/bin` must be on `PATH`. Without `claude` on `PATH`, step 6 warns
  and changes no mods.
- Check what is installed now: `board --version`, and
  `readlink ~/.local/share/board/current`.

## When it stops

- `<path> is a folder, not a link the installer made`, or `<path> is a link
  to <target>, which is not the old attention plugin`: something other than
  this installer put it there. Nothing was changed. Show the owner the path.
  Do not delete it.
- `<path> holds files and is not a board`: the board folder is in use.
  Nothing was changed. Pass `--board-folder` with an empty folder or an
  existing board.
- `git has no name or email`: nothing was changed. Run the two
  `git config --global` commands it names, or pass `--git-name` and
  `--git-email`.
- `has a conditional include`: git's name or email is unset, and the
  global git config, or a file it includes, has an `[includeIf]` section
  that may set it. A value written now would override that section.
  Nothing was changed. Set `user.name` and `user.email` in the global git
  config outside any conditional include.
- `<email> is not an email address`, or `git does not run`: nothing was
  changed. Fix it as the message says.
- `<path> ships no skills`, or `refused skills list --plugins`: the release
  was built wrongly or from an older crumbkit/board. Nothing was changed.
  Build it again with `bin/bundle`.
- `board init --personal refused`: its error names a code, such as
  `board::config::personal_elsewhere`, and the next step. Follow it.
- `board skills install refused` with `board::skills::not_board`: a folder
  at a Board skill's name in `~/.claude/skills` came from elsewhere. The
  binaries are new and the skills old. Show the owner.
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
