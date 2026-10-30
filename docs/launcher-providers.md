# Launcher providers

## The config file

Board.app reads its providers from `~/.config/board/launcher.json` each
time the launcher opens:

```json
{"providers": [{"name": "Workspaces", "list": ["/usr/local/bin/workspaces", "list"]}]}
```

`name` is what the footer and a failure row show. `list` is the argv of
the listing command. Board.app refuses the file when it is a symlink,
belongs to another user, or the group or others can write it. Run
`chmod 600 ~/.config/board/launcher.json` after creating it.

With no file, the launcher says that no providers are set up.

## Writing a provider

A provider is any executable that prints [the contract](launcher-contract.md)
on standard output.

- Exit 0 when the output is good. Any other status shows as Failed.
- Print within 5 seconds and under 1 MB.
- Give every argv an absolute path as its first element. No shell runs
  it, so `~`, `$HOME`, pipes and globs are passed through as written.
- Give items stable ids, such as `workspace:garden-journal`.
- Keep a confirm preview free of side effects. It runs every time the
  owner picks the action.

## The example provider

[launcher-example-provider.sh](launcher-example-provider.sh) lists two
made-up workspaces and writes three evidence files to a temporary
directory. Nothing runs it by default. To try it, point the config at
its absolute path:

```json
{"providers": [{"name": "Example", "list": ["/path/to/board-app/docs/launcher-example-provider.sh", "list"]}]}
```

Its stop action runs `/usr/bin/true`, so it changes nothing.

## Testing a provider

Run the command yourself and check the output decodes:

```sh
/usr/local/bin/workspaces list | python3 -m json.tool
```

`LauncherTests` decodes the example provider's output and the example in
the contract doc, so both stay valid.
