## Context

The cascade docs are parsed by tests and cited from other repos by README heading. Moving them to `references/` keeps the text and changes the address.

## Decisions

- The three caller blocks and the CI step block keep their bold lead-in line, so the tests read them unchanged. The test library joins the `references/cascade-*.md` files into one text and the cases search it.
- The script cites a file name, not a heading: a heading moves, a reference file name is stable.
- The tag-ledger requirement stops asking for a second copy of the repo list: the workflow's list is the live value.
