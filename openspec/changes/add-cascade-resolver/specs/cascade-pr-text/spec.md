## Purpose

One implementation of the cascade PR's title and body, computed from a repo's diff, its
path-class map and its pin report, so every repo's cascade PR reads the same way. Source:
workspace RELEASING.md, section "Title from diff class", and the Phase 2 cascade contract §4.

## ADDED Requirements

### Requirement: Path classification

`classify --classes FILE` SHALL read paths on stdin and print `<class>\t<path>` for each, where
the class is `release-tool`, `test` or `shipped`. `FILE` SHALL hold lines `<class> <pattern>`,
with `#` comments and blank lines ignored; the first matching line SHALL win and a path matching
no line SHALL be `shipped`. Patterns SHALL match as follows: `dir/` every path under `dir/`; a
pattern with `/` and no `*` exactly that path; a name with no `/` and no `*` exactly that
root-level path; a name with `*` and no `/` a basename glob at any depth; `**/name/` any path with
a directory segment `name` at any depth, including the root. An unknown class SHALL be exit 1.

#### Scenario: Unmatched path is shipped

- **WHEN** the classes file is `test testdata/` and the path is `opm/schema/loader.go`
- **THEN** `classify` prints `shipped` and the path

#### Scenario: Basename glob at depth

- **WHEN** the classes file has `test *_test.go` and the path is `opm/kernel/render_test.go`
- **THEN** `classify` prints `test` and the path

#### Scenario: Directory segment at any depth

- **WHEN** the classes file has `test **/testdata/` and the path is `internal/instinit/testdata/initvalues/cue.mod/module.cue`
- **THEN** `classify` prints `test` and the path

#### Scenario: Root-level name only

- **WHEN** the classes file has `release-tool .opm-cli-version` and the path is `sub/.opm-cli-version`
- **THEN** `classify` prints `shipped` and the path

### Requirement: Diff and moved pins

`title` and `body` SHALL take `--classes FILE` and `--pins SCRIPT`, with the base ref from
`--base`, else `CASCADE_BASE`, else `origin/main`. They SHALL compare against
`M = git merge-base <base> HEAD`. Changed paths SHALL be `git diff --name-only M` plus untracked
files that are not ignored. Moved pins SHALL be the keys present in both `SCRIPT M` and
`SCRIPT WORKTREE` whose versions differ, in the order of `SCRIPT WORKTREE`. A pins script that
exits non-zero SHALL make `title` or `body` exit 1.

#### Scenario: Untracked file counts

- **WHEN** the only change is a new untracked, non-ignored file under `src/`
- **THEN** that path counts as changed

#### Scenario: Pin missing at the base

- **WHEN** a pin key appears in `SCRIPT WORKTREE` but not in `SCRIPT M`
- **THEN** it is not a moved pin

### Requirement: Cascade PR title

`title` SHALL print one line `<type>: <subject>`. The type SHALL be `fix(deps)` if any changed
path is `shipped`, else `test(fixtures)` if any is `test`, else `ci(deps)`. With no changed path
it SHALL print nothing and exit 3. The subject SHALL be `bump <display> to <to>` for one moved
pin, `bump <A> to <a> and <B> to <b>` for two, `bump <A> to <a>, <B> to <b> and <C> to <c>` for
three, `bump <N> upstream pins` for four or more, and `refresh cascade-managed files` when paths
changed but no pin moved. `<to>` SHALL be v-prefixed. The title MUST NOT contain `!` after the
type and MUST NOT use any other type.

#### Scenario: Shipped wins over test

- **WHEN** `src/cue.mod/module.cue` (shipped) and `.opm-cli-version` (release-tool) changed, and core moved to `v2.0.0-beta.2`
- **THEN** `title` prints `fix(deps): bump core to v2.0.0-beta.2`

#### Scenario: Release tool only

- **WHEN** only `.opm-cli-version` changed and the opm CLI pin moved to `v1.0.0-beta.7`
- **THEN** `title` prints `ci(deps): bump opm CLI to v1.0.0-beta.7`

#### Scenario: Four pins

- **WHEN** four pins moved
- **THEN** the subject is `bump 4 upstream pins`

#### Scenario: Empty diff

- **WHEN** nothing changed against the merge-base
- **THEN** `title` prints nothing and exits 3

### Requirement: Cascade PR body

`body` SHALL print, deterministically and with no timestamps, a `<!-- cascade-title: ... -->`
marker holding the title, a `<!-- cascade-labels: ... -->` marker holding the union of the moved
pins' labels, then the sections `## Moved pins` (a table `Pin | Class | From | To`, one row per
moved pin, or the single row `| none | - | - | - |`, followed by the changed-file counts per
class), `## Triggering releases` (from `CASCADE_SOURCE` and `CASCADE_TAGS`, tags not matching
`^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$` dropped with a warning, or
`- None recorded (daily sweep or manual run).`), `## Warnings` (from `--warnings`, default
`<git-dir>/cascade/warnings`, de-duplicated keeping the first, key `-` rendered without a prefix,
or `- None.`) and `## Notes` last, opened by the line
`<!-- cascade-notes: the bot keeps everything below this line -->` and followed by
`CASCADE_NOTES_FILE`'s content when set and non-empty. It SHALL NOT compute
`deps-cascade:breaking`.

#### Scenario: Labels from moved pins

- **WHEN** library's core pin, whose pins row carries `need-human-review`, moved
- **THEN** the labels marker reads `<!-- cascade-labels: need-human-review -->`

#### Scenario: Same input, same bytes

- **WHEN** `body` runs twice on the same tree and environment
- **THEN** the two outputs are byte-identical

#### Scenario: Hostile tag dropped

- **WHEN** `CASCADE_TAGS` holds `v1.0.0 $(id)`
- **THEN** only `v1.0.0` is listed and a warning names the dropped tag

### Requirement: Mention lint and Notes neutralization

Before printing, `title` and `body` SHALL check the whole title and the body above the
`cascade-notes` marker against `(?<![\w@])@[A-Za-z0-9]`, and exit 1 naming the line on a match.
In Notes, every `@` matching that pattern SHALL get a U+200D zero-width joiner inserted right
after it, and the body SHALL add the warning "neutralized <n> mention(s) in Notes" under key `-`.
Neutralization SHALL be idempotent.

#### Scenario: Module path passes

- **WHEN** a warning line contains `opmodel.dev/core@v2`
- **THEN** the lint passes

#### Scenario: Planted bare mention fails

- **WHEN** a warning in the generated part contains ` @octocat`
- **THEN** `body` exits 1 naming the offending line

#### Scenario: Mention in Notes neutralized

- **WHEN** `CASCADE_NOTES_FILE` contains `ping @octocat`
- **THEN** `body` exits 0, the Notes text has a zero-width joiner after that `@`, and a second run over that output adds no further joiner
