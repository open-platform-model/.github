## Context

`harden-cascade-publish` (PR 11, `fe0e11b`) made every `compute` output after the first repo-code
step untrusted and called `publish` the boundary because it "re-derives the plan". The security
pass of 2026-10-04 showed the re-derivation stops at the title shape, the label names and the
workflow paths. This change makes `publish` re-derive what it pushes and writes from `.github`
code and plain git, and closes four smaller gaps (payload tags, tool downloads, forged tags,
merge-mode task code). The supervisor plan (W1-gh, items 1 to 12) is binding; deviations are
listed under Research & Decisions.

Trust model, unchanged: trusted are the caller's inputs and variables, the event payload read by
`.github` code, the `.github` scripts at the pinned SHA, `origin/main`, and what `publish` reads
with git and the API. Untrusted is everything `compute` writes after `Gates`.

## Goals / Non-Goals

**Goals:**

- A bot push can only change the files the receiver's task really writes, with bot-made commits.
- The PR's title, bot section and cascade labels come from `.github` code, never from `compute`.
- A push never discards commits a human made on `deps/cascade`.
- `compute` never runs the branch tip's task code; its tools are pinned by checksum.
- The resolver never proposes a tag that is not on its repo's `main`.
- The wiring check binds the release key to the `release` Environment.

**Non-Goals:**

- G2 out of a `main`-ref run (residual risk, D9).
- Checksums for Go (`setup-go` reads the version from the receiver's `go.mod`; residual, D7).
- Repo settings, rulesets, secrets and the receivers' own workflows (other changes).

## Decisions

### D1. The increment and its checks (items 1, 2, 9)

`verify`, for `push` and `recreate` after the bundle is fetched to `refs/cascade/new`, picks the
range:

| Case | Range |
| --- | --- |
| `recreate`, or no old tip | `git rev-list new ^origin/main` |
| old tip is an ancestor of new (merge mode, an unchanged rebuild) | `git rev-list new ^origin/main ^old` (a merge brings `main`'s commits, which are not the bot's) |
| otherwise (a rebuild replacing a bot-only branch) | `git rev-list new ^origin/main`, after the drop check |

Drop check: when the push does not contain the old tip and the action is `push`, every commit of
`origin/main..old` MUST have `BOT_EMAIL` as author and committer, else "refusing the plan: the
push would drop commits on deps/cascade the bot did not make". `recreate` is exempt (plan item
9). `close` deletes the branch only when that holds; otherwise it closes the PR and keeps the
branch with a notice (`$V/keep-branch`).

Every commit in the range (`git rev-list --parents`):

- at most 2 commits, none a root commit, none with three or more parents;
- author and committer email `BOT_EMAIL`;
- a single-parent commit: `git diff-tree -r -z --raw --no-renames <parent> <commit>`; each entry
  MUST have status `M`, equal old and new modes, a mode of `100644` or `100755`, and a path that
  passes `publish_path_ok <repo> <path>`;
- a two-parent commit: its second parent MUST be an ancestor of `origin/main`; `git merge-tree
  --write-tree --no-messages <p1> <p2>` (exit 0 or 1; anything else refuses) gives the expected
  tree; every path where it differs from the commit's tree MUST pass `is_derived_path` and carry
  the second parent's blob (or be absent on both).

`publish_path_ok` (lib.sh): refuse when the path matches the deny-list, except cli's
`hack/kind-platform.yaml` and `hack/platform/cue.mod/module.cue`; else accept when an ERE of
`publish_paths <repo>` matches.

Deny-list: `.github/*`, `.tasks/*`, any path whose basename starts with `Taskfile`, `hack/*`,
`*.sh`, any basename `CODEOWNERS`, `release-please-config.json`, `.release-please-manifest.json`,
`.cascade-frozen`, `.cascade-hold`.

Allow-lists, read from each receiver's `.tasks/cascade/cascade.sh` on `origin/main` (2026-10-04:
catalog_opm `3288406`, library `93a892f`, opm-operator `6a14adb`, cli `5f00930`):

