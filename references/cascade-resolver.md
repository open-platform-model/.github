# The cascade resolver

Covers the one script that answers which upstream version a pin moves to: how repos find it, its
subcommands and exit codes, the tag-on-main rule, the stub and its tests. The scripts are in
`.github/scripts/cascade/`. The workflows around it, the pin procedure and the wiring check are
other topics.

## What it is

The resolver is the one implementation that every repo's `task deps:cascade` and the cascade receive
workflow ask three things: which upstream version a pin moves to, whether a pin is held or frozen,
and what the cascade PR is called. The design is the cascade part of the workspace `RELEASING.md`. The interface is fixed by the
resolver contract, kept with the archived change `add-cascade-resolver` in `openspec/changes/archive/`.

**How repos find it.** A repo task uses `CASCADE_RESOLVER` when it is set (an absolute path).
Otherwise it uses the resolver in a `.github` checkout beside the repo (`../.github` from the main
checkout), so a laptop needs only the sibling checkout. CI checks this repo out at the repo's cascade
pin beside the repo it works on.

## Subcommands and exit codes

The subcommands are `newest`, `published`, `pin-of`, `language-of`, `frozen`, `is-frozen`, `hold`,
`check-files`, `tag-on-main`, `semver-cmp`, `semver-sort`, `next-patch`, `classify`, `title` and
`body`. The script header lists their arguments. Query kinds: `cue` (GHCR), `go` (the Go proxy),
`release` and `opm-cli` (git tags plus anonymous release downloads) and `oci` (published only).
Versions are always `v`-prefixed SemVer.

| Exit | Meaning |
| --- | --- |
| 0 | Success. For `newest`, a newer version was printed. For a predicate, yes. |
| 3 | Nothing to do, or no. For `title`, the diff is empty. |
| 1 | Error: network after retries, an unexpected status, a malformed `.cascade-*` file, a missing tool, the mention lint. Never a guessed version. |
| 2 | Usage error. |

It needs `bash`, `curl`, `jq`, `git` and mikefarah `yq` v4, and no credentials. It sends no token
anywhere but GHCR's own anonymous pull token to `ghcr.io`, and it never calls `api.github.com`.

## Tags must be on main

`newest` proposes only a version whose release tag is on its repo's `main`. This holds for every pin
whose versions are tags of an org repo: the Go modules of org repos, `release`, `opm-cli`, and the
CUE modules whose tags an org repo makes (core, the opm catalog and the operator module). A tag made
on a commit that `main` never had (the release App can create one) is still served by the Go proxy
and listed by git. So `newest` clones the repo once per run, bare and without trees, fetches each
probed tag and skips, with a warning, one whose commit is not an ancestor of `main`.

`tag-on-main <pin-key> <v>` answers the same for one version: exit 0 on `main` or when there is no
tag to check, 3 when not. The receive publish script runs it on every pin that the new tip moves,
because the compute step reaches `newest` only through repo code. Release branches (`release/*`) are
not accepted yet. The release-branch automation extends this check when it lands.

## The stub

`stub-resolve.sh` is the canonical stub that the repos copy byte for byte into
`.tasks/cascade/testdata/`. The suite checks the stub's checksum and that the stub and the real
resolver agree on every case the stub supports. Changing the stub means a new contract version and a
new checksum in every copy.

## Tests

- `bash .github/scripts/cascade/test/run.sh` runs the resolver suite.
- `bash .github/scripts/cascade/wiring/test/run.sh` runs the suite for the workflows' scripts. It
  also needs go-task.

`curl` and `git` are PATH shims that answer from `test/fixtures/`, captured from the real services.
Sleep and the date are faked, and nothing touches the network. The resolver-tests workflow runs
pinned `shellcheck`, `actionlint`, go-task and OpenSpec releases, the OpenSpec validation of the specs and both suites on every PR and push to
`main`, with no path filter, as the job `Resolver tests`. The owner adds that job to the ruleset on
`main` of this repo. A live workflow checks read-only invariants against GHCR and GitHub weekly and
on dispatch, and a drift workflow checks the publish mirrors daily. Neither is ever required.

## Pitfalls

- Printing a version when the network fails: the resolver exits 1 and never guesses.
- A fixture edited by hand: fixtures are captured from the real services. Capture them again.
- Changing the stub in one repo copy: all copies stay byte-identical to the canonical stub.
- A path filter on the resolver-tests job: it is a required check and must report on every PR.

## Check before you finish

- [ ] Both offline suites pass, and `shellcheck` is clean on every script you touched.
- [ ] A new subcommand has its arguments in the script header and a suite case.
- [ ] A change of the stub has a new checksum and a note for every copying repo.
- [ ] No test needs the network.
