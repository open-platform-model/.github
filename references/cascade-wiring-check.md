# The cascade wiring check

Covers the check that holds every product repo's cascade callers to one shape: where it lives, the
CI step that runs it, everything it refuses, its per-repo config, how a repo's copy stays in step and
what to do when its API call fails. The check is `.github/scripts/cascade/wiring-check.sh`, with its
tests in `wiring/test/`. The callers' shapes, the trust bounds and the pin procedure are other topics.

## What it is

One script checks every product repo's caller shapes. Each repo runs a byte-identical copy at
`.tasks/cascade/wiring-check.sh`, with its own values in `.tasks/cascade/wiring-check.yaml`. It runs
offline through `task cascade:wiring:check`, and online in a step of the repo's required CI job.

**The wiring check.** The online step is:

```yaml
      - name: Verify the cascade wiring
        env:
          GH_TOKEN: ${{ github.token }}
        run: bash .tasks/cascade/wiring-check.sh --pin-on-main
```

Only SHA-pinned actions (checkout, setup) may come before it. Every `run:` step goes after it. Where a step before it writes to `GITHUB_ENV`, the next pin bump moves the wiring step above that
step. Tests in `wiring/test/` read this block from this file to prove the CI step that the check
requires, so keep the bold lead-in line and the fenced block as they are.

The script prints every mismatch and exits 1, or prints `cascade wiring: ok, .github <SHA> (<pin
comment>)`. Offline (without `--pin-on-main`) a second line says `the copy was not compared`. A bad
config exits 2.

## What it refuses

- A workflow file that uses a YAML anchor or alias (GitHub resolves them, the check reads text).
- Key-holding jobs (`notify-downstream`, `publish`) that differ from the contract: exact job and step
  keys, names, timeouts, `environment: cascade`, `runs-on: ubuntu-latest`, permissions, one
  SHA-pinned cascade action with exact inputs, the client id and the key. Notify's `needs`, `if:` and
  `tag` come from the config. Publish's `needs`, `if:` (with the gates-only clause), `dry-run`,
  `gates-only` and `labels-managed` (a YAML boolean, from the config) are checked too.
- A top-level `env` of the release workflow that is not a map, or has a key off the config's
  `env-allow`.
- For a receiver: the triggers, permissions, concurrency and jobs of the deps-cascade and
  cascade-gates workflows, and a `cascade` job that passes an input the receive workflow does not take.
- In every workflow: the App key read outside the key-holding jobs. A reader is any expression that
  names it in any case or uses the secrets context other than as `secrets.<name>` (`secrets[...]`
  with any index, `format()`, `secrets.*`, `toJSON(secrets)` and any other function given the whole
  context). The `cascade` Environment (any case, a map or an expression) outside those jobs. A call
  into `.github` (in any case) that passes `secrets:`.
- In every workflow: a job that reads the release App key (`RELEASE_APP_PRIVATE_KEY`, named in any
  case, or `secrets: inherit`) without declaring exactly `environment: release`, the main-only
  Environment that holds the key. Any other job that declares `release`. A read outside a job.
- In every workflow the config's `publish-workflows` lists: any cache action (any action whose name
  says `cache`), `actions/setup-go` without `cache: false`, `actions/setup-node` without
  `package-manager-cache: false` or with `cache`, any other `cache*` input but `no-cache`, and any
  `type=gha` (buildx `cache-from` and `cache-to`). A reusable workflow called from there is not
  checked. The docs-kit publish workflow sets `cache: false` itself.
- A `.github` reference without one full SHA and the pin comment, matched in any case (the four
  `uses:`, the cascade-task resolver `ref:`, and each resolver checkout the config's
  `extra-references` declares), and any other reference.
