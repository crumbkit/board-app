# Launcher contract

A provider prints one JSON object. Its `kind` is `launcher/items/v1`;
Board.app refuses any other kind. It holds `sections`, each with a
`title` and `items`.

```json
{
  "kind": "launcher/items/v1",
  "sections": [{
    "title": "Running",
    "items": [{
      "id": "workspace:garden-journal",
      "type": "workspace",
      "title": "garden-journal",
      "subtitle": "web · api",
      "keywords": ["web", "api"],
      "status": {"tone": "good", "word": "Running"},
      "children": ["/usr/local/bin/workspaces", "parts", "garden-journal"],
      "actions": [
        {"id": "open-web", "label": "Open web",
         "open": {"href": "http://localhost:3000/", "reach": "mac-only"}},
        {"id": "copy-branch", "label": "Copy branch", "copy": "garden-journal"},
        {"id": "stop", "label": "Stop workspace",
         "run": {"argv": ["/usr/local/bin/workspaces", "stop", "garden-journal"],
                 "confirm": {"preview": ["/usr/local/bin/workspaces", "stop", "garden-journal", "--dry-run"]}}}
      ],
      "data": {
        "apps": [{"name": "web", "link": {"href": "http://localhost:3000/", "reach": "mac-only"}}],
        "branch": "garden-journal",
        "updated": "2026-10-30T09:12:00Z"
      }
    }]
  }]
}
```

## Items

- `id` is stable across runs, so a selection survives a refresh.
- `status` has a `tone` (`good`, `neutral`, `failed` or `removed`) and the
  word the row shows.
- `children` is the argv of a command that prints the item's parts in the
  same format. Its sections might be Evidence, Test runs and Commits.
- `data` holds the type's own fields. Dates are ISO 8601 with seconds.

## Actions

An action has an `id`, a `label` and exactly one of these:

- `open`: a URL.
- `copy`: text.
- `run`: an argv. With `confirm`, Board.app first runs `preview` and
  shows its output. The owner then picks the action or Cancel, and Cancel
  is selected.

↩ on an item opens it when it has `children` or more than two actions,
and runs its first action when not. ⌘↩ runs the next action: the first
when ↩ opens the item, the second when not.

Every argv, including `children` and `preview`, must start with an
absolute path. `open` takes only http and https URLs.

## URLs

Every URL is an object with `href` and `reach`. `mac-only` works only on
this Mac; `proxyable` can be reached through a proxy; `public` works
anywhere. The phone will open only the last two.

## Types

Board.app shows a type only when it has a view for it. It skips items of
any other type, and the provider's list says how many and why.

- `workspace`: `apps` (`name`, optional `link`), `branch`, `updated`.
- `evidence`: `path`, `kind`, `size` in bytes, `added`, `task_record`,
  `sha256`.
- `test-run`: `passed`, `command`, `finished`, `seconds`, `summary`.
- `commit`: `sha`, `subject`, `author`, `date`, `link`.

`test-run` and `commit` are parts of a workspace. Optional fields may be
left out.
