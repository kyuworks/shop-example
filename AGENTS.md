# Agent notes — shop example

This repository is the shop: the test application for `@kyuworks/sdk`, the company message bus. It installs the SDK from npm and acts as a real project would. The SDK lives in `kyuworks/kyu`; do not open issues, PRs or automation against any other repository from here, and never change the SDK from here. If the SDK lacks something, ask for it in `kyuworks/kyu`.

## Rules

- **Imports.** `@kyuworks/sdk` only. Never `@hatchet-dev/*`, never `@kyuworks/schemas`, never a deep path (`@kyuworks/sdk/dist/...`). Gate: `scripts/gates/check-consumer-imports.sh`.
- **Messages carry ids and small discriminators.** No personal data enters the bus.
- **Delivery is at-least-once.** Every handler is idempotent on the envelope id, naturally or through `onceById()`.
- **Durable handler bodies re-run from the top.** Read the time with `ctx.now()`, never `Date.now()` or `new Date()`. Gate: `check-durable-wall-clock.sh`.
- **Migrations are append-only.** New file `migrations/000N_shop.sql`; never edit, rename or delete one that exists on `main`. List it in `src/__tests__/migrate.integration.test.ts` (the list and the ledger count). Gate: `check-migration-immutability.sh`.
- **No escape hatches** in production source: `as any`, `as unknown as`, `@ts-ignore`, `@ts-expect-error`, lint-disable comments. Gate: `check-no-escape-hatches.sh`. Lint is oxlint at error with the anti-slop preset in `oxlint-rules/`; fix the code, do not silence a rule.
- **Do not weaken a gate to land a change.** A gate that is wrong is fixed in its own PR.

## Running things

- Normal loop: `pnpm typecheck`, `pnpm typecheck:tests`, `pnpm test`, `pnpm lint`, `pnpm format:check`, `pnpm gates`, `pnpm self-tests`. CI runs all of them; there is no commit hook.
- Integration tests need the local engine (`pnpm hatchet:up`, Docker) and these variables: `HATCHET_CLIENT_TOKEN="$(bash infra/hatchet/token.sh)"`, `HATCHET_CLIENT_TLS_STRATEGY=none`, `KYU_SHOP_DATABASE_URL=postgresql://hatchet:hatchet@localhost:15432/kyu_shop_<lane>`, `KYU_SHOP_NAMESPACE=<lane>_`. They fail loudly when the engine or database is missing; they never skip. Run one file at a time: `pnpm exec vitest run --config vitest.integration.config.ts <file>`. Run `pnpm build` after source edits and `node dist/bin/migrate.js` after a migration, because the integration files and the harness run `dist/`.
- One integration lane at a time on a machine; give each lane its own database and namespace. Every `psql`, `createdb` and `dropdb` carries `PGPASSWORD=hatchet`.
- The engine is shared. An empty `workflowNames` filter on the engine's bulk cancel is tenant-wide; never send one.
- `.env.local` holds real settings. It stays untracked, and nobody copies it into a commit, an issue or a log.
- The failure harness (`src/__tests__/harness/`) is run by hand, not by CI. It may kill and proxy only the processes and ports it started itself.
- `.github/workflows/against-kyu-main.yml` runs the shop against the packed `main` of the SDK. A red run there is an SDK regression until shown otherwise.

## Changes

Behaviour changes get a test that fails when the change is reverted; watch it fail first. Keep the diff small and one concern per pull request. Plain language on issues and pull requests: simple words, no assumed context, no metaphors; the first sentence is the ask or the change. Roles, not names, in docs. The CTO merges; an agent never merges and never pushes to `main`.

## Agent ship loop

Humans may shortcut a tiny PR (typo, docs-only, rename). An agent fills `## Agent ship loop` on its PR: `Behavior changed: yes|no`, `Red proof: <test file> — <test title>` (required when behaviour changed), and these rows checked, each with a short reason: Plan (or N/A and why); Red must-hold (or N/A for docs, lint, rename or config only); Smallest diff; Local checks (`pnpm gates`, `pnpm self-tests` and the rest of the normal loop); Separate review (not the author); Hosted CI (do not claim done from a local green). The heading alone marks an agent pull request and is checked in full, because agents push from the owner's account and no author or branch name gives them away; a body without it passes as human, so a human deletes the heading. Gate: `scripts/gates/check-agent-ship-loop.sh`, run by `pnpm gates` when `PR_BODY_FILE` is set, and by the `Ship loop` workflow on every pull request open, edit, push and reopen.
