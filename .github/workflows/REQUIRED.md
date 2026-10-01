# Required CI checks

Status-check names that must pass on a pull request into `main`. Machine
list: [`required-checks.txt`](./required-checks.txt). Hosted Actions is the
gate; there is no local commit hook.

GitHub matches the job `name:` string, not the job id. Renaming a `name:`
unhooks branch protection until an admin updates the ruleset **and** this
list. `scripts/gates/check-required-ci-jobs.sh` (in the Lint job) fails the
PR if `required-checks.txt` drifts from `ci.yml`.

| Job id | Check name | What it runs |
| --- | --- | --- |
| `lint` | Lint | `pnpm format:check`, `scripts/verify-gates.sh`, `pnpm lint` |
| `typecheck` | Type Check | `pnpm typecheck`, `pnpm typecheck:tests` |
| `test-unit` | Unit Tests | `pnpm test` |
| `test-integration-1`, `test-integration-2` | Integration Tests (1/2), Integration Tests (2/2) | Each: its own Hatchet Lite and Postgres service containers, a worker token minted in the job, then `pnpm test:integration` with `KYU_INTEGRATION_SHARD` 1 or 2 |
| `self-tests` | Gate Self Tests | `scripts/verify-self-tests.sh`: every `*.test.sh` under `scripts/` and `infra/` |

Every one of these runs on every pull request. None is path-filtered: a
skipped required check counts as passing, which would let a red job merge.

Shard 1 runs the files listed in `vitest.integration.config.ts`; shard 2 runs
every other file. `scripts/gates/check-integration-shards.sh` (in the Lint job)
fails the PR if a file is in no shard or in both.

`against-kyu-main.yml` is not a pull-request check. It runs daily and by hand,
and tests the shop against the packed `main` of `kyuworks/kyu`. Do not add it to
`required-checks.txt` or the ruleset.

## Branch protection

`main` needs a ruleset that requires the six names above, requires a pull
request, and blocks force pushes. Set it in the repository settings; this
file and the gate keep the names honest, they do not create the ruleset.
