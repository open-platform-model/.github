# open-platform-model/.github

The org meta repo of Open Platform Model. It holds the pull request workflow that the organization
requires, a daily drift check for release tags, a shared lint workflow and the code of the release
cascade. Other repos use its workflows and scripts at `main`, or at a pinned commit of `main`. It has
no release of its own.

## What is here

| Part | What it does | Detail |
| --- | --- | --- |
| `mention-guard` | Required on every pull request in the org. Fails a PR whose title, body or commit messages hold a bare `@mention`, a session identifier, a generated-with footer or an embellished AI co-author trailer. | [references/mention-guard.md](references/mention-guard.md) |
| `tag-ledger` | Daily check that no release tag moved, vanished or changed, and that the org tag rulesets still apply. Opens an issue on drift. | [references/tag-ledger.md](references/tag-ledger.md) |
| `cite-lint` | Reusable workflow that checks the Go and CUE comments of the calling repo for enhancement citations. | [references/cite-lint.md](references/cite-lint.md) |
| Release cascade | Scripts, two reusable workflows and two composite actions that carry a new upstream release into the pins of the downstream repos as one rolling PR. | see below |

## The release cascade

When an upstream repo publishes a release, the cascade finds the new version, moves the downstream
pins and opens or updates one `deps/cascade` PR in each receiving repo. The design is in the
workspace `RELEASING.md`. The detail is split by topic:

- [The resolver](references/cascade-resolver.md): which version a pin moves to.
- [The workflows and callers](references/cascade-workflows.md): the parts and the caller shapes.
- [Switches](references/cascade-switches.md): dry run, repo variables and how to stop the cascade.
- [Trust bounds](references/cascade-security.md): what `compute` may do, what `publish` accepts, the
  receiver mirrors and the risks that stay open.
- [Pinning and rollout](references/cascade-pinning.md): how a product repo moves to a new commit of
  this repo.
- [The wiring check](references/cascade-wiring-check.md): the script that holds every repo's callers
  to one shape.

## How other repos use it

- The org ruleset runs `mention-guard` from `main` here. An edit on `main` reaches every repo at once.
- A product repo calls the cascade workflows and actions at a full commit SHA of `main` here, and a
  merge here changes nothing for it until it moves its pin.
- A repo calls `cite-lint` at a full SHA too.
- `tag-ledger` runs here and only reads the repos it scans.

## Working in this repo

Every change lands by pull request. Read `AGENTS.md` for the rules, the layout and the checks to run
before you push.
