# How Board checks signatures

Board asks for Touch ID before it writes an approval, writes one of your own
protected changes under `effects/`, or trusts an order you signed. Each of
those is an SSH signature, made by a key in this Mac's Secure Enclave or in
a paired iPhone's. Board checks the signature with `ssh-keygen -Y verify`
against one file: `~/.config/board/allowed_signers`.

## The file

Each line names a key Board trusts, as principal `owner`, and the kinds of
statement it may sign:

- `board/approve/v1`: approvals of what a plugin asked for.
- `board/write/v1`: your own protected writes. Only a Mac's key gets this.
- `attention/order/v1`: orders.

This Mac's line names all three and ends in `board`. A paired iPhone's line
names approvals, orders or both, as you chose when you paired it, and ends in
`board-app/device/<id>`.

Board does not read `~/.config/attention/allowed_signers` any more. Lines
left there do nothing.

## Let this Mac sign

Board.app shows this step after Install, and from the menu bar's Let This Mac
Sign… while this Mac's line is missing from the file or lacks a namespace.

1. Make Key runs `~/.local/bin/board-sign line`. board-sign makes the key
   in the Secure Enclave when there is none, and prints this Mac's line.
   Making the key needs no Touch ID; each signature after it does.
2. The sheet shows the line and how many other lines the file keeps.
3. Add with Touch ID asks for your fingerprint, with no password button,
   then checks the file and writes it. The line replaces any line with the
   same key. Every other line stays byte for byte. A new file gets mode
   644, and an existing file keeps its mode. The file is written beside
   itself and renamed into place, so no reader sees half of it.

board-sign keeps the key at `~/.config/board/secure-enclave-key`. When only
the older `~/.config/attention/secure-enclave-key` exists, board-sign moves
it there and leaves a link at the old path, so the older `attention-sign`
signs with the same key.

## When Board refuses the file

Board will not trust a file that group or other users may write, or that
neither you nor root owns, because another program could have added a line
to it. The sheet then changes nothing. It names the file, its mode and its
owner, and asks you to read the file's lines first: each line should be a
key you added. Delete any line you do not recognise, then run:

```bash
chmod 644 ~/.config/board/allowed_signers
```

and choose Try Again. A file owned by another user also needs
`sudo chown "$USER" ~/.config/board/allowed_signers` before the `chmod`.

## On a Mac without Board.app

Install board-sign in `~/.local/bin`, then add this Mac's line once:

```bash
line=$(~/.local/bin/board-sign line)
mkdir -p ~/.config/board
grep -qxF "$line" ~/.config/board/allowed_signers 2>/dev/null \
  || printf '%s\n' "$line" >>~/.config/board/allowed_signers
chmod 644 ~/.config/board/allowed_signers
```

`>>` adds to the file and keeps the paired lines; never write it with `>`.
If the file has an older line for this Mac's key, such as one without
`attention/order/v1`, delete that line by hand.
