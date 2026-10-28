# Sync

The phone and the Mac meet in the owner's private iCloud database, so they
need no server and no shared network. Both must use the same Apple Account.

- Container `iCloud.com.stemmacorp.board`, zone `Pairing`. Builds signed
  for development use the development environment.
- `PairingRequest`, named by the device id: the device name, the
  commitment and the time it was made. After the challenge it also holds the
  key, the phone's nonce and the proof.
- `PairingChallenge`, named `challenge-<device id>`: the Mac's nonce.
- `PairingGrant`, named `grant-<device id>`: the granted scope and the Mac's
  name.
- A new request deletes the old challenge and grant in the same save.
- Each side reads every 2 seconds while its screen is open. The Mac reads
  the whole zone.
- A request older than 10 minutes is ignored; the phone then starts again.
- The phone deletes all three records once it reads its grant.

Not built: requests to approve, push notifications.
