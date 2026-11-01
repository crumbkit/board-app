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
  Again to Change opens pairing, which replaces the lines.
- The footer says whether the relay is sharing and when it last did. When
  iCloud fails, a banner says what to do; when no iPhone is paired, a
  banner offers Add iPhone.

## Toolbar

The search button opens the launcher ([launcher](launcher.md)). Add iPhone
opens pairing as a sheet ([devices](devices.md)). The sheet's Cancel closes
it, and it closes once a phone is added.

## Phone names

At pairing the Mac keeps the name the phone gave and the time, in its own
defaults. They are shown and never trusted: what a phone may sign comes
from the two files alone. A phone paired before the Mac kept names shows as
"iPhone" and the first 8 characters of its id until it pairs again.

Not built: removing a paired iPhone from the window.
