## Purpose

One implementation of the cascade PR's title and body, computed from a repo's diff, its
path-class map and its pin report, so every repo's cascade PR reads the same way. Source:
workspace RELEASING.md, section "Title from diff class", and the Phase 2 cascade contract,
version 1, §4 (kept with this change as `contract.md`).

## ADDED Requirements

### Requirement: Path classification

`classify --classes FILE` SHALL read paths on stdin and print `<class>\t<path>` for each, where
the class is `release-tool`, `test` or `shipped`. `FILE` SHALL hold lines `<class> <pattern>`,
with `#` comments and blank lines ignored; the first matching line SHALL win and a path matching
no line SHALL be `shipped`. Patterns SHALL match as follows: `dir/` every path under `dir/`; a
pattern with `/` and no `*` exactly that path; a name with no `/` and no `*` exactly that
root-level path; a name with `*` and no `/` a basename glob at any depth; `**/name/` any path with
a directory segment `name` at any depth, including the root. An unknown class, a line without a
pattern, or a pattern that is none of these five forms (for example one with both `/` and `*`
other than `**/name/`) SHALL be exit 1 naming the line.

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

#### Scenario: Pattern of no known form

- **WHEN** the classes file has `test src/*.cue`
- **THEN** `classify` exits 1 naming that line

### Requirement: Diff and moved pins

`title` and `body` SHALL take `--classes FILE` and `--pins SCRIPT`, with the base ref from
`--base`, else `CASCADE_BASE`, else `origin/main`. They SHALL compare against
`M = git merge-base <base> HEAD`. Changed paths SHALL be `git diff --name-only M` plus untracked
files that are not ignored. Moved pins SHALL be the keys present in both `SCRIPT M` and
`SCRIPT WORKTREE` whose versions differ, in the order of `SCRIPT WORKTREE`. A renamed file
SHALL count as both its old and its new path. A pins script that
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

`body` SHALL exit 0 and print, deterministically and with no timestamps, exactly these lines,
where `<title>` is the `title` output (empty when the diff is empty) and each bracketed part is
filled as described below:

```
<!-- cascade-title: <title> -->
<!-- cascade-labels: <labels> -->
## Moved pins

| Pin | Class | From | To |
| --- | --- | --- | --- |
| <display> (`<pin-key>`) | <class> | `<from>` | `<to>` |

Changed files: <s> shipped, <t> test, <r> release-tool.

## Triggering releases

- `<source>` `<tag>`

## Warnings

- `<pin-key>`: <message>

## Notes

<!-- cascade-notes: the bot keeps everything below this line -->
<notes>
```

- `<labels>` SHALL be the union of the moved pins' `labels` columns, each label once, in
  first-seen order (pins in `SCRIPT WORKTREE` order, labels in column order), joined with `,`;
  empty when none. `body` SHALL NOT compute `deps-cascade:breaking`.
- The table SHALL have one row per moved pin, or the single row `| none | - | - | - |`.
- `<s>`, `<t>` and `<r>` SHALL count the changed paths per class.
- Triggering releases SHALL list one line per valid tag in `CASCADE_TAGS` (space-separated) with
  `CASCADE_SOURCE` as the source. A source outside `core`, `catalog_opm`, `library`,
  `opm-operator` and `cli` SHALL be dropped with a warning, and its tags with it. A tag not
  matching `^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$` SHALL be dropped with a warning. A dropped
  value SHALL be named only with every character outside `[A-Za-z0-9._/-]` replaced by `?`, so
  payload text can never fail the mention lint. With nothing
  valid the section SHALL be the single line `- None recorded (daily sweep or manual run).`.
- Warnings SHALL be the lines of `--warnings` (default `<git-dir>/cascade/warnings`, which may
  be missing; an explicit file that is missing SHALL be exit 1) followed by `body`'s own warnings, each `<pin-key>\t<message>`, de-duplicated
  keeping the first. A key of `-` SHALL render as `- <message>`. With none the section SHALL be
  `- None.`.
- `<notes>` SHALL be the content of `CASCADE_NOTES_FILE`, byte for byte, when it is set and
  non-empty (a final newline added if missing); otherwise the body SHALL end with the marker
  line. Notes SHALL NOT be edited or linted (workspace RELEASING.md, section "Title from diff
  class": a `## Notes` section the bot never edits; Phase 2 cascade contract §11 C1).

#### Scenario: Labels from moved pins

- **WHEN** library's core pin, whose pins row carries `need-human-review`, moved
- **THEN** the labels marker reads `<!-- cascade-labels: need-human-review -->`

#### Scenario: Same input, same bytes

- **WHEN** `body` runs twice on the same tree and environment
- **THEN** the two outputs are byte-identical

#### Scenario: No moved pin

- **WHEN** paths changed but no pin moved
- **THEN** the table's only row is `| none | - | - | - |`

#### Scenario: Empty diff

- **WHEN** nothing changed against the merge-base
- **THEN** `body` exits 0 and its first line is `<!-- cascade-title:  -->`

#### Scenario: Hostile tag dropped

- **WHEN** `CASCADE_TAGS` holds `v1.0.0 $(id)`
- **THEN** only `v1.0.0` is listed and a warning names the dropped tag

#### Scenario: Unknown source dropped

- **WHEN** `CASCADE_SOURCE` is `evil` and `CASCADE_TAGS` is `v1.0.0`
- **THEN** the section is `- None recorded (daily sweep or manual run).` and a warning names the dropped source

### Requirement: Mention lint

Before printing, `title` and `body` SHALL check the whole title and every body line above the
`cascade-notes` marker against `(?<![\w@])@[A-Za-z0-9]`, and exit 1 naming the line on a match,
printing nothing on stdout. Notes below the marker SHALL pass through unchanged. A lint that
cannot run (grep exits other than 0 or 1, for example a grep without `-P` support) SHALL exit 1;
it MUST NOT be read as "no match".

#### Scenario: Module path passes

- **WHEN** a warning line contains `opmodel.dev/core@v2`
- **THEN** the lint passes

#### Scenario: Planted bare mention fails

- **WHEN** a warning in the generated part contains ` @octocat`
- **THEN** `body` exits 1 naming the offending line

#### Scenario: Lint that cannot run fails

- **WHEN** the `grep` on `PATH` exits 2 on `-P`
- **THEN** `title` and `body` exit 1 with `mention lint: grep -P failed` and print nothing on stdout

#### Scenario: Mention in Notes passes through

- **WHEN** `CASCADE_NOTES_FILE` contains `ping @octocat`
- **THEN** `body` exits 0 and the Notes text is byte-identical to the file
