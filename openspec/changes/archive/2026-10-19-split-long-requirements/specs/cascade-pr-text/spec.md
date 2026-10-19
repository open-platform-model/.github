## MODIFIED Requirements

### Requirement: Diff and moved pins

`title` and `body` SHALL compare against `M = git merge-base <base> HEAD`. Changed paths SHALL be `git diff --name-only M` plus untracked files that are not ignored. Moved pins SHALL be the keys present in both `SCRIPT M` and `SCRIPT WORKTREE` whose versions differ, in the order of `SCRIPT WORKTREE`. A renamed file SHALL count as both its old and its new path.

#### Scenario: Untracked file counts

- **WHEN** the only change is a new untracked, non-ignored file under `src/`
- **THEN** that path counts as changed

#### Scenario: Pin missing at the base

- **WHEN** a pin key appears in `SCRIPT WORKTREE` but not in `SCRIPT M`
- **THEN** it is not a moved pin

## REMOVED Requirements

### Requirement: Path classification
**Reason**: Split into three requirements that each state one behavior.
**Migration**: See "classify prints the class of each path", "Patterns match in five forms" and "classify exits 1 on a bad line".

### Requirement: Cascade PR title
**Reason**: Split into three requirements that each state one behavior.
**Migration**: See "The title type follows the changed paths", "The title subject names the moved pins" and "An empty diff gives no title".

### Requirement: Cascade PR body
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "The PR body is printed in a fixed layout", "The body labels", "The body table and the counts", "Triggering releases list one line per valid tag", "A dropped value is named only with safe characters", "A source outside the allowlist is dropped", "CASCADE_EXTRA_SOURCES widens the allowlist", "The body warnings" and "The body ends with the Notes".

## ADDED Requirements

### Requirement: title and body take the classes, the pins script and a base ref

`title` and `body` SHALL take `--classes FILE` and `--pins SCRIPT`, with the base ref from `--base`, else `CASCADE_BASE`, else `origin/main`.

#### Scenario: Base ref fallback

- **WHEN** `title` runs with no `--base` and `CASCADE_BASE` unset
- **THEN** the base ref is `origin/main`

### Requirement: A failing pins script fails title and body

A pins script that exits non-zero SHALL make `title` or `body` exit 1.

#### Scenario: Pins script exits non-zero

- **WHEN** the pins script exits non-zero
- **THEN** `title` or `body` exits 1

### Requirement: classify prints the class of each path

`classify --classes FILE` SHALL read paths on stdin and print `<class>\t<path>` for each, where the class is `release-tool`, `test` or `shipped`. `FILE` SHALL hold lines `<class> <pattern>`, with `#` comments and blank lines ignored; the first matching line SHALL win and a path matching no line SHALL be `shipped`.

#### Scenario: Unmatched path is shipped

- **WHEN** the classes file is `test testdata/` and the path is `opm/schema/loader.go`
- **THEN** `classify` prints `shipped` and the path

### Requirement: Patterns match in five forms

Patterns SHALL match as follows: `dir/` every path under `dir/`; a pattern with `/` and no `*` exactly that path; a name with no `/` and no `*` exactly that root-level path; a name with `*` and no `/` a basename glob at any depth; `**/name/` any path with a directory segment `name` at any depth, including the root.

#### Scenario: Basename glob at depth

- **WHEN** the classes file has `test *_test.go` and the path is `opm/kernel/render_test.go`
- **THEN** `classify` prints `test` and the path

#### Scenario: Directory segment at any depth

- **WHEN** the classes file has `test **/testdata/` and the path is `internal/instinit/testdata/initvalues/cue.mod/module.cue`
- **THEN** `classify` prints `test` and the path

#### Scenario: Root-level name only

- **WHEN** the classes file has `release-tool .opm-cli-version` and the path is `sub/.opm-cli-version`
- **THEN** `classify` prints `shipped` and the path

### Requirement: classify exits 1 on a bad line

An unknown class, a line without a pattern, or a pattern that is none of these five forms (for example one with both `/` and `*` other than `**/name/`) SHALL be exit 1 naming the line. The five forms are those of the requirement "Patterns match in five forms".

