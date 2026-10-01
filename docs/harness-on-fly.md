# Running the shop harness in-region

Engine-side commands (`infra/hatchet/fly/*`) run from a kyuworks/kyu checkout. Everything else on this page runs from the root of this repository. The engine runbook is `docs/operations/kyu-engine-on-fly.md` in that repository.

This runs the shop's failure harness (`src/__tests__/harness/`) from inside `syd`,
beside `<engine-app>`, instead of from a laptop (archived issue 166, following archived issue 165 option 1). It uses a
second, separate app — `<shop-harness-app>` — plus its own database cluster
(`<shop-harness-db>`, Postgres 17, 10 GB, `syd`). It does not change `<engine-app>` or
`<engine-db>` at all.

**Destroyed on 2026-09-25.** The app and its cluster (cluster id `<shop-cluster-id>`; Basic from
2026-09-24 after archived issue 198, before that Basic, then Starter, then Launch on 2026-09-23) were
destroyed on the CTO's instruction; see "Destroying the cluster" below. Neither exists now. Machine
ids below are from before that date. To run the harness again, recreate both
with the steps that follow, in order: "One-time setup" (the app, a new cluster and its
`kyu_shop_inregion` database), then "The CTO's steps, in order" (the four secrets through
`infra/shop-harness/fly/secrets.sh`, from the new cluster's direct connection string and a newly
minted engine token), then "Running it". A new cluster gets a new cluster id: use it wherever this
section says `<shop-cluster-id>`. Before a report-size run, move the new cluster to Launch (see
**Before a report-size harness run** at the top of this page).

**Who does what:** an engineer (or an agent, for the parts that touch no secret) creates the app,
the cluster, and the image, and drives every deploy, start, collect and stop below. The CTO sets
the secrets on the harness app and never anything on `<engine-app>`. Neither role reads a
Fly connection string or a token back once set — the checks below use names-only listings.

### One-time setup

1. Create the app: `fly apps create <shop-harness-app> -o <fly-org>`
2. Create a second Basic managed Postgres cluster — **never** the engine's own cluster
   (`<engine-db>`) and never `<engine-db>-restoretest`
   (destroyed 2026-09-23). Redirect stdout to `/dev/null`; it carries one-time
   credentials:
   `fly mpg create -o <fly-org> -n <shop-harness-db> -r syd --plan Basic --pg-major-version 17 --volume-size 10 >/dev/null`
   (the command line cannot change a cluster's plan; before a report-size run, move the cluster to
   Launch in the Fly dashboard, see the note at the top of this page).
3. Confirm it reached `ready` with names only: `fly mpg list -o <fly-org>`.
4. Create the database inside the cluster: `fly mpg databases create <shop-cluster-id> -n kyu_shop_inregion`
   — the managed Postgres user lacks `CREATEDB`, so `migrate` cannot create it itself.
5. Validate the config: `fly config validate -c infra/shop-harness/fly/fly.toml -a <shop-harness-app> --strict`
6. Validate the image on Fly's remote builder, with no machine created and no secret needed:
   `fly deploy . -c infra/shop-harness/fly/fly.toml --dockerfile infra/shop-harness/fly/Dockerfile --ignorefile infra/shop-harness/fly/harness.dockerignore --build-arg KYU_HARNESS_COMMIT_SHA="$(git rev-parse HEAD)" --build-only -a <shop-harness-app>`

**The CTO's steps, in order** (needed once, before the first real run):

1. In the Fly dashboard, open Managed Postgres → `<shop-harness-db>`. Copy the **direct**
   connection string (not the pooler — the relay and migrations need session-mode semantics, the
   same reason step 5 of the first-deploy section above gives). Change the database name at the
   end of its path to `kyu_shop_inregion`. Store the string in 1Password.
2. Run `bash infra/shop-harness/fly/secrets.sh`, fill in its `KYU_SHOP_DATABASE_URL` line from
   step 1, and run it. Run the two `HATCHET_CLIENT_HOST_PORT` and `HATCHET_CLIENT_API_URL` lines
   as well, with the engine's private addresses it names.
