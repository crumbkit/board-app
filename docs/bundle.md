# The Board release in Board.app

The Mac app carries one Board release in `Contents/Resources/board`. Board.app
is the only Mac release of `board`, so a Mac always gets `board` and its
signer, `board-sign`, together. When the app opens and
`~/.local/share/board/current` names another release, the Board window offers
to install the one the app carries ([Board window](window.md#installing-board)).
An agent can also run `install` by hand; `INSTALL.md` beside it says how.

- [Building a release](bundle-building.md): `bin/bundle`, what it needs, and
  how it is tested.
- [Installing a release](bundle-install.md): where `install` puts each part,
  what it checks first, and the lines Board.app reads from it.
- [Building Board.dmg](bundle-dmg.md): `bin/dmg`, which signs the app and its
  release with the Developer ID for another Mac.

## What a release holds

- `bin/board`, built from crumbkit/board with every Board plugin built in,
  and `bin/board-sign`, built from this repository.
- `.claude-plugin/marketplace.json`: Board's Claude Code marketplace, `board`,
  with its eight mods, among them `board-attention` and `board-rules`.
  `plugins/<name>/claude-code` holds each mod, and nothing else from
  crumbkit/board's `plugins/` ships.
- `release.json`: the crumbkit/board and board-app commits, the date of the
  crumbkit/board commit, and the release id made from the two commits.
- `install`, `INSTALL.md`, `MIGRATING.md` and `SIGNING.md`, from `Install/`.
  `MIGRATING.md` moves a board from the `controls` plugin to `rules`.
  `SIGNING.md`, which the sheet's signing step links, says how Board checks
  signatures against `~/.config/board/allowed_signers`.

## Not built

- `bin/install-mac` does not sign the bundled binaries with the app's
  identity. Only `bin/dmg` signs them.
- Board.app does not check online for a newer release.
