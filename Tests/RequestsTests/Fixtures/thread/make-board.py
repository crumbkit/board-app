import json, hashlib, os, sys
root = sys.argv[1]
board = "/Users/ana/Code/board"
base = """---
$type: "tasks/task/v2"
title: "Write the release notes"
status: "open"
defer: "%s"
reviewed: "2026-10-29"
---

Collect the merged pull requests since the last tag.
"""
def effect(text, asked):
    digest = "sha256:" + hashlib.sha256(text.encode()).hexdigest()
    e = {"$type": "board/effect/v1", "board": board, "plugin": "tasks", "op": "put",
         "path": "/tasks/write-the-release-notes.md", "text": text, "digest": digest, "asked": asked}
    key = {k: e.get(k) for k in ["board", "plugin", "op", "path", "digest"]}
    key["prior"] = None
    eid = hashlib.sha256((json.dumps(key, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()).hexdigest()
    return eid, e
def write(path, obj):
    p = os.path.join(root, path.lstrip("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f: f.write(json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
v1, e1 = effect(base % "2026-10-30", "2026-10-30T18:40:02.000000Z")
v2, e2 = effect(base % "2026-11-02", "2026-10-30T18:52:11.000000Z")
v3, e3 = effect(base % "2026-11-03", "2026-10-30T18:58:40.000000Z")
write(f"/effects/answered/{v1}.json", e1)
write(f"/effects/seen/{v1}.json", {"$type": "board/seen/v1", "effect": f"/effects/answered/{v1}", "answer": "refuse", "reason": "Not Friday"})
write(f"/effects/pending/{v2}.json", e2)
write(f"/effects/pending/{v3}.json", e3)
write(f"/requests/replies/{v1}/20261030T184500Z.json", {"$type": "requests/reply/v1", "effect": v1, "text": "Not Friday. Next week."})
write(f"/requests/replies/{v2}/20261030T185500Z.json", {"$type": "requests/reply/v1", "effect": v2, "text": "Monday's full. Defer it to Tuesday instead."})
print(v1, v2, v3)
