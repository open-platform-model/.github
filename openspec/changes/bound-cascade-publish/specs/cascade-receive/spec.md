## MODIFIED Requirements

### Requirement: Payload is a validated hint

On a `repository_dispatch` run `compute` SHALL accept the payload only when `source` is a string
in the receiver's allowlist and `tags` is an array of 1 to 8 strings each matching the tag shape
for that source; unknown keys SHALL be ignored. A `source` or tag holding a control character
(U+0000 to U+001F or U+007F) SHALL make the payload invalid, and each tag SHALL be matched whole,
so a tag with a trailing newline is refused. Allowlists: `catalog_opm` accepts `core`, `cli`;
`library` accepts `core`, `catalog_opm`; `opm-operator` accepts `catalog_opm`, `library`, `cli`;
`cli` accepts `catalog_opm`, `library`, `opm-operator`; `cascade-sandbox-down` accepts
`cascade-sandbox-up`. A receiver outside this list SHALL fail with "not a cascade receiver". A
valid payload SHALL set `CASCADE_SOURCE`, `CASCADE_TAGS` and one `CASCADE_EXPECT` pair built from
the last tag (`catalog_opm` tags lose their `opm-` prefix). An invalid payload SHALL be dropped
whole with a warning and a summary line naming why, and the run SHALL continue as a sweep. The
payload SHALL never set a label. Only `cascade-sandbox-down` SHALL export
`CASCADE_EXTRA_SOURCES=cascade-sandbox-up`. `publish` SHALL read the payload from the event
itself, with the same validation, never from `compute`.

#### Scenario: Hostile payload

- **WHEN** the payload is `{"source":"evil","tags":["@x"]}`
- **THEN** the payload is dropped with a warning, the run behaves as a sweep, and no mention appears in any text the bot writes

#### Scenario: Nine tags

- **WHEN** the payload carries nine valid tags
- **THEN** the whole payload is dropped and the run continues as a sweep

#### Scenario: Tag with a trailing newline

- **WHEN** the payload for cli is `{"source":"library","tags":["v1.0.0\n","v1.0.1"]}`
- **THEN** the whole payload is dropped and the run continues as a sweep

### Requirement: Labels

The planned labels SHALL be the union of `deps-cascade`, the `cascade-labels` marker of the new
body, and `deps-cascade:breaking` when any non-draft release of a moved pin's upstream with a
version `v` where `from < v <= to` has `BREAKING CHANGES` in its body. The breaking check SHALL
cover the whole range between the pin on `main` and the pin on the branch, never read the
payload, ignore pins of third-party modules, and on an API error add no label and write a summary
warning. `publish` SHALL derive the labels again with `.github` code: the marker from the body it renders itself, and the breaking check
from the `.github` mirror of the receiver's pins and the releases it reads itself; when its
release read fails it SHALL keep the plan's `deps-cascade:breaking` and write a notice; every
other planned label is ignored. The bot SHALL only add labels, with one exception: it removes
`deps-cascade:conflict` after a successful push; it SHALL never remove `need-human-review` or
`deps-cascade:breaking`. Outside cli (`labels-managed: false`) `publish` SHALL create or update
the five labels `deps-cascade`, `deps-cascade:conflict`, `deps-cascade:hold`,
`deps-cascade:breaking` and `need-human-review` with the colours and descriptions of workspace
RELEASING.md, section "Labels"; with `labels-managed: true` it SHALL fail with "declare it in
.github/labels.yml" when any of them is missing.

#### Scenario: Breaking release in the middle of the range

- **WHEN** the pin moves from `v1.0.0` to `v1.3.0` and only `v1.2.0`'s release body contains `BREAKING CHANGES`
- **THEN** the planned labels include `deps-cascade:breaking`

#### Scenario: A plan that drops the labels

- **WHEN** a library plan moves core but lists only `deps-cascade`, and an upstream release in the range is breaking
- **THEN** `publish` adds `need-human-review` and `deps-cascade:breaking` itself

