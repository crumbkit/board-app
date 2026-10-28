# Devices

## Pairing

1. Open Board on the Mac. It waits for a phone.
2. Open Board on the phone. It makes its key and a nonce, and publishes only
   a commitment: SHA-256 of the key and nonce.
3. The Mac sends a random nonce of its own. It pins the nonce, the
   commitment, the name and the request time in memory, and checks every
   later read of the request against them.
4. The phone signs the key and both nonces with Face ID, then reveals the
   key, its nonce and the signature.
5. The Mac checks the reveal against the commitment and the signature against
   the key. Both screens show six digits from the key and both nonces.
6. The owner checks the digits, picks what the phone may approve and clicks
   Add with Touch ID. The Mac writes the lines ([security](security.md))
   and a grant.
7. The phone reads the grant, shows "You're set" and deletes the records.

The phone commits before it sees the Mac's nonce, so a device that swaps in
its own key cannot search for one that gives the same digits. With two
requests waiting, the Mac pairs neither and says so.

Pairing the same phone again replaces its lines with the new scope.

## Revoking and a lost device

Not built in the app. To revoke a phone, delete the line ending in
`board-app/device/<id>` from both allowed signers files. A lost phone's key
needs that phone's Face ID, but revoke it anyway.
