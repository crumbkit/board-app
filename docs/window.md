# Board window

The Mac app's window shows what Board relays and what waits for the owner.
It answers nothing: the owner answers on the iPhone or with `board answer`.
Closing it stops nothing. A click on the Dock icon, or Open Board Window in
the menu bar item's menu, opens it again.

## Relay

The app starts the relay when it launches, beside the launcher, and runs it
until the app quits ([sync](sync.md)). The relay keeps what the window
shows: the requests waiting, when iCloud first held each one, when it last
shared, and why the last share failed. Board.app does not start at login,
so after a restart nothing is shared until the owner opens it.

## Sidebar

- Waiting: the requests in the personal board's `effects/pending/`, one per
  thread, by board, as the iPhone inbox words them. A row says whether
  iCloud holds the request, or that no iPhone is paired, and shows the
  owner's latest reply.
- Answered: the records committed under `effects/seen/` in the last 7 days,
  with each effect from `effects/answered/`. An approval names the paired
  iPhone whose key its signature carries. Board checked the signature; the
  window only reads which key it names.
- iPhones: each device with a line in either allowed signers file
  ([security](security.md)). Its page shows what it may approve, read from
  the namespaces of its lines, its key's fingerprint and its lines. Pair
  Again to Change opens pairing, which replaces the lines. Remove iPhone
  deletes them after Touch ID ([devices](devices.md)).
- The footer says whether the relay is sharing and when it last did. When
  iCloud fails, a banner says what to do; when no iPhone is paired, a
  banner offers Add iPhone.

## Toolbar

The search button opens the launcher ([launcher](launcher.md)). Add iPhone
opens pairing as a sheet ([devices](devices.md)). The sheet's Cancel closes
it, and it closes once a phone is added.

## Installing Board

When the app launches and `~/.local/share/board/current` does not name the
release the app carries ([bundle](bundle.md)), the window opens with a
sheet. It waits while the pairing sheet is open.

- With no release installed, it offers Install Board on this Mac: the
  binaries, the skills, the Claude Code mods and the plugins, with the
  personal board named in Board's config.
- With another release installed, it offers Update Board: both releases'
  crumbkit/board commits and dates, what the update replaces, updates,
  enables and removes, and the boards that still name `controls`, with
  Open Migration Guide, which opens `MIGRATING.md`. A Removes row shows only
  when `board-controls@board` is installed in Claude Code, or the Python
  attention plugin is linked or its `attention-approve` mod installed.
- Install or Update gets the PATH from the person's login shell (`$SHELL
  -l -c`, five seconds at most), then runs `install --hooks` with it through
  the one runner. When the shell fails, it runs with `~/.local/bin` before
  the app's own PATH, and the sheet says so.
- While it runs, the sheet shows the seven steps and the installer's
  output as they arrive. Afterwards it shows what each step did, with a
  warning sign on a step that left something for the person, or why the
  install stopped, what that left behind, Show in Finder for the path the
  installer named, Close and Try Again.
- Not Now closes the sheet until the next launch. Until the release is
  installed, the menu bar icon has a dot in the accent colour and the menu
  has Install Board… or Update Board…, which shows the sheet again.
- Quitting the app while it installs stops the installer and everything it
  started. `current` moves only at the end, so the sheet shows again on the
  next launch.

## Phone names

At pairing the Mac keeps the name the phone gave and the time, in its own
defaults. They are shown and never trusted: what a phone may sign comes
from the two files alone. A phone paired before the Mac kept names shows as
"iPhone" and the first 8 characters of its id until it pairs again.