- A checkout of `.github` (a step whose `with.repository` is any owner's `.github`, in any case) that
  is not `actions/checkout@<full SHA>` with exactly `repository`, `ref`, `path` and
  `persist-credentials: false`, so no token or SSH key reaches it. A step whose `repository` input is
  an expression (`${{ github.repository_owner }}/.github` would name `.github` unseen). A `run:` step
  that names `open-platform-model/.github`, or an expression or owner variable followed by `/.github`
  (a `git clone` past the pinned checkouts).
- A CI job that does not run the step above as exactly that step on every pull request: no path
  filter, no `if:` or `continue-on-error`, no `shell` or `working-directory` of its own or from
  `defaults`.
- Anything that reaches the step from around it: the CI workflow's and job's `env` must be plain maps
  whose names are only `CUE_*`, `OPM_*`, `REGISTRY` or `IMAGE_NAME` (so no `BASH_ENV`, `CASCADE_GH` or
  `PATH`). The job has no `container` or `services`. Every step before the wiring step is an action
  from another repo at a full SHA with only `id`, `name`, `uses` and `with`. With `--pin-on-main` it
  also exits 1 when `BASH_ENV` or `ENV` is set, a tripwire only, since bash reads `BASH_ENV` before
  the script runs.
- With `--pin-on-main`, after every shape matched: `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status`
  must print `identical` or `ahead`, so a commit that exists only in a fork (which GitHub also
  resolves under this repo's name) is refused. Then the contents API at the pinned SHA, with the
  `application/vnd.github.raw` accept header, must return exactly the bytes of the script that is
  running, so a copy that drifted or was not replaced at a pin bump fails with `differs from`.

## The config

The config is data, read with `yq`, never run. `env-allow` may name only `CUE_*`, `OPM_*`, `REGISTRY`
and `IMAGE_NAME`: a workflow-level env reaches the notify action's steps, which hold the App token,
and too many other names make bash, git, gh, node, curl or the loader run code or send traffic
elsewhere (`BASH_ENV`, `GIT_*`, `GH_*`, `NODE_*`, `LD_*`, `XDG_*`, `SSL_*`, `*_PROXY` and more) for a
deny-list to be safe. `publish-workflows` must list the release workflow. `extra-references`
(optional) lists more pinned `.github` references, one item per reference, each a map of exactly
`file` (a workflow file name) and `kind`. The kinds are `resolver` (a checkout of `.github` held to
the rules above, receivers only) and `cite-lint` (a job that calls the cite-lint workflow, any
repo). A file appears at most once per kind, and never as the release, deps-cascade, cascade-gates or
cascade-task workflow, which hold the fixed references. A new kind (another action or reusable
workflow call) is a change here, never a config entry.

`pin-comment` is `.github main` everywhere. `notify.if` and `notify.tag` are each repo's own release
workflow values. Only opm-operator sets `extra-references`, for the resolver checkout in its
module-deps workflow. Each repo's values at the time of writing:

| Repo | `receiver` | `env-allow` | `publish-workflows` | `ci` (workflow, job) | `notify.needs` | `labels-managed` |
| --- | --- | --- | --- | --- | --- | --- |
| core | `false` | `CUE_VERSION`, `CUE_REGISTRY` | `release.yml`, `branch-publish.yml`, `docs.yml` | `ci.yml`, `ci` | `release-please`, `publish-cue` | (none) |
| catalog_opm | `true` | `OPM_REGISTRY`, `CUE_REGISTRY` | `release.yml`, `branch-publish.yml`, `docs.yml` | `ci.yml`, `ci` | `release-please`, `publish-cue` | `false` |
| library | `true` | (none) | `release.yml`, `docs.yml` | `test.yml`, `test` | `release-please` | `false` |
| opm-operator | `true` | `REGISTRY`, `IMAGE_NAME`, `CUE_VERSION` | `release.yml`, `publish-fixtures.yml`, `docs.yml`, `image-pr.yml`, `test-e2e.yml`, `module-image.yml`, `module-deps.yml` | `lint.yml`, `lint` | `release-please`, `publish-release` | `false` |
| cli | `true` | (none) | `release.yml`, `publish-fixtures.yml`, `docs.yml` | `pr.yml`, `lint` | `release-please`, `goreleaser` | `true` |

catalog_opm's file, for example:

```yaml
pin-comment: .github main
receiver: true
env-allow: [OPM_REGISTRY, CUE_REGISTRY]
publish-workflows: [release.yml, branch-publish.yml, docs.yml]
ci:
  workflow: ci.yml
  job: ci
notify:
  needs: [release-please, publish-cue]
  if: ${{ !cancelled() && needs.publish-cue.outputs.published == 'true' && vars.CASCADE_NOTIFY != 'off' }}
  tag: ${{ needs.release-please.outputs.opm_tag_name }}
publish:
  labels-managed: false
```

## Keeping the copy in sync

A repo's copy is the file at the `.github` SHA its cascade references pin, and it moves only with the
pin. The pin-bump PR replaces it with:

```sh
sha=<the new .github SHA>
gh api "repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=$sha" \
  -H 'Accept: application/vnd.github.raw' >.tasks/cascade/wiring-check.sh
```

The PR's diff of the copy is then exactly the change here between the two SHAs. A reviewer confirms
it with the same `gh api` call piped to `cmp - .tasks/cascade/wiring-check.sh`. A change to the check
is made here, never in a copy.

The required CI step makes the same comparison, so a copy that differs from the file at the pin fails
CI on every PR. The comparison runs from the copy under test, though. It catches drift and a copy
left behind at a bump, but it does not replace review. A PR can pass an edited copy by also deleting
the comparison, or by changing what runs around the CI step. The shape rules refuse the plain routes
(env, a container or service, a `run:` step before the wiring step). An earlier SHA-pinned action can
still set the step's environment through `GITHUB_ENV` or `GITHUB_PATH`. So a reviewer reads any
change to the CI workflow, and to the copy, as a change to the check. The copy and the config live in
the repo's own tree, so a PR can change them along with the workflows: the check guards against
mistakes, and only review guards against a deliberate edit. CODEOWNERS on `/.tasks/` requests that
review, but while OPM is in beta the `main` ruleset requires a pull request and no approval, so
nothing enforces it.

## When the API call fails

The required step makes two GitHub API requests (the compare, then the contents read of the pinned
file). A GitHub outage, a secondary rate limit or the job token's hourly limit fails the required job
on every PR with `cannot compare .github <SHA> with main` or `cannot fetch
.github/scripts/cascade/wiring-check.sh at .github <SHA>`. Only those two messages can be outages.
`cannot compare` is also what a SHA that GitHub does not know prints (the compare returns 404), and
that is a finding.

1. Confirm the SHA exists: `gh api repos/open-platform-model/.github/commits/<SHA> --jq .sha` must
   print the SHA. A 404 or 422 is a pin to fix, never an outage; skip the steps below. If this call
   fails for the outage itself, re-run it until it answers.
2. Re-run the failed job (`gh run rerun <run id> --failed -R open-platform-model/<repo>`).
3. Check the GitHub status page and `gh api rate_limit`. Wait for the reset or the recovery and
   re-run again.
4. If it lasts, step 1 printed the SHA and a merge cannot wait, an admin may merge with admin bypass
   (`gh pr merge --admin`) only a PR whose changed files (`gh pr diff <n> --name-only`) include
   nothing under `.github/**` or `.tasks/**`. Every other required check must have passed, and
   `task cascade:wiring:check` must have passed on the PR head. A PR that touches those paths waits
   for the API.
5. Never remove `--pin-on-main` from the step (the check refuses that shape anyway), and never edit
   the copy to skip a request.

`is not on .github main` and `differs from` are findings, not outages. Fix the pin or the copy, and
never bypass them.

## Pitfalls

- Editing a repo's copy of the script: change the check here and move the pin.
- Putting a `run:` step, an `env` name or a container before the wiring step.
- A config `env-allow` name outside the four allowed patterns: a deny-list cannot be safe.
- A new caller kind added as a config entry: a new kind is a change here.
- Bypassing a `differs from` or `is not on .github main` failure.

## Check before you finish

- [ ] The wiring suite passes, with a refusal case for every new rule.
- [ ] The CI step block above still equals the step the check requires.
- [ ] A change of a shape here comes with the matching caller block, and the pin PR order is stated.
- [ ] A new rule has a reason in this file.
