# Devices

## Pairing

1. Click Add iPhone in the Board window on the Mac. The sheet waits for a
   phone; Cancel closes it.
2. Open Board on the phone. It makes its key and a nonce, and publishes only
   a commitment: SHA-256 of the key and nonce.
3. The Mac sends a random nonce of its own. It pins the nonce, the
   commitment, the name and the request time in memory, and checks every
   later read of the request against them.
4. The phone signs the key and both nonces with Face ID or Touch ID, then reveals the
   key, its nonce and the signature.
5. The Mac checks the reveal against the commitment and the signature against
   the key. Both screens show six digits from the key and both nonces.
6. The owner checks the digits, picks what the phone may approve and clicks
   Add with Touch ID. The Mac writes the lines ([security](security.md))
   and a grant.
7. The phone reads the grant, shows "You're set" and deletes the records.
   The Mac keeps the phone's name and the time ([window](window.md)).

The phone commits before it sees the Mac's nonce, so a device that swaps in
its own key cannot search for one that gives the same digits. With two
requests waiting, the Mac pairs neither and says so.

Pairing the same phone again replaces its lines with the new scope.

## Revoking and a lost device

Select the phone in the Board window and click Remove iPhone. A
confirmation names the phone; Remove with Touch ID then deletes from both
allowed signers files every line that names it: a line with the field
`board-app/device/<id>`, split on spaces, tabs and CR, and a line from
which OpenSSH could read the same key, under any comment. It reads both
files before it writes either, then forgets the phone's name. The id is the one the page showed, taken before
Touch ID.

Board tries both files even when one fails, and an alert names each file
that still holds the phone's key, such as one that group or others may
write. Removing a phone touches no other line, and the phone's own key and app are left as they are; to use it
again, pair it again.

A lost phone's key needs that phone's Face ID or Touch ID, but remove it
anyway.
