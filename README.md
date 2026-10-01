# tag-ledger

Append-only record of every release tag in the open-platform-model repos that
release, written by `.github/workflows/tag-ledger.yml` on `main`. Rows are
only ever appended; never edit, reorder or delete one, and never delete or
force-push this branch. Each run proves the branch head descends from the
commit the previous run ended on and that no row changed; anything else
fails the run. Acknowledgements of reviewed drift are not kept here: they go
by PR into `tag-ledger/acknowledged.tsv` on the default branch.