#### Scenario: Pattern of no known form

- **WHEN** the classes file has `test src/*.cue`
- **THEN** `classify` exits 1 naming that line

#### Scenario: Unknown class

- **WHEN** the classes file has a line with the class `docs`
- **THEN** `classify` exits 1 naming the line

### Requirement: The title type follows the changed paths

`title` SHALL print one line `<type>: <subject>`. The type SHALL be `fix(deps)` if any changed path is `shipped`, else `test(fixtures)` if any is `test`, else `ci(deps)`. The title MUST NOT contain `!` after the type and MUST NOT use any other type.

#### Scenario: Shipped wins over test

- **WHEN** `src/cue.mod/module.cue` (shipped) and `.opm-cli-version` (release-tool) changed, and core moved to `v2.0.0-beta.2`
- **THEN** `title` prints `fix(deps): bump core to v2.0.0-beta.2`

#### Scenario: Release tool only

- **WHEN** only `.opm-cli-version` changed and the opm CLI pin moved to `v1.0.0-beta.7`
- **THEN** `title` prints `ci(deps): bump opm CLI to v1.0.0-beta.7`

### Requirement: The title subject names the moved pins

`title` SHALL print one line `<type>: <subject>`. The subject SHALL be `bump <display> to <to>` for one moved pin, `bump <A> to <a> and <B> to <b>` for two, `bump <A> to <a>, <B> to <b> and <C> to <c>` for three, `bump <N> upstream pins` for four or more, and `refresh cascade-managed files` when paths changed but no pin moved. `<to>` SHALL be v-prefixed.

#### Scenario: Four pins

- **WHEN** four pins moved
- **THEN** the subject is `bump 4 upstream pins`

#### Scenario: Paths changed, no pin moved

- **WHEN** paths changed but no pin moved
- **THEN** the subject is `refresh cascade-managed files`

### Requirement: An empty diff gives no title

With no changed path `title` SHALL print nothing and exit 3.

#### Scenario: Empty diff

- **WHEN** nothing changed against the merge-base
- **THEN** `title` prints nothing and exits 3

### Requirement: The PR body is printed in a fixed layout

`body` SHALL exit 0 and print, deterministically and with no timestamps, exactly these lines, where `<title>` is the `title` output (empty when the diff is empty) and each bracketed part is filled as described below. The lines are those of the scenario "Body layout"; the parts are described in "The body labels", "The body table and the counts", "Triggering releases list one line per valid tag", "The body warnings" and "The body ends with the Notes".

#### Scenario: Same input, same bytes

- **WHEN** `body` runs twice on the same tree and environment
- **THEN** the two outputs are byte-identical

#### Scenario: Empty diff

- **WHEN** nothing changed against the merge-base
- **THEN** `body` exits 0 and its first line is `<!-- cascade-title:  -->`

#### Scenario: Body layout

- **WHEN** `body` runs
- **THEN** it prints exactly these lines:

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

### Requirement: The body labels

`<labels>` SHALL be the union of the moved pins' `labels` columns, each label once, in first-seen order (pins in `SCRIPT WORKTREE` order, labels in column order), joined with `,`; empty when none. `body` SHALL NOT compute `deps-cascade:breaking`.

#### Scenario: Labels from moved pins

- **WHEN** library's core pin, whose pins row carries `need-human-review`, moved
- **THEN** the labels marker reads `<!-- cascade-labels: need-human-review -->`

### Requirement: The body table and the counts

The table SHALL have one row per moved pin, or the single row `| none | - | - | - |`. `<s>`, `<t>` and `<r>` SHALL count the changed paths per class.

#### Scenario: No moved pin

- **WHEN** paths changed but no pin moved
- **THEN** the table's only row is `| none | - | - | - |`

#### Scenario: Counts per class

- **WHEN** paths of the classes `shipped`, `test` and `release-tool` changed
- **THEN** `<s>`, `<t>` and `<r>` count the changed paths per class

### Requirement: Triggering releases list one line per valid tag

Triggering releases SHALL list one line per valid tag in `CASCADE_TAGS` (space-separated) with `CASCADE_SOURCE` as the source. A tag not matching `^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$` SHALL be dropped with a warning. With nothing valid the section SHALL be the single line `- None recorded (daily sweep or manual run).`.

