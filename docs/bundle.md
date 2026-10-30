# The Board release in Board.app

The Mac app carries one Board release in `Contents/Resources/board`. An agent
installs it with `install`; `INSTALL.md` beside it tells the agent how.

- [Building a release](bundle-building.md): `bin/bundle`, what it needs, and
  how it is tested.
- [Installing a release](bundle-install.md): where `install` puts each part,
  and what it checks first.

## What a release holds

- `bin/board`, built from crumbkit/board, and `bin/attention-sign`, built from this
  repository.
- `plugins/<name>`: every plugin on Board's main, and attention from
  board-attention, without their tests.
- `python/board-plugin`: the library Board's plugins depend on by path.
- `.claude-plugin/marketplace.json`: one Claude Code marketplace, `board`,
  with the hooks of controls, plans, runs and effects, and attention-approve.
- `release.json`: the three commits, and the release id made from them.
- `install` and `INSTALL.md`, from `Install/`.

## Not built

- Bundled binaries are not signed with the app's identity.
- Nothing checks that a newer release is in a newer app.
