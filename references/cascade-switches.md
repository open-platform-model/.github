# Cascade switches: dry run, variables and stop

Covers how a receiver is held dry or set live, what each repo variable does and how to stop the
cascade, smallest step first. The caller shapes, the pin procedure and the trust bounds are other
topics.

## The stop switch and the dry run

- The stop switch is the `cascade-publish` input `dry-run`, given the same expression as the
  reusable job's `dry-run`. The action publishes only when it is exactly `false`, does nothing on
  `true` and fails on any other value (an empty or missing input included), so a mistyped `if:`
  cannot make a dry run publish.
- GitHub compares strings without regard to case, so a receiver is live when `CASCADE_DRY_RUN` is
  `false` in any letter case. Any other value keeps it dry.
- A gates-only run never publishes. The `publish` job's `if:` reads the caller's own `gates_only`
  input, and the required `gates-only` input makes the action fail before the mint unless it is
  exactly `false`. A gates-only run runs the code of every open release head inside `compute`, so
  `compute`'s outputs are hints there and everywhere. The reusable workflow also reports
  `action: gates-only` and `compute-ok: false` for such a run, but nothing relies on that.
- The `publish` job's `if:` repeats the switches only so that a dry run does not start a `cascade`
  Environment job. It reads them itself, not from the reusable job that ran repo code.
- `cascade-publish` also refuses any ref but `main` and a plan marked as a dry run.
- `setup-go: true` installs Go from the repo's `go.mod` (opm-controller, cli). `labels-managed: true`
  (cli) only checks that the five cascade labels exist instead of creating them. `setup-cue`
  (default true) and `cue-version` install CUE, and only a version whose sha256 the install script
  holds is accepted.

## Repo variables

| Variable | Repo | Meaning |
| --- | --- | --- |
| `CASCADE_DRY_RUN` | receivers | The receiver pushes only when it is `false`, in any letter case. Unset, deleted or anything else is a dry run (compute, summary and artifact; no push, PR, label or comment). |
| `CASCADE_NOTIFY` | upstreams | `off` skips notify, so that repo's releases stop dispatching. |
| `CASCADE_G2_MODE`, `CASCADE_G3_MODE` | receivers | `warn` (default: a problem posts `success` with `WARN:`) or `enforce` (a problem posts `failure`). |

A run from any ref other than `main`, and every gates-only run, is always a dry run. A manual
dispatch with `dry_run: true` dry-runs that one run.

## Stop switches, smallest first

The `deps-cascade:hold` label on the cascade PR (the bot skips it); a `.cascade-hold` entry (one
pin); `CASCADE_DRY_RUN` set to anything but `false`; `CASCADE_NOTIFY=off` in an upstream; disabling
the deps-cascade workflow; suspending the `opm-cascade` App (notify and publish then fail at
minting, and compute and gates keep running).

## Pitfalls

- Setting `CASCADE_DRY_RUN` to `true` and forgetting to set it back after a dry run.
- Reading a switch from a `compute` output: the caller's own inputs and variables are the only source.
- Using `CASCADE_NOTIFY=off` as a rollout step: it stops that repo's releases from dispatching.
- A mistyped `if:` on the `publish` job: the action's own `dry-run` check is the guard, so keep both.

## Check before you finish

- [ ] The `publish` job's `if:` and the action's `dry-run` input use the same expression.
- [ ] A receiver you changed is dry unless you mean it to publish.
- [ ] `CASCADE_DRY_RUN` is back at its old value.
