# DB migrations for existing Postgres volumes

Postgres only runs `postgres/init/*.sql` when a data directory is created for the
first time. Existing Smart Class demo/local volumes therefore need an explicit
operator step when a release adds tables after the original volume was created.

## Assignment schema upgrade (`014_assignment_schema_upgrade.sql`)

Use this migration when a persisted `postgres-data` volume predates the
assignment feature and assignment API calls fail because these tables are
missing:

- `assignments`
- `assignment_submissions`
- `assignment_submission_attachments`

The migration is intentionally idempotent (`CREATE ... IF NOT EXISTS`) so it can
be run safely once per environment before deploying Backend/Front versions that
use assignment APIs.

Example through the Service compose project:

```bash
cd ../Service
# start the current stack first so the postgres service is reachable
./scripts/up-image.sh -d

docker compose \
  --project-directory "$PWD" \
  --env-file .env \
  -f compose.yml -f compose.image.yml \
  exec -T postgres \
  psql -U "${POSTGRES_USER:-smartclass}" -d "${POSTGRES_DB:-smartclass}" \
  < ../DB/postgres/migrations/014_assignment_schema_upgrade.sql
```

For demo releases, prefer the Service release manifest gate: if a DB image
digest change requires seed replay, set `components.db.resetRequired: true` and
run `scripts/deploy-demo.sh --reset-demo-data true` only after explicit approval.
That reset path deletes only the Service compose project's `postgres-data`
volume.

## Rollback

This migration creates domain tables and does not include an automatic rollback
because dropping them would delete student submissions and attachment metadata.
If rollback is required, first stop assignment-capable Backend/Front versions,
take a `pg_dump` backup, then either restore the pre-upgrade backup or perform a
reviewed destructive drop in reverse dependency order:

1. `assignment_submission_attachments`
2. `assignment_submissions`
3. `assignments`

Never run the destructive rollback against a production/demo volume without a
verified backup and operator approval.