| Receiver | Paths (ERE, anchored) | From |
| --- | --- | --- |
| all four | `(^\|/)cue\.mod/module\.cue$` | every `cue mod get`/`tidy` and text re-pin |
| catalog_opm | `^\.opm-cli-version$` | the CLI pin |
| library | `^opm/schema/loader\.go$`, `^docs/getting-started\.md$`, `^AGENTS\.md$` | C1 loader, C4 docs examples |
| opm-operator | `^go\.(mod\|sum)$`, `^\.opm-cli-version$`, `^config/samples/opmodel\.dev_v1alpha1_(platform\|moduleinstance)\.yaml$`, `^test/fixtures/catalog\.go$`, `^test/fixtures/(modules/[^/]+\|catalogs/provider)/identity/identity\.cue$`, `^test/fixtures/modules/[^/]+/moduleinstance\.yaml$` | library move, catalog text pins, version setters, consumers, CLI pin |
| cli | `^go\.(mod\|sum)$`, `^internal/operator/(manifest\.go\|dist/install\.yaml)$`, `^hack/kind-platform\.yaml$`, `^(templates/[^/]+\|tests/fixtures/modules/podinfo)/identity/identity\.cue$` | library move, `operator:sync`, kind file, version setters |
| cascade-sandbox-down | `^UPSTREAM_VERSION$`, `^fixtures/` | the toy receiver of the suites |

The `module.cue` rule is broad on purpose: it is data that only names module versions (what the
cascade moves anyway), and the receivers' module lists change often; the deny-list still keeps
it out of `.github/`, `.tasks/` and `hack/`. Every other entry is exact.

### D2. Title, body and labels from `.github` code (items 3, 4)

`wiring/pins.sh <ref|WORKTREE>` is an executable with the resolver's pins interface (TSV
`<pin-key> <display> <class> <version> <labels>`); it reads the receiver from
`CASCADE_PINS_REPO` and calls `receiver_pins` in lib.sh, which reads files with `git show
<ref>:<path>` only (`WORKTREE` means `HEAD`), never the disk. Each receiver's function copies the
parsing of its `pins.sh` on `origin/main`. `receiver_classes <repo>` prints its `classes` lines.

Verify, for `push` and `recreate`:

1. `git worktree add --detach $CASCADE_T/tree refs/cascade/new` (pruned first, removed after).
2. Warnings: `$P/warnings.tsv` from `compute`, if present. Kept are at most 100 lines of at most
   500 bytes, of printable characters and tabs, holding no `<`, `>`, `[`, `]`, `://`, `#<digit>`
   or bare mention; a line without a tab gets the key `-`. When lines were dropped, one line
   `- \t<n> warning line(s) from the task were dropped by the publish filter` is added.
3. Payload: `CASCADE_EVENT` and `CASCADE_PAYLOAD` from the action (the event, not `compute`); a
   valid `repository_dispatch` payload (`validate_payload`) gives `CASCADE_SOURCE` and
   `CASCADE_TAGS`; otherwise none.
4. Notes: `extract_notes` of the live PR body when a cascade PR is open.
5. `cascade-resolve.sh title` and `body --classes $V/classes --pins wiring/pins.sh --base
   origin/main --repo-root $CASCADE_T/tree --warnings <filtered>` with `CASCADE_PINS_REPO`,
   `CASCADE_EXTRA_SOURCES` (`extra_sources`), `CASCADE_NOTES_FILE` and no `CASCADE_WARNINGS`.
   `title` exit 3 refuses ("the new tip has no diff against main"); any other failure refuses.
6. Final title: `final_title` with the live PR and the derived title. A plan title that differs
   is a notice (mirror drift or tampering), not a refusal.
7. Body: over 65000 bytes refuses (compute should have planned `too_long`); the part above the
   Notes marker passes the mention lint.
8. Labels: `deps-cascade`, the body's `cascade-labels` marker (line 2), and
   `deps-cascade:breaking` when `breaking_check` (moved pins of `pins.sh` between
   `merge-base(origin/main, new)` and `new`, releases read with `gh api --paginate
   repos/<org>/<repo>/releases`) says so. When a release read fails, the plan's
   `deps-cascade:breaking`, if any, is kept and a notice names the failure. Other plan labels are
   ignored (still checked to be bot labels).

