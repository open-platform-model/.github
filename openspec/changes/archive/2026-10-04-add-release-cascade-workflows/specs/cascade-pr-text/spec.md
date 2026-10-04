## MODIFIED Requirements

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
  `opm-operator`, `cli` and the names in `CASCADE_EXTRA_SOURCES` SHALL be dropped with a
  warning, and its tags with it. `CASCADE_EXTRA_SOURCES` is a space-separated list that only the
  sandbox receiver sets (to `cascade-sandbox-up`); a name in it that does not match the
  resolver's repo-name pattern SHALL be ignored with a warning, and when it is unset or empty
  the allowlist is exactly the five repos. A tag not
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

#### Scenario: Sandbox source accepted when listed

- **WHEN** `CASCADE_EXTRA_SOURCES` is `cascade-sandbox-up`, `CASCADE_SOURCE` is `cascade-sandbox-up` and `CASCADE_TAGS` is `v0.2.0`
- **THEN** the section is ``- `cascade-sandbox-up` `v0.2.0` `` and no warning names the source

#### Scenario: Sandbox source dropped when not listed

- **WHEN** `CASCADE_EXTRA_SOURCES` is unset, `CASCADE_SOURCE` is `cascade-sandbox-up` and `CASCADE_TAGS` is `v0.2.0`
- **THEN** the section is `- None recorded (daily sweep or manual run).` and a warning names the dropped source
