# The release environment

The `dmg` job runs in the GitHub environment `release` and reads the five
[secrets](release-secrets.md) from it. It stops, naming the first secret
that is not set.

The owner creates the environment once. Its deployment rule admits only
main and `v*` tags, so a run from any other branch cannot read the
secrets. The rule admits a `v*` tag on any commit, and a tag runs the
release.yml of the commit it names, so the rule alone lets a tag on
another branch run an edited workflow that reads the secrets. The owner is
therefore a required reviewer on the environment: every run waits for his
approval before the `dmg` job starts, and that approval is what keeps a
tag on another branch from reaching the secrets. The first command sets
the owner, as the signed-in `gh` user, as the reviewer, together with the
deployment rule:

```bash
owner_id=$(gh api user --jq .id)
echo "{\"reviewers\":[{\"type\":\"User\",\"id\":$owner_id}],\"deployment_branch_policy\":{\"protected_branches\":false,\"custom_branch_policies\":true}}" |
  gh api --method PUT repos/crumbkit/board-app/environments/release --input -
gh api --method POST repos/crumbkit/board-app/environments/release/deployment-branch-policies \
  -f name=main -f type=branch
gh api --method POST repos/crumbkit/board-app/environments/release/deployment-branch-policies \
  -f name='v*' -f type=tag
```

A manual run started from another branch fails at the `dmg` job, because
the environment does not admit it.

The job imports the certificate into a keychain that lives only for the
job, and deletes it when the job ends. `bin/dmg` passes the API key to
`xcodebuild` through `ASC_KEY_PATH`, `ASC_KEY_ID` and `ASC_ISSUER_ID`, so
Xcode fetches the Developer ID provisioning profile that iCloud needs
without a signed-in account. notarytool uses the same key through the
keychain profile `board-notary`. The job's log shows the notarisation
submission id and never a secret.