`act` adds labels only; its one removal stays `deps-cascade:conflict`.

### D3. Merge mode runs `main`'s task (item 5)

In `step_run`, mode `merge` only: when `git diff --quiet origin/main HEAD -- .tasks
':(glob)Taskfile*'` fails, `git restore --source=origin/main --worktree -- <those pathspecs>`
puts `main`'s versions in the work tree (removing branch-only files), the task runs with
`CASCADE_ALLOW_DIRTY=1` (every receiver's task honours it), and the commit stages
`git add -A -- . ':(exclude).tasks' ':(exclude,glob)Taskfile*'`. The overlay stays in the work
tree for `text`, so `pins.sh` and the body task are `main`'s too; later steps read commits only.

### D4. Payload tags (item 6)

`validate_payload` refuses a payload whose `source` or any tag holds a character in
`[\u0000-\u001f\u007f]` (jq), and checks each tag with the bash `valid_tag` read NUL-delimited
(`jq -j '.tags[] | ., "\u0000"'`), whose `[[ =~ ]]` anchors at the end of the string. Oniguruma's
`$` in the old `jq test()` matched before a final newline.

### D5. Tags on `main` (item 8)

`lib/release.sh` gets `on_main <repo> <tag>`: once per repo per run, `git clone --bare --quiet
--filter=tree:0 --no-tags https://github.com/open-platform-model/<repo>` into `$WORK` with the
isolation of `ls_remote_tags` (no system or global config, no credential helper, no prompt), then
`git fetch --filter=tree:0 origin refs/tags/<tag>:refs/tags/<tag>` and `git merge-base
--is-ancestor <tag>^{commit} refs/heads/main`. Answers: on main, not on main, or error (four
attempts like `release_tags`, then exit 1; never a guess).

`newest` calls it in `probe_first` for a published candidate whose pin maps to a tag:
`go github.com/open-platform-model/<repo>[/vN]` (tag `v`), `release <repo>` and `opm-cli` (tag
`v`), `cue opmodel.dev/core@vN` (repo `core`, tag `v`), `cue opmodel.dev/catalogs/opm@vN`
(`catalog_opm`, tag `opm-v`). A candidate not on main is skipped with the warning "`<v>` is
published but its tag is not on `<repo>` main; skipped", and the walk continues to older
candidates. Other kinds (fixtures, templates, oci) have no tag and are not checked. `published`
does not check (it answers a different question).

### D6. Wiring check: the release key (item 10)

In every workflow file: a release-key reader is a job any of whose strings is an expression (or
a whole `if:`) naming `secrets.RELEASE_APP_PRIVATE_KEY` without regard to case or whitespace, or
whose `secrets` is `inherit`. Each reader MUST have `environment: release` (that exact string);
and every job whose environment (string, or a map's `name`) is `release` in any case MUST be a
reader. Mismatches print `release key readers without environment: release` and `environment:
release on jobs that do not read the release key`. No config key is needed: the name is fixed by
owner decision 29. The other `secrets` forms are already refused by the cascade-key rule.

### D7. Pinned tools (item 7)

`wiring/install-tools.sh <cue-version>` (before any repo code; it may write `GITHUB_PATH`):

| Tool | URL | sha256 |
| --- | --- | --- |
| Task v3.53.1 | `https://github.com/go-task/task/releases/download/v3.53.1/task_linux_amd64.tar.gz` | `a54a408f6861ff921f6e87774180db31bacd8c1e7c944ca696db9fea49a82fc7` |
| CUE v0.17.1 | `https://github.com/cue-lang/cue/releases/download/v0.17.1/cue_v0.17.1_linux_amd64.tar.gz` | `a39b0c97695069d95d276d99be0f5dbabb081d801bfdc9ba49b76efaf94e2369` |

Both checksums were read three ways on 2026-10-04: the release's own `task_checksums.txt` (Task),
the GitHub release asset `digest`, and `sha256sum` of the download. `curl -fsSL --proto =https
--retry 3`, `sha256sum -c`, extract one binary into `$RUNNER_TEMP/cascade-tools`, append that
directory to `GITHUB_PATH`. Exit 1 on a download or checksum failure, 2 on a `cue-version`
missing from the table or a runner that is not Linux x64. `setup-cue: false` skips CUE.
`actions/setup-go` stays (SHA-pinned, `cache: false`); its download is not checksummed by
`.github` (residual).

### D8. This repo (item 11)

`.github/CODEOWNERS` holds `/.github/ @emil-jacero @orvis98` (the CODEOWNERS spec, only the path
that exists here). `mention-guard.yml` uses `actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b # v7.1.0`
(the commit `v7` pointed to on 2026-10-04). A static case requires top-level `permissions:` in
every workflow of this repo and a full SHA with a version comment on every `uses:`.

### D9. Residual risk (item 12)

Stated in the README and RELEASING (patch handed to the supervisor):

- G2 still runs every open release head's task inside `compute`, a `main`-ref run. That code can
  write `main`'s Actions cache scope; the sink is closed because no publish workflow restores a
  cache (the publish-workflows rule of the wiring check), not because the write is impossible.
- The `.github` mirrors and allow-lists must follow each receiver's `pins.sh`, `classes` and
  task. Drift makes publish refuse (a red run) or, for a pin the mirror lacks, a body that omits
  that pin; the title-mismatch notice is the signal.
- `compute` still decides the action (push, close, conflict, too_long); a hostile `compute` can
  stall its own receiver, not publish content outside the bounds.
- Go downloads are not checksummed by `.github`.

## Research & Decisions

**Increment versus whole diff.** Checking `new ^origin/main` alone in merge mode would refuse every
human commit on the branch. The bot's own commits are the increment (plan item 1). Considered and
rejected: trusting `plan.mode`, which `compute` writes; the range is derived from the refs.

**Item 9 wording.** The plan says "the new tip contains the old remote tip unless the action is
recreate". Taken literally it refuses every rebuild of a bot-only branch (a force push by
design). Decision: containment is required only when the old branch holds a non-bot commit
(PUB-4's own fix notes); recreate stays exempt.

**`hack/**` versus cli's task.** The plan always refuses `hack/**`, but cli's task writes
`hack/kind-platform.yaml` and `hack/platform/cue.mod/module.cue` (data, run by no workflow with a
write token). Decision: the deny-list keeps `hack/**` with exactly those two cli paths excepted.
Everything else under `hack/` (the Go programs, scripts) stays refused.

**Body: verify compute's, or build our own.** Verifying only the `## Moved pins` section would
still need the pin data, which only repo code (`pins.sh`) produces today. Mirroring `pins.sh` and
`classes` in `.github` (they are small, data-only parsers) lets the resolver render the whole bot
section in `publish` with the same code `compute` uses, so the bytes match on an honest run.
Cost: drift (D9). Rejected: running the receiver's `pins.sh` from `origin/main` in `publish`
(repo code in the job that later holds the App token).

**Tag on main: compare API versus git.** The plan names the compare API (`main...tag`, status
`behind` or `identical`). The resolver's contract is no credentials and never `api.github.com`,
and the anonymous API allows 60 requests an hour per runner IP. A tree-less clone answers the
same question (the tag commit is an ancestor of `main`) through `github.com` git, which the
resolver already uses. Release branches (`release/*`, none exist before GA) are not accepted yet;
the release-branch automation must extend `on_main` when it lands.

**Task version.** `3.x` resolved to v3.54.0 (released 2026-10-01). v3.53.1 (2026-08-18) is the
newest release older than a month; the four receivers' Taskfiles use no newer feature (their own
cascade suites, `CASCADE_TEST_SET=all`, passed with v3.53.1 locally on 2026-10-04).

**Allow-list completeness.** Proven by running each receiver's own offline cascade suite
(`.tasks/cascade/test.sh`) from its `origin/main` in a scratch clone, collecting every path its
scenarios left changed, and checking each against `publish_path_ok` (tasks.md 2.7; results in
the PR body).