#### Scenario: A live label is never removed

- **WHEN** the open cascade PR carries `need-human-review` and the new plan derives no such label
- **THEN** `publish` removes nothing but, at most, `deps-cascade:conflict`

### Requirement: Publish verifies before it mints

`publish` SHALL treat the uploaded plan as untrusted and, with `GITHUB_TOKEN` and plain git only,
before the token exists: refuse an unknown action or a label outside the five bot-relevant labels;
re-derive the cascade PR and refuse a PR-number mismatch; stop with "deps/cascade moved since
compute; the next run retries" when the remote tip differs from the planned old tip; for `push`
and `recreate` verify the bundle, require its tip to equal the planned new tip, re-run the
workflows guard, bound the increment (requirement "Publish bounds the bot's increment") and
render the title, body and labels itself (requirement "Publish renders the PR text"); and lint
the body above the Notes marker and every comment it builds for a bare mention. Every comment
SHALL be built inside `publish` from fixed texts. Every push and branch delete SHALL carry a lease
on the planned old tip (an empty lease where the branch must not exist). When the re-derived
cascade PR carries `deps-cascade:hold` that `compute` did not see, `publish` SHALL mint no token
and publish nothing, and SHALL end with a notice, not a failure (stop switch 1 used as
documented).

#### Scenario: Hold added between compute and publish

- **WHEN** a human adds `deps-cascade:hold` to the cascade PR after `compute` planned a `push`
- **THEN** `publish` writes a notice, skips the mint and every write, and the run is not red

#### Scenario: Human push between compute and publish

- **WHEN** a human pushes to `deps/cascade` after `compute` read the tip
- **THEN** `publish` fails before minting the token and the next run retries

#### Scenario: Forged plan

- **WHEN** the plan names a PR number that is not the bot's cascade PR
- **THEN** `publish` refuses before minting the token

### Requirement: Task run, commit and Notes

`compute` SHALL refuse a dirty `repo/` tree, run `task -x deps:cascade` with
`CASCADE_BASE=origin/main` (exit 3: no commit; any exit other than 0 or 3: job error), commit
the result as `opm-cascade[bot]` with the computed title as the only line, and require the title
computed before the commit to equal the title computed after it. In mode `merge`, when the
branch's `.tasks/` or root `Taskfile*` differ from `origin/main`'s, `compute` SHALL put
`origin/main`'s versions in the work tree before the task runs, run the task with
`CASCADE_ALLOW_DIRTY=1`, and leave those paths out of the commit, so the task, `pins.sh` and the
body task are always `main`'s. All scratch files SHALL live under `$RUNNER_TEMP/cascade/`, never
in `repo/` or `org-github/`. With an open cascade PR the Notes SHALL be every byte after the
first line equal to `<!-- cascade-notes: the bot keeps everything below this line -->` (one
trailing `\r` removed for the comparison), or the whole old body when no such line exists, and
SHALL be passed to the body task through `CASCADE_NOTES_FILE` unchanged. `compute` SHALL upload
the task's warnings file as `warnings.tsv` in the plan artifact.

#### Scenario: CRLF body is stable

- **WHEN** a human edited the PR body on the web so it has CRLF line ends, and two runs follow with no upstream change
- **THEN** the body after the second run is byte-identical to the body after the first

#### Scenario: Body rewritten by a human

- **WHEN** the open PR's body has no Notes marker line
- **THEN** the whole old body becomes the Notes of the new body

#### Scenario: A branch that edits the task

- **WHEN** a human commit on `deps/cascade` changes `.tasks/cascade/cascade.sh` and `main` moved since
- **THEN** `compute` runs `main`'s `cascade.sh`, and the bot's commit leaves `.tasks/` as the branch has it

## ADDED Requirements

### Requirement: Publish bounds the bot's increment

