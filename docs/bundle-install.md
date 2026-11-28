# Installing a release

`install` runs six steps; `install --hooks`, which Board.app never passes,
installs every mod at step 6 and adds step 7.
[INSTALL.md](../Install/INSTALL.md) lists what each step changes and the
arguments.

- Step 1 checks, before anything changes:
  - that `~/.local/bin` is on `PATH`, and that no directory before it on
    `PATH` holds another `board`;
  - that `~/.local/share/board/current` is a link or absent;
  - that `~/.local/share/board/plugins/attention` and
    `~/.claude/skills/attention` are absent or links an installer made;
  - that the release's `board` ships at least one skill and accepts
    `skills list --plugins`;
  - when the config names no personal board: that `git` runs; that the
    board folder is missing with a writable folder above it, empty apart
    from `.DS_Store`, a git repository with no commit and no other file, or
    the top of a git repository holding `.board/board.json`; and that git
    has, or is given, a name and an email. A value set in a file the global
    git config includes counts as set. When a value is unset and the global
    config, or a file it includes, has an `[includeIf]` section, step 1
    refuses and writes nothing. It writes the missing values last.
- Each release is copied once to `~/.local/share/board/releases/<id>`, through
  a `.partial-<id>` folder renamed when the copy is complete.
- `board` and `board-sign` are copied into `~/.local/bin` through
  `.<name>.new`. A different copy already there is kept as
  `~/.local/share/board/<name>.prev`. An `attention-sign` already there
  stays installed.
- Step 4 runs `board init --personal` only when the config names no personal
  board, and enables again only plugins a board already enables. A plugin
  under `~/.local/share/board/plugins` that no installer linked, and one a
  board names that `board` lacks (`board::plugin::not_installed`), is left.
- A relative path in the config is read against that file's folder, as
  `board` reads it. `$XDG_CONFIG_HOME` moves the config as it does for
  `board`.
- Step 5 counts only the skills it wrote, so an install that changed none
  says 0.
- The Claude Code marketplace is added from the copied release, because
  `current` moves last. Adding a marketplace of the same name re-points it
  and keeps its installed mods. Install never removes the `board`
  marketplace, because Claude Code would uninstall its mods.
- `current` moves to the release last, so an install that stopped is
  offered again.

## Lines for Board.app

Board.app reads these lines on standard output. Every other line, and
everything on standard error, is for a person.

| Line | Meaning |
| --- | --- |
| `::step <n> <label>` | Step `n` starts, such as `::step 5 Install skills`. |
| `::done <n> <summary>` | Step `n` finished, such as `::done 5 Installed 17 skills`. |
| `::warn <n> <summary>` | Step `n` finished and left something for the person. |
| `::controls <path>` | A known board still names `controls`; install left it as it is. |
| `::path <path>` | The path that the refusal names. |
| `::refusal <message>` | Why the installer stopped. |

A refusal prints `::refusal <message>` on standard output, then `install: <message>` on standard error, and exits with status 1. Board.app reads the two streams separately, so it takes the message from standard output, where it cannot arrive before the step's `::step` line.

## Not built

- Old releases are never deleted.
- `~/.config/attention/board`, which the Python attention plugin read, is
  not deleted.
