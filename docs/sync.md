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

Zone `Requests` carries pending effects and their threads to the phone, and
answers and replies back. [Requests](sync-requests.md) has the records.
It also carries the agents' open questions and the owner's answers
([questions](sync-questions.md)).

A build without the iCloud entitlement, such as an unsigned one, makes no
container. The Mac still lists what waits, logs once that iCloud is
unavailable, shares nothing, and shows the same error in its window and in
pairing.
