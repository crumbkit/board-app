# Sync

The phone and the Mac meet in the owner's private iCloud database, so they
need no server and no shared network. Both must use the same Apple Account.

- Container `iCloud.com.stemmacorp.board`, zone `Pairing`. Builds use the
  Production environment, as TestFlight builds must, so the phone and the
  Mac meet however each was signed ([TestFlight](testflight.md)).
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

## Requests

Zone `Requests` carries pending effects to the phone and answers back.

- The Mac app reads the committed files under `effects/pending/` in the
  personal board every 10 seconds while its window is open. It shares each
  as a `Request` named by the effect id: the effect's bytes and the blob a
  put replaces, as assets, and the board's git remote, the commit time and
  the blob at the path now. It deletes requests no longer pending, and stamps `Shared`,
  named `mac`, with the time.
- The phone shows a request only when its effect hashes to the record's
  name, and the old version only when it hashes to the blob the effect names. It writes `Answer`, named `answer-<id>`: approve with the armored
  signature, or refuse with an optional reason.
- The Mac runs `board --personal answer <id> approve --signature -` or
  `refuse --reason=…`, then deletes the answer and the request. When Board
  refuses the answer, or its request is no longer pending, the Mac deletes the
  answer alone.

A build without the iCloud entitlement, such as an unsigned one, makes no
container. The Mac logs that iCloud is unavailable and shares nothing, and
pairing shows the same error.

Not built: push notifications.
