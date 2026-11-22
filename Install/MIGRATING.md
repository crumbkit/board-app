# Migrating a board from controls to rules

Board renamed its `controls` plugin to `rules`. A board written before the
rename keeps its requirements under `/controls/` as `controls/control/v1` and
`controls/source/v1` records, and other records name `controls.<capability>`
commands and `/controls/` paths. The new `board` binary still reads those old
records, but `board rules migrate --rename true` rewrites them to the new
names, history included, in one commit.

This guide was tested on a copy of a real personal board taken just before its
own rename. The rename wrote 2,057 changes (1,660 records, 397 files and 65
removals) in about 20 seconds, and the result matched the board's real
migration byte for byte.

## Before you start

- Install the new `board` binary and its skills with Board.app, or with
  `install` as `INSTALL.md` says.
- In Claude Code, replace the `board-controls@board` mod with
  `board-rules@board`. `install --hooks` does this; Board.app does not.
- If you set `BOARD_CONTROLS_AGENT`, rename it to `BOARD_RULES_AGENT`. The
  cache of judged rules moves to `board-rules/judged` and starts empty, so the
  first rules check after the switch judges every rule again.
- Make sure each board's working tree is clean and synced with its remote, and
  that no other session is writing to it while you migrate.

## Which board goes first

The rename reads and writes only the board it runs in, so every board runs it
itself. When one board mounts another (a personal board that mounts team or
repository boards, for example), migrate the mounted boards first and the
board that mounts them last. A reference into a mounted board that has not
migrated yet still resolves, so the order is not strict, but step 5 below
needs the mounted board's `/rules/` paths to exist.

## Steps for each board

Run these from inside the board's checkout, or add `-C <board>` to each
command.

### 1. Name `rules` in the board's config

Open `.board/board.json`, replace `"controls"` with `"rules"` in the
`plugins` list, and commit:

```bash
git commit -am "Name the rules plugin in place of controls"
```

The rename refuses with `rules::migrate::config_first` and writes nothing
until the config names `rules` and no longer names `controls`. A plugin may
not write the config itself, so this edit is manual.

### 2. Dry run

```bash
board rules migrate --rename true --json > rename-dry-run.json
```

This writes nothing. Its `data.output` holds:

- `total`: how many writes the rename will make. `writes` lists only the
  first 100 when `truncated` is true.
- `digest`: the hash of the planned writes. The apply in step 3 needs it.
- `kept`: files the rename leaves for a person to change, each with `why`.
- `signed`: signed orders and effects that hold an old name. The rename
  never rewrites them, because that would break their signatures.
- `unread`: files Board could not read. Any entry here stops the rename;
  fix or remove the file and dry-run again.

To see the digest and what was kept:

```bash
jq '.data.output | {total, digest, unread, signed, kept: [.kept[] | select(.path | startswith("/changes/") | not)]}' rename-dry-run.json
```

Records under `/changes/control-becomes-rule/` and `/changes/rule-rename-rest/`
always appear in `kept`. They describe the rename itself and keep the old
names on purpose. Leave them alone.

### 3. Apply

```bash
board rules migrate --rename true --apply true --digest <digest from step 2>
```

It writes everything in one commit with the trailer
`Board-Bulk: rename controls to rules`. If any record changed since the dry
run, it refuses with `rules::migrate::stale` and writes nothing; run the dry
run again and apply with the new digest.

What the apply changes:

- Each record under `/controls/` moves to `/rules/`.
  `controls/control/v1` becomes `rules/rule/v1`, and its `rule` field becomes
  `checker`. `controls/source/v1` becomes `rules/source/v1`.
- Field names in other records follow: a boundary's `checks[].control`, a
  crossing verdict's `control` and `rule`, a plan's `owed[].control` and a
  flow check's `controls`. A flow's `controlled-paths` and
  `planned-controlled` checks become `rule-paths` and `planned-rule-paths`.
- In every record's strings and every Markdown file, `/controls/` paths
  become `/rules/` and `controls.<capability>` becomes `rules.<capability>`.
- A flow stored at the hash of its JSON is stored again at its new hash. The
  old version is kept, so a mounted board that still names it keeps working,
  and every record in this board is pointed at the new version.

### 4. Confirm nothing is left

```bash
board rules migrate --rename true --json | jq '.data.output.total'
```

This prints `0`. The rules schemas are already in place after the apply;
`board plugin enable rules` reports `rules is already enabled`.

### 5. Move mount pointers by hand

A board that mounts another board's rules has mount pointers under
`/controls/`, such as `/controls/auth` containing:

```json
{"$type": "board/mount/v1", "path": "/repos/team/controls/auth"}
```

The rename lists these in `kept` and leaves them. Once the mounted board has
migrated, write each pointer at its `/rules/` path with the target's
`/controls/` changed to `/rules/`, then remove the old one:

```bash
printf '{"$type":"board/mount/v1","path":"/repos/team/rules/auth"}' | board put /rules/auth
```

```bash
board rm /controls/auth
```

Both commands commit. Repeat for each pointer in `kept`.

Two other kinds of file can appear in `kept` and also need a hand edit: a file
under `/controls/` that is not UTF-8 text or not a valid record, and a flow
under `/flows/` that is not stored at the hash of its JSON. Move or edit each
one as its `why` says.

### 6. Re-sign orders and effects that name controls

Signed orders and pending effects listed in `signed` still name the old
commands or paths. They keep verifying, but an agent that follows an order
saying "run `controls.check`" will find no such command. For each order that
matters, draft a replacement that uses the new names and have the owner sign
it with `board --personal attention sign --path /orders/<name>`, then remove
the old order. Pending effects can be approved or dropped as before; drop and
re-request any that would act on a `/controls/` path.

### 7. Check and push

```bash
board rules check --path /
```

```bash
git push
```

## Optional: fill in who owes each obligation

Boards from before the rename may have obligations without an `owed_by`
field. `board rules migrate --owed_by true` lists what it would set, and
`--apply true` writes it in one commit. This is separate from the rename and
can be done at any time.
