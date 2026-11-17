# Installing a release

`install` runs seven steps, and `install --hooks` all of them; without
`--hooks` it stops after step 5. [INSTALL.md](../Install/INSTALL.md) lists
what each step changes.

- Step 1 checks, before anything changes:
  - that `~/.local/bin` is on `PATH`, and that no directory before it on
    `PATH` holds another `board`, which would still run;
  - that `~/.local/share/board/current` is a link or absent;
  - that `~/.local/share/board/plugins/attention` and
    `~/.claude/skills/attention` are absent or links an installer made. Such
    a link points into a copied release, or at a board-attention checkout,
    which `pyproject.toml` names;
  - that the release's `board` ships at least one skill, because a `board`
    with none would make `board skills install` remove every Board skill;
  - that no folder in `~/.claude/skills` at the name of a Board skill is one
    `board` did not write, except a link an installer made, which step 4
    removes.
- Each release is copied once to `~/.local/share/board/releases/<id>`, through
  a `.partial-<id>` folder that is renamed only when the copy is complete.
  Nothing writes there afterwards.
- `board` and `attention-sign` are copied into `~/.local/bin` through
  `.<name>.new`. A different copy already there is kept as
  `~/.local/share/board/<name>.prev`.
- `board skills install` writes the skills. Step 4's summary counts only the
  skills it wrote, so an install that changed none says 0.
- A plugin under `~/.local/share/board/plugins` that no installer linked
  comes from elsewhere: install leaves its link and does not enable it. A
  plugin a board names that `board` does not have
  (`board::plugin::not_installed`) is skipped.
- A relative path in `~/.config/board/config.json` is read against that
  file's folder, as `board` reads it. A config that names no board makes
  step 5 end with a `::warn` line.
- The Claude Code marketplace is added from the copied release, not through
  `current`, because `current` moves last. Adding a marketplace of the same
  name re-points it and keeps its installed mods. Install never removes the
  `board` marketplace, because Claude Code uninstalls every mod of a removed
  marketplace and deletes their data.
- When `claude` is not on `PATH`, or Claude Code does not uninstall an old
  mod, the install still succeeds and says so on a `::warn` line.
- `~/.local/share/board/current` moves to the release last, so an install
  that stopped is offered again.

## Lines for Board.app

Board.app reads these lines on standard output. Every other line, and
everything on standard error, is for a person.

| Line | Meaning |
| --- | --- |
| `::step <n> <label>` | Step `n` starts, such as `::step 4 Install skills`. |
| `::done <n> <summary>` | Step `n` finished, such as `::done 4 Installed 17 skills`. |
| `::warn <n> <summary>` | Step `n` finished and left something for the person. |
| `::controls <path>` | A known board still names `controls`; install left it as it is. |
| `::path <path>` | The path that the refusal names. |
| `::refusal <message>` | Why the installer stopped. |

A refusal prints `::refusal <message>` on standard output, then `install: <message>` on standard error, and exits with status 1. Board.app reads the two streams separately, so it takes the message from standard output, where it cannot arrive before the step's `::step` line.

## Not built

- Old releases are never deleted.
- `~/.config/attention/board`, which the Python attention plugin read, is
  not deleted.
