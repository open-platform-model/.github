# Cascade trust bounds

Covers what the cascade's `compute` step may do and what it may not, what the `publish` step accepts
before it mints the App token, the receiver mirrors and their drift check, and the risks that stay
open. The scripts are in `.github/scripts/cascade/wiring/`. The workflow shapes, the pin procedure
and the wiring check are other topics.

## Repo code in compute

`compute` runs the receiver's tasks and pin parser (`main`'s, on `main` merged with `deps/cascade`),
the new dependency code those tasks build or run, and, for G2, the task of every open
`release-please--*` head. Any write collaborator can push to either branch. Its two `Read` steps make
every read that needs `GITHUB_TOKEN` (the release-PR list, the release heads' commits, the cascade
PR, the branch tips and the upstream releases for the breaking check) before the first step that runs
repo code. No step from `Gates` on is given a token. Repo code also runs without `GITHUB_ENV`,
`GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `GITHUB_STATE` and every `ACTIONS_*` variable,
so a task that honours them cannot set the step's outputs, environment or `PATH`.

None of this is a boundary inside the job. Hostile code can find the runner's command files on disk,
leave a process running into later steps and rewrite the checked-out scripts. It can plant a git hook
or `core.fsmonitor` in the repo's `.git` (the G2 worktrees share it), which the two checkout post
steps then run with the job's read-only token in their environment. With the runner's `sudo` it can
read that token and the artifact runtime token, and the runtime token also writes the Actions cache
of `main`'s scope. So everything `compute` writes from `Gates` on is untrusted: its `action` and
`compute-ok` outputs, `gates.json`, the plan, the bundle and any cache entry. The bounds that follow
from this:

- `Post gates` posts only on the open release heads it lists itself, takes only G2 from `gates.json`
  and evaluates G3 itself from the API. A release head can choose its own G2 result, which is why G2
  stays `warn`. It cannot choose G3.
- `publish` takes its switches from the caller's inputs and re-derives the plan: what the push may
  change, who made its commits, and the PR's title, body and labels.
- No job that publishes restores an Actions cache. `compute` installs Go with `cache: false`, and the
  wiring check refuses a cache in every workflow a repo lists as publishing. A cache entry written
  from `compute` (or any job on `main` that runs repo code) would otherwise reach a released binary
  or image.
- On a branch that a human merged into (merge mode), `compute` runs `main`'s task. When the branch
  changed `.tasks/` or a root `Taskfile*`, it puts `main`'s versions in the work tree, runs the task
  with `CASCADE_ALLOW_DIRTY=1` and leaves those paths out of its commit.
- `compute` installs Task and CUE with the install script in `wiring/`: fixed release URLs, HTTPS
  only, each archive checked against a sha256 held in this repo. A CUE version without a row there
  fails before any repo code runs. A new version is a change here first.

## What publish accepts

Before it mints the App token, `publish` (the verify mode of the receive-publish script) bounds the
push and writes the PR text itself.

- **The increment.** The bot's own commits are the new tip's commits that neither `main` nor, for a
  fast-forward, the old remote tip has. There are at most two (a merge of `main` and one task
  commit), each authored and committed by the bot. A plain commit may change only paths on the
  receiver's allow-list, in place: status `M`, no mode change, no symlink and no gitlink. The
  allow-list map is in `wiring/lib.sh`, and it is the live value. A merge commit must be git's own
  merge of its parents, with its second parent on `main`, except derived files that carry `main`'s
  content. A deny-list always wins: `.github/**`, `.tasks/**`, any `Taskfile*`, `hack/**` (except the
  CLI's `hack/kind-platform.yaml` and `hack/platform/cue.mod/module.cue`), any `*.sh`, any `CODEOWNERS`, the release-please files,
  `.cascade-frozen` and `.cascade-hold`, and the operator's `modules/**` (its operator module moves
  only through its own deps workflow).
- **Human commits.** A push that does not contain the old tip is refused when the old branch holds a
  commit the bot did not make. A `recreate` over such a branch is refused, and `close` keeps such a
  branch.
- **The text.** `publish` checks the new tip out into a scratch worktree and runs the resolver's own
  `title` and `body` there. It uses a mirror of the receiver's pin parser and classes (which read only
  `git show`), the trigger from the event, the live PR's notes, and `compute`'s warnings after a line
  filter (no HTML, link, URL, issue reference or mention; at most 100 lines of 500 bytes). The labels
  are `deps-cascade`, the pins' labels (`need-human-review` for library's core) and
  `deps-cascade:breaking`, from the mirrored pins and the releases `publish` reads itself. The `body.md`
  and titles from `compute` are hints; a planned title that differs is a notice. The bot never removes
  `need-human-review` or `deps-cascade:breaking`.

## Keeping the mirrors in step

The allow-lists, the pin parsers and the classes copy each receiver's `.tasks/cascade/` on its
`main`. The mirror-source map in `wiring/lib.sh` records the sha256 of every receiver file that the
mirrors copy or were read from: the pin parser, the `lib.sh` it sources, the classes, and the
`cascade.sh` each allow-list was read from. For a push or recreate, `publish` first reads those files
on the receiver's `origin/main`. It refuses, naming the receiver, the file and both hashes, when one
differs. A stale pin mirror or a stale allow-list therefore stops the run before it renders a body or
judges a path.

Code that `cascade.sh` only runs (the CLI's operator pin program, a Taskfile task) is not hashed.
When a change there makes the task write a new path, `publish` still refuses that path as one the
task never writes, and the allow-list needs the same update. The mirror-drift workflow runs the same
comparison daily (read-only, with the run's own token) and fails red on drift.

A receiver change to its `cascade.sh` (or to what its task writes), its pin parser, the `lib.sh` it
sources or its classes needs the matching change here (mirror, allow-list and hash) merged first. The
receiver's change should carry its pin bump to that `.github` commit, so both land together. Until
both have, `publish` refuses that receiver's plans, which is the intended fail-closed state.

To check a mirror, run the receiver's pin parser and the mirror (`CASCADE_PINS_REPO=<repo>
.github/scripts/cascade/wiring/pins.sh`) on the same commits of its checkout and compare. To check an
allow-list, run the receiver's own cascade suite with its sandboxes kept and pass every changed path
through the allow-list function.

## Residual risk

- G2 still runs every open release head's own task inside `compute`, a run on `main`'s ref. That code
  can write `main`'s Actions cache scope. The sink is closed, not the write: no publish workflow
  restores a cache.
- Merge mode runs `main`'s `.tasks/` and root `Taskfile*`, but the rest of the branch tip's code still
  runs in that run: `hack/` programs, scripts the task calls and the `go.mod` toolchain line. Anyone
  who can push to `deps/cascade` gets this, the same class as G2, and the cache sink is closed the
  same way.
- A receiver's own publisher outside the receive workflow and `cascade-publish` (the operator's
  module-deps workflow) gets only its own repo's bounds. Its `publish` job runs in the `release`
  Environment and takes only plain files under `modules/opm_operator/` from `compute`'s artifact. The
  PR title and body still come from `compute`, and its tools are not pinned here. Routing it through
  these workflows needs its own mirror entries.
- `main` requires a pull request but no approval while OPM is in beta, so a write collaborator, or
  the `opm-cascade` bot, can merge a PR whose required checks pass without review, a change to
  `.tasks/cascade/` included.
- One `opm-cascade` key sits in every `cascade` Environment: a leak reaches every receiver at once.
  The workspace `RELEASING.md` holds the rotation response.
- `compute` still chooses the action (push, close, conflict, too long). A hostile `compute` can stall
  or relabel its own receiver's cascade PR as conflicted. It cannot publish anything outside the
  bounds above.
- `setup-go` installs Go from the receiver's `go.mod` version without a checksum held here.

## Pitfalls

- Giving a step after `Gates` a token: nothing from that point is trusted.
- Reading a `compute` output as a switch or as the PR text. `publish` derives both itself.
- Editing a receiver's pin parser or allow-list without the matching mirror and hash change here.
- Adding a path to an allow-list that the deny-list covers: the deny-list wins.
- Restoring an Actions cache in a workflow that publishes.

## Check before you finish

- [ ] No step that runs repo code holds a token, and no publishing job restores a cache.
- [ ] A changed receiver file has its mirror, allow-list and hash changed here.
- [ ] The offline suites pass, including the bound cases for `publish`.
- [ ] A new risk that stays open is listed under Residual risk with its reason.