#### Scenario: Hostile tag dropped

- **WHEN** `CASCADE_TAGS` holds `v1.0.0 $(id)`
- **THEN** only `v1.0.0` is listed and a warning names the dropped tag

### Requirement: A dropped value is named only with safe characters

A dropped value SHALL be named only with every character outside `[A-Za-z0-9._/-]` replaced by `?`, so payload text can never fail the mention lint.

#### Scenario: Dropped value with a hostile character

- **WHEN** a dropped tag holds `$(id)`
- **THEN** the warning names it with every character outside `[A-Za-z0-9._/-]` replaced by `?`

### Requirement: A source outside the allowlist is dropped

A source outside `core`, `catalog_opm`, `library`, `opm-operator`, `opm-controller` (the name `opm-operator` takes at its rename), `cli` and the names in `CASCADE_EXTRA_SOURCES` SHALL be dropped with a warning, and its tags with it.

#### Scenario: Unknown source dropped

- **WHEN** `CASCADE_SOURCE` is `evil` and `CASCADE_TAGS` is `v1.0.0`
- **THEN** the section is `- None recorded (daily sweep or manual run).` and a warning names the dropped source

#### Scenario: The renamed repo as a source

- **WHEN** `CASCADE_SOURCE` is `opm-controller` and `CASCADE_TAGS` is `v1.0.0-beta.9`
- **THEN** the section is ``- `opm-controller` `v1.0.0-beta.9` `` and no warning names the source

### Requirement: CASCADE_EXTRA_SOURCES widens the allowlist

`CASCADE_EXTRA_SOURCES` is a space-separated list that only the sandbox receiver sets (to `cascade-sandbox-up`); a name in it that does not match the resolver's repo-name pattern SHALL be ignored with a warning, and when it is unset or empty the allowlist is exactly those six names. The six names are those of "A source outside the allowlist is dropped".

#### Scenario: Sandbox source accepted when listed

- **WHEN** `CASCADE_EXTRA_SOURCES` is `cascade-sandbox-up`, `CASCADE_SOURCE` is `cascade-sandbox-up` and `CASCADE_TAGS` is `v0.2.0`
- **THEN** the section is ``- `cascade-sandbox-up` `v0.2.0` `` and no warning names the source

#### Scenario: Sandbox source dropped when not listed

- **WHEN** `CASCADE_EXTRA_SOURCES` is unset, `CASCADE_SOURCE` is `cascade-sandbox-up` and `CASCADE_TAGS` is `v0.2.0`
- **THEN** the section is `- None recorded (daily sweep or manual run).` and a warning names the dropped source

#### Scenario: Extra name that is not a repo name

- **WHEN** `CASCADE_EXTRA_SOURCES` holds a name that does not match the resolver's repo-name pattern
- **THEN** the name is ignored with a warning

### Requirement: The body warnings

Warnings SHALL be the lines of `--warnings` (default `<git-dir>/cascade/warnings`, which may be missing; an explicit file that is missing SHALL be exit 1) followed by `body`'s own warnings, each `<pin-key>\t<message>`, de-duplicated keeping the first. A key of `-` SHALL render as `- <message>`. With none the section SHALL be `- None.`.

#### Scenario: Explicit warnings file missing

- **WHEN** `--warnings` names a file that is missing
- **THEN** `body` exits 1

#### Scenario: No warnings

- **WHEN** there are no warnings
- **THEN** the Warnings section is `- None.`

### Requirement: The body ends with the Notes

`<notes>` SHALL be the content of `CASCADE_NOTES_FILE`, byte for byte, when it is set and non-empty (a final newline added if missing); otherwise the body SHALL end with the marker line. Notes SHALL NOT be edited or linted (workspace RELEASING.md, section "Title from diff class": a `## Notes` section the bot never edits; Phase 2 cascade contract §11 C1).

#### Scenario: Notes from the file

- **WHEN** `CASCADE_NOTES_FILE` is set and non-empty
- **THEN** the Notes are its content byte for byte, with a final newline added if missing