For `push` and `recreate`, `publish` SHALL take as the bot's increment the new tip's commits that
`origin/main` does not have and, for a `push` whose old tip is an ancestor of the new one, that
the old tip does not have either. It SHALL refuse the plan, before any token exists, when the
increment has more than two commits, a root commit or a commit with more than two parents; when a
commit's author or committer email is not the bot's; when a single-parent commit changes a path
with a status other than `M`, changes a mode, has a mode other than `100644` or `100755` (a
symlink `120000` or gitlink `160000`), or changes a path outside the receiver's allow-list or
inside the deny-list; and when a merge commit's second parent is not on `origin/main` or its tree
differs from `git merge-tree --write-tree` of its parents in a path that is not a derived path
carrying the second parent's content. The allow-lists SHALL live in `.github` (`wiring/lib.sh`),
keyed by the receiver, never read from the receiver's tree. The deny-list SHALL be `.github/**`,
`.tasks/**`, any `Taskfile*`, `hack/**` (except cli's `hack/kind-platform.yaml` and
`hack/platform/cue.mod/module.cue`), `*.sh`, any `CODEOWNERS`, `release-please-config.json`,
`.release-please-manifest.json`, `.cascade-frozen` and `.cascade-hold`, and SHALL win over the
allow-list. When a `push` does not contain the old tip and `origin/main..old` holds a commit the
bot did not make, `publish` SHALL refuse; `recreate` is exempt; `close` SHALL then keep the branch
and delete only a bot-only one.

#### Scenario: A bundle that edits the cascade task

- **WHEN** `compute`'s commit changes `UPSTREAM_VERSION` and `.tasks/cascade/pins.sh`
- **THEN** `publish` refuses naming `.tasks/cascade/pins.sh` and mints no token

#### Scenario: A bundle that edits the Taskfile

- **WHEN** `compute`'s commit changes `Taskfile.yml`
- **THEN** `publish` refuses before the mint

#### Scenario: A symlink

- **WHEN** `compute`'s commit turns an allowed path into a symlink
- **THEN** `publish` refuses before the mint

#### Scenario: A commit the bot did not make

- **WHEN** the bundle's commit has a human committer
- **THEN** `publish` refuses before the mint

#### Scenario: A rebuild over a human commit

- **WHEN** the remote branch holds a human commit and the plan's new tip does not contain it
- **THEN** `publish` refuses with "would drop commits", and `close` keeps such a branch

#### Scenario: Merge mode with a human commit

- **WHEN** the branch holds a human commit that changes `.tasks/` and the bot merges `main` and commits a pin move
- **THEN** `publish` accepts: the human commit is not in the increment, and the bot's merge and pin commits pass

### Requirement: Publish renders the PR text

For `push` and `recreate`, `publish` SHALL check the new tip out into a scratch worktree outside
the repo checkout and run the resolver's `title` and `body` there with the `.github` mirror of the
receiver's `classes` and `pins.sh` (`wiring/pins.sh`, which reads only `git show`), the payload
from the event, the live PR's Notes and `compute`'s warnings after a line filter (at most 100
lines of at most 500 printable bytes with no `<`, `>`, `[`, `]`, `://`, `#<digit>` or bare
mention; dropped lines are counted in one added warning). The final title SHALL be computed from
that title and the live PR; a different planned title SHALL be a notice. The body SHALL be the
one rendered there, never `compute`'s `body.md`; over 65000 bytes, or an empty diff for a push,
SHALL refuse.

#### Scenario: Text planted above the Notes marker

- **WHEN** `compute`'s `body.md` starts with a link and a misleading summary above the Notes marker
- **THEN** the PR body `publish` writes holds the resolver's sections from `.github` code and none of that text

#### Scenario: Notes come from the live PR

- **WHEN** `compute`'s `body.md` carries other text below the Notes marker than the live PR
- **THEN** `publish` keeps the live PR's Notes