3. Run `fly ssh issue` for the org, only if that has not already been done (it was, for archived issue 162).
4. Run the token line `secrets.sh` prints exactly as written, so the token never reaches the
   screen or shell history as an argument:
   `printf 'HATCHET_CLIENT_TOKEN=%s\n' "$(bash infra/hatchet/fly/token.sh -a <engine-app>)" | fly secrets import --stage -a <shop-harness-app>`

   `hatchet-admin token create` with no expiry flag mints a token that lasts 90 days, measured as
   `exp` minus `iat` on v0.107.0 (the admin tool's own default is 2160h — the same 90 days). Re-mint
   before then. `invalid auth token` in the harness logs, seen only at report size and not at smoke
   size (archived issue 165), is an open hypothesis — engine-side token validation under load — not a confirmed
   cause: a smoke-size run with zero such lines shows only that the token was accepted at smoke
   size that day, not why the report-size lines appeared. Whether to re-mint before the 90 days are
   up is the CTO's decision.
5. Reply "done" on the tracking issue, with no values in the reply.

Whether the four secrets are staged can be checked with names only, never by reading a value:

```bash
fly secrets list -a <shop-harness-app> --json | node -e \
  'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).map(x=>x.name ?? x.Name).sort().join("\n")))'
```

This should list exactly `HATCHET_CLIENT_API_URL`, `HATCHET_CLIENT_HOST_PORT`, `HATCHET_CLIENT_TOKEN` and `KYU_SHOP_DATABASE_URL`. Whether the database
string actually names `kyu_shop_inregion` and works cannot be checked without reading it — the
first run's `migrate-done` log line is the check; a wrong name fails loudly with `refusing to
create database "<name>"`, which names the database, not the credentials.

### Running it

**A `fly deploy` only starts a run the first time, when it creates the machine.** On every deploy
after that, the machine already exists and is `stopped` (restart policy `never`); a deploy to an
existing machine only updates its config (including applying any newly staged secret) and leaves
it `stopped`. **`fly machine start <id> -a <shop-harness-app>` is the
step that actually executes `run.sh` again.** There is no separate "create" step once the app and
cluster above exist.

1. From a clean tree (`git diff --quiet && git diff --cached --quiet`), deploy:
   `fly deploy . -c infra/shop-harness/fly/fly.toml --dockerfile infra/shop-harness/fly/Dockerfile --ignorefile infra/shop-harness/fly/harness.dockerignore --build-arg KYU_HARNESS_COMMIT_SHA="$(git rev-parse HEAD)" --ha=false -a <shop-harness-app>`
   — this creates the machine and starts it only if the app has none yet; otherwise it updates the
   existing (stopped) machine's config and image without running it.
2. Start the run: `fly machine start <id> -a <shop-harness-app>`.
3. Watch `fly logs -a <shop-harness-app>` for the harness's own event lines: `preflight-ok`,
   `migrate-done` (including the database name `migrateLogFields()` logs — see the pitfall below),
   one `report-written` per scenario, then `harness-done`. Do not paste engine or harness logs into
   a pull request or a chat message beyond the event lines named here.
4. Copy each scenario's report back, verified by its sha256, while the machine holds open
   (`KYU_HARNESS_HOLD_SECONDS` in `fly.toml`):
   `bash infra/shop-harness/fly/collect.sh -a <shop-harness-app> -m <machine-id> -s tenant-load -o report-166-tenant-load.json`
   (and the same for `outbox-backlog`). The `-o` path must be absolute or repository-relative from
   the repo root — archived issue 164's laptop-to-Fly run lost a report to a path resolved from the wrong
   working directory.

   Collect before you stop. Run `collect.sh` on its own and wait for `collected`; never chain
   `fly machine stop` after it in one command. On 2026-09-23 a 6.7 MB report was lost that way.
   `collect.sh` reads a report in 1 MB parts, because one exec answer has a size limit — on
   2026-09-23 that read failed: `Error: could not exec command on machine`.
5. Stop the machine once both reports are collected: `fly machine stop <id> -a <shop-harness-app>`
6. Verify it actually stopped, names and states only:
   `fly machine list -a <shop-harness-app> --json` and `fly status -a <shop-harness-app>`.

**Pitfall: a `KYU_SHOP_DATABASE_URL` naming the wrong cluster fails the same way as a missing
grant.** `migrate`'s `start`/`failed` log lines print the database name only
(`{"process":"migrate","event":"start","database":"<name>"}`), never the connection string. If
that name is right but migrate still fails with `permission denied to create database`, the
database name is not the problem — check that the string's **host** belongs to the shop cluster
(`<shop-harness-db>`), not the engine's (`<engine-db>`), which has no
`kyu_shop_inregion` database at all. Compare the host with the two cluster ids that
`fly mpg list -o <fly-org>` prints. An unchanged secret digest in `fly secrets list` after a
re-stage means the value was not actually changed.

If nobody collects in time, the machine exits on its own after `KYU_HARNESS_HOLD_SECONDS` and
reads `stopped` — nothing is left running either way.

**To run again** (the app and cluster already exist): `fly machine start <id> -a <shop-harness-app>`
runs `CMD` once more, because the restart policy is `never`. To run one scenario only:
`fly machine update <id> -e KYU_HARNESS_SCENARIOS=outbox-backlog --skip-start -a <shop-harness-app>`,
then start it.

### Network path and its fallback

The standing config points the harness at the engine's internal 6PN address, plaintext
(`<engine-app>.internal`, `HATCHET_CLIENT_TLS_STRATEGY = 'none'`) — how a same-org consumer
reaches the engine in production. If that path does not answer, `run.sh`'s preflight
(`GET $HATCHET_CLIENT_API_URL/api/ready`) fails within seconds and the run never starts a
scenario. The fallback is the public edge, the same path the laptop-to-Fly run (archived issue 164) used:

The two address values are app secrets. Fly's configuration reference says "Secrets take precedence
over env variables with the same name", and the `-e` flag sets the same machine env, so a `-e` address
loses to the secret. Stage the public ones first; then override the TLS settings on the machine:

```bash
fly secrets set --stage -a <shop-harness-app> HATCHET_CLIENT_HOST_PORT=<engine-app>.fly.dev:7077 HATCHET_CLIENT_API_URL=https://<engine-app>.fly.dev
fly machine update <id> -a <shop-harness-app> --skip-start \
  -e HATCHET_CLIENT_TLS_STRATEGY=tls \
  -e HATCHET_CLIENT_TLS_SERVER_NAME=<engine-app>.fly.dev
fly machine start <id> -a <shop-harness-app>
```

If a run used this fallback, the proof page says so and labels that column "in-region via edge".
To go back to the standing path, stage the two internal values again (`secrets.sh` prints them), then
run `fly deploy` as in "Running it" step 1. The deploy applies the staged secrets and puts back the
`[env]` TLS strategy, clearing the `-e HATCHET_CLIENT_TLS_STRATEGY=tls` override. A secret outlives a
deploy; the `-e` override does not.

### Cancelling a harness namespace

A scenario run can leave runs queued or running on the engine under its own namespace after the
harness exits — a durable run whose worker stopped mid-retry is invisible to a single check (archived issue 165).
`fly machine start <id>` cannot be used to clean these up: starting `<shop-harness-machine-id>` runs the image's
own `CMD`, `bash infra/shop-harness/fly/run.sh`, which is the full report-size scenario suite, not a
one-off command. After a fallback run, restore the internal secrets first (see the end of
"Network path and its fallback"): the public address secrets would otherwise override the `-e`
internal addresses below while the TLS strategy is still `none`.

Instead, build and push an image without touching any machine:

```bash
fly deploy . -c infra/shop-harness/fly/fly.toml --dockerfile infra/shop-harness/fly/Dockerfile \
  --ignorefile infra/shop-harness/fly/harness.dockerignore \
  --build-arg KYU_HARNESS_COMMIT_SHA="$(git rev-parse HEAD)" \
  --build-only --push --image-label <image-label> -a <shop-harness-app>
```

Then run the cancel CLI as a throwaway machine that removes itself, naming one namespace to cancel:

```bash
fly machine run -a <shop-harness-app> -r syd --vm-size shared-cpu-1x --rm \
  -e HATCHET_CLIENT_HOST_PORT=<engine-app>.internal:7077 \
  -e HATCHET_CLIENT_API_URL=http://<engine-app>.internal:8888 \
  -e HATCHET_CLIENT_TLS_STRATEGY=none \
  registry.fly.io/<shop-harness-app>:<image-label> \
  node dist/__tests__/harness/cancelNamespaceCli.js <namespace>
```

**One namespace per `fly machine run`.** On 2026-09-24 (archived issue 198) two namespaces given this way
reached the CLI as one argument, `"<first> <second> "`, and it exited 1 with `is not a harness
namespace`. For more than one, loop:

```bash
for ns in <namespace> <namespace>; do
  fly machine run -a <shop-harness-app> -r syd --vm-size shared-cpu-1x --rm \
    -e HATCHET_CLIENT_HOST_PORT=<engine-app>.internal:7077 \
    -e HATCHET_CLIENT_API_URL=http://<engine-app>.internal:8888 \
    -e HATCHET_CLIENT_TLS_STRATEGY=none \
    registry.fly.io/<shop-harness-app>:<image-label> \
    node dist/__tests__/harness/cancelNamespaceCli.js "$ns"
done
```

**Finding a run's namespaces.** The harness log does not print them. Each scenario namespace
prefixes the worker and queue names in the engine's log, so search a saved engine log tail:
`grep -oh '<prefix>_[a-z_]*_[0-9a-f]\{6\}_' <engine log> | sort -u`, where `<prefix>` is
`KYU_SHOP_NAMESPACE` without its last underscore (`inregion198` finds
`inregion198_tenant_load_7d76f5_`). A scenario that starts no worker, such as `outbox-backlog`,
does not appear.

Each namespace takes at least 60 seconds to settle, and that settle wait counts toward whatever
scenario duration you are comparing it against — see the proof page's comparison-table note. The
log line `cancel-namespace` gives `found` (runs before cancelling), `acceptedByEngine` (the sum of
what the engine's own cancel call accepted) and `left` (what the engine's list still shows after
cancelling); an exit code of 1 means at least one namespace still holds runs. The machine removes
itself when it exits — confirm with `fly machine list -a <shop-harness-app>`.

**This command only accepts a scenario namespace** (a prefix ending `_<6 hex chars>_`, the shape
`scenarioNamespace` mints) — not a bare project prefix like `shop_`, which the SDK would cancel by
prefix across the whole tenant.

**A namespace can stay above 0 forever.** The engine's REST run list can keep showing a run as
RUNNING or QUEUED after it has actually completed or been cancelled; this command's cancel and
`left` count cannot detect or clear that state, so a namespace that never reaches 0 after repeated
runs is not necessarily still doing anything (archived issues 165 and 170). `left` now leaves out runs the
engine's run detail says completed or failed; what remains is either live or a durable run the
engine stopped tracking — see Known engine defects.

### Destroying the cluster

Done on 2026-09-25, on the CTO's instruction: `fly apps destroy <shop-harness-app>` removed the
app and its machine, and `fly mpg destroy` destroyed `<shop-harness-db>` (`<shop-cluster-id>`).
Confirmed: `fly apps list -o <fly-org>` no longer lists `<shop-harness-app>`, and
`fly mpg list -o <fly-org>` no longer lists `<shop-harness-db>`; both still list the engine
app, `<rabbitmq-app>` and `<engine-db>` respectively.

After a future run, the lane that recreated the cluster may destroy it once the CTO accepts that
run's proof, with no CTO step: `fly mpg destroy <shop-cluster-id>`, then the same `fly mpg list` check.
The app can be destroyed the same way with `fly apps destroy <shop-harness-app>`, or left in
place (its machine stays `stopped` at no cost).
