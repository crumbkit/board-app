#!/bin/sh
# An example launcher provider for trying the launcher by hand. It lists two
# made-up workspaces and writes a few evidence files to a temporary
# directory. Nothing runs it unless launcher.json names it; see
# docs/launcher-providers.md.
#
#   launcher-example-provider.sh list
#   launcher-example-provider.sh parts NAME
#   launcher-example-provider.sh stop-preview NAME
set -eu
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
dir=${TMPDIR:-/tmp}/launcher-example

# Escapes a value for a JSON string: backslashes, quotes and control
# characters.
json() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr -d '\000-\037'
}

case "${1:-}" in
list)
  self_json=$(json "$self")
  cat <<JSON
{
  "kind": "launcher/items/v1",
  "sections": [
    {
      "title": "Running",
      "items": [
        {
          "id": "workspace:garden-journal",
          "type": "workspace",
          "title": "garden-journal",
          "subtitle": "web · api",
          "keywords": ["web", "api"],
          "status": {"tone": "good", "word": "Running"},
          "children": ["$self_json", "parts", "garden-journal"],
          "actions": [
            {"id": "open-web", "label": "Open web", "open": {"href": "http://localhost:3000/", "reach": "mac-only"}},
            {"id": "copy-branch", "label": "Copy branch", "copy": "garden-journal"},
            {"id": "stop", "label": "Stop workspace",
             "run": {"argv": ["/usr/bin/true"], "confirm": {"preview": ["$self_json", "stop-preview", "garden-journal"]}}}
          ],
          "data": {
            "apps": [
              {"name": "web", "link": {"href": "http://localhost:3000/", "reach": "mac-only"}},
              {"name": "api", "link": {"href": "http://localhost:4000/", "reach": "mac-only"}}
            ],
            "branch": "garden-journal",
            "updated": "2026-10-30T09:12:00Z"
          }
        }
      ]
    },
    {
      "title": "Recently stopped",
      "items": [
        {
          "id": "workspace:login-fix",
          "type": "workspace",
          "title": "login-fix",
          "subtitle": "2 d ago",
          "status": {"tone": "neutral", "word": "Stopped"},
          "children": ["$self_json", "parts", "login-fix"],
          "actions": [{"id": "copy-name", "label": "Copy name", "copy": "login-fix"}],
          "data": {"apps": [{"name": "web"}], "branch": "login-fix"}
        },
        {"id": "job:nightly", "type": "job", "title": "nightly", "data": {}}
      ]
    }
  ]
}
JSON
  ;;
parts)
  name=$2
  name_json=$(json "$name")
  mkdir -p "$dir/$name"
  printf '# %s\n\nThe sign-in page now returns you to the page you asked for.\n\n- web: passed\n- api: passed\n' "$name" >"$dir/$name/report.md"
  printf 'web test\n  120 passed in 42.5 s\n' >"$dir/$name/run.log"
  printf '{"result": "passed", "count": 120}\n' >"$dir/$name/result.json"
  evidence() {
    file=$dir/$name/$1
    size=$(wc -c <"$file" | tr -d ' ')
    sha=$(shasum -a 256 <"$file" | cut -d' ' -f1)
    printf '{"id": "evidence:%s/%s", "type": "evidence", "title": "%s", "data": {"path": "%s", "kind": "%s", "size": %s, "added": "%s", "task_record": "tasks/%s.md", "sha256": "%s"}}' \
      "$name_json" "$1" "$1" "$(json "$file")" "$2" "$size" "$3" "$name_json" "$sha"
  }
  cat <<JSON
{
  "kind": "launcher/items/v1",
  "sections": [
    {"title": "Evidence", "items": [
      $(evidence report.md Markdown 2026-10-29T10:00:00Z),
      $(evidence run.log Log 2026-10-30T08:00:00Z),
      $(evidence result.json JSON 2026-10-30T08:01:00Z)
    ]},
    {"title": "Test runs", "items": [
      {"id": "test:$name_json/1", "type": "test-run", "title": "web tests",
       "status": {"tone": "good", "word": "Passed"},
       "data": {"passed": true, "command": "web test", "finished": "2026-10-30T08:00:00Z", "seconds": 42.5, "summary": "120 passed"}}
    ]},
    {"title": "Commits", "items": [
      {"id": "commit:$name_json/1", "type": "commit", "title": "Sign-in returns you to the page you asked for",
       "data": {"sha": "3f2a9c1d7e5b", "subject": "Sign-in returns you to the page you asked for",
                "author": "Sam", "date": "2026-10-30T07:00:00Z"}}
    ]}
  ]
}
JSON
  ;;
stop-preview)
  printf 'Would stop %s:\n  web  (port 3000)\n  api  (port 4000)\n' "$2"
  ;;
*)
  echo "usage: $0 list | parts NAME | stop-preview NAME" >&2
  exit 2
  ;;
esac
