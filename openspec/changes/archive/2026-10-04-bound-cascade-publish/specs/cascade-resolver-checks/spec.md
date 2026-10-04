## MODIFIED Requirements

### Requirement: Offline wiring test suite

`bash .github/scripts/cascade/wiring/test/run.sh` SHALL test the wiring scripts with no network:
local bare git repos served as `origin` through `file://` URLs, a `gh` shim selected through
`CASCADE_GH` that answers from fixture files and logs every call, the real
`cascade-resolve.sh` as `CASCADE_RESOLVER` for its offline subcommands only (`title`, `body`,
`classify`, `semver-cmp`; no case calls `newest`, `published` or `pin-of`), and a toy
`Taskfile.yml`. It SHALL print `PASS` or `FAIL` per case and
exit 0 only when every case passes. It SHALL cover at least: payload validation (eight tags, nine
tags, a bad tag, a tag with a trailing newline, a control character in the source, an unknown
source, extra keys); every receiver mode, including a bot commit a human amended; the cascade-PR
filter (a fork PR on `deps/cascade`, a same-repo PR by a human, two matching PRs); the
derived-file merge conflict and a hard conflict; merge mode running `main`'s task when the branch
changed it; every row of the workflows guard under both rule values; the title rules (not
retitled, retitled with `!` kept, the title-rise comment firing once, a marker pasted into the
Notes, a body with no marker); the breaking check over several releases with one breaking release
in the middle and with an API error; Notes extraction with the marker, without it, and with a CRLF
body that must not grow across two runs; the publish refusals (a PR-number mismatch, an unknown
label, an unknown action, a bundle touching `.tasks/cascade/pins.sh`, `Taskfile.yml` or a symlink,
a mode change, a non-bot commit, a rebuild that would drop a human commit, a merge commit whose
tree is not the merge of its parents); publish deriving the title, body and labels itself (a
forged title, planted body text, a dropped `need-human-review` or `deps-cascade:breaking`); the
per-receiver allow-lists and the mirrors of each receiver's `pins.sh`; the action table; the
notify payload bytes and target map; the org `.github` ref guard and the repo-name derivation,
run from the inline step text of every job in the three workflows; that no repo-code command sees
a token; the pinned tool installer; the release-key rule of the wiring check; and the gate status
mapping with truncation.

#### Scenario: Wiring suite runs without network

- **WHEN** the wiring suite runs on a machine with no network access
- **THEN** every case passes and the `gh` shim log shows no call that the case did not expect

#### Scenario: Amended bot commit is a human commit

- **WHEN** the fixture branch holds a bot-authored commit whose committer is a human
- **THEN** the case asserts the receiver picks mode `merge`, not `rebuild`
