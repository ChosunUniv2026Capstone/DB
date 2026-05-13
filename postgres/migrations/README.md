# DB migrations for existing Postgres volumes

Postgres only runs `postgres/init/*.sql` when a data directory is created for the
first time. Existing Smart Class demo/local volumes therefore need an explicit
operator step when a release adds tables after the original volume was created.

## Assignment and object-storage schema upgrades

Use these migrations when a persisted `postgres-data` volume predates the
assignment feature and assignment/object-storage API calls fail because the
current schema is missing tables, columns, or deletion-outbox triggers. Run them
in order:

1. `014_assignment_schema_upgrade.sql` creates the assignment domain tables:
   - `assignments`
   - `assignment_submissions`
   - `assignment_submission_attachments`
2. `015_object_storage_schema_upgrade.sql` adds the object-storage metadata
   columns, domain attachment metadata tables, `object_deletion_jobs`, and
   deletion triggers required by Backend object-storage APIs.

Both migrations are intentionally idempotent (`CREATE ... IF NOT EXISTS`,
`ADD COLUMN IF NOT EXISTS`, and trigger replacement) so they can be rerun safely
once per environment before deploying Backend/Front versions that use assignment
or object-storage APIs.

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

docker compose \
  --project-directory "$PWD" \
  --env-file .env \
  -f compose.yml -f compose.image.yml \
  exec -T postgres \
  psql -U "${POSTGRES_USER:-smartclass}" -d "${POSTGRES_DB:-smartclass}" \
  < ../DB/postgres/migrations/015_object_storage_schema_upgrade.sql
```

For demo releases, prefer the Service release manifest gate: if a DB image
digest change requires seed replay, set `components.db.resetRequired: true` and
run `scripts/deploy-demo.sh --reset-demo-data true` only after explicit approval.
That reset path deletes only the Service compose project's `postgres-data`
volume.

## Rollback

These migrations create domain tables, object metadata, and deletion-outbox
triggers. They do not include an automatic rollback because dropping them would
delete student submissions, attachment metadata, and durable object-deletion
jobs.
If rollback is required, first stop assignment-capable Backend/Front versions,
take a `pg_dump` backup, then either restore the pre-upgrade backup or perform a
reviewed destructive drop in reverse dependency order:

1. Object-delete triggers on attachment/export tables
2. `object_deletion_jobs`
3. Object metadata attachment/export tables added by `015_object_storage_schema_upgrade.sql`
4. `assignment_submission_attachments`
5. `assignment_submissions`
6. `assignments`

Never run the destructive rollback against a production/demo volume without a
verified backup and operator approval.
