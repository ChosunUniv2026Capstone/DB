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
3. `017_selected_lms_subset.sql` adds selected LMS grading fields, Q&A tables,
   learning progress snapshots, and demo rows for grade/feedback, Q&A, and progress APIs.

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

docker compose \
  --project-directory "$PWD" \
  --env-file .env \
  -f compose.yml -f compose.image.yml \
  exec -T postgres \
  psql -U "${POSTGRES_USER:-smartclass}" -d "${POSTGRES_DB:-smartclass}" \
  < ../DB/postgres/migrations/017_selected_lms_subset.sql

docker compose \
  --project-directory "$PWD" \
  --env-file .env \
  -f compose.yml -f compose.image.yml \
  exec -T postgres \
  psql -U "${POSTGRES_USER:-smartclass}" -d "${POSTGRES_DB:-smartclass}" \
  < ../DB/postgres/migrations/018_continuous_attendance_monitoring.sql
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
4. `learning_progress`
5. `course_qna_posts`
6. `course_qna_threads`
7. selected LMS grading columns on `assignment_submissions` and `assignments`
8. `assignment_submission_attachments`
9. `assignment_submissions`
10. `assignments`
11. `attendance_monitoring_states`
12. `attendance_monitoring_leases`
13. `attendance_sessions.attendance_policy` and the `CSE999` seed rows, only after stopping continuous-attendance-capable Backend/Front versions.

Never run the destructive rollback against a production/demo volume without a
verified backup and operator approval. Continuous-attendance rollback is destructive if monitoring state or the `CSE999` seed has been used; prefer restore from a pre-upgrade backup.

## OpenWrt collector registry upgrade

Use `016_openwrt_collector_registry.sql` when a persisted `postgres-data` volume
predates the OpenWrt local collector push rollout. It creates:

- `access_points` for physical OpenWrt collector nodes and token metadata.
- `access_point_interfaces` for physical AP interface/BSS to `classroom_networks` mapping.
- demo mappings for `openwrt-a`, `openwrt-b`, and `openwrt-c`.
- `openwrt-push` collection mode for the actual demo AP-backed classroom networks.

Run it after `015_object_storage_schema_upgrade.sql` and before deploying a
Backend/PresenceService version that expects AP registry data.

Example:

```bash
cd ../Service
./scripts/up-image.sh -d

docker compose \
  --project-directory "$PWD" \
  --env-file .env \
  -f compose.yml -f compose.image.yml \
  exec -T postgres \
  psql -U "${POSTGRES_USER:-smartclass}" -d "${POSTGRES_DB:-smartclass}" \
  < ../DB/postgres/migrations/016_openwrt_collector_registry.sql
```

### OpenWrt collector rollback

This migration is additive and mostly operational metadata. To rollback without
deleting attendance/course data, first stop collector-capable
Backend/PresenceService versions and revoke AP tokens. If a destructive rollback
is still required after backup, drop `access_point_interfaces`, then
`access_points`, and optionally set affected `classroom_networks.collection_mode`
back to `openwrt-ssh`. Do not drop `classroom_networks` rows because they remain
course/classroom network contract data.


## Selected LMS subset upgrade

`017_selected_lms_subset.sql` is an additive/idempotent upgrade for Backend #36 selected LMS scope. It adds:

- `assignments.max_score`
- assignment submission grading columns (`score`, `feedback`, `graded_by_user_id`, `graded_at`, `grading_status`)
- `course_qna_threads` and `course_qna_posts`
- `learning_progress`

Run after `016_openwrt_collector_registry.sql` on persisted Service deployments. Rollback requires a backup restore or manual removal of the added tables/columns after stopping Backend/Front traffic that reads selected LMS endpoints.


## Continuous attendance monitoring upgrade

`018_continuous_attendance_monitoring.sql` is an additive/idempotent upgrade for `continuous_presence_v1`. It adds:

- `attendance_sessions.attendance_policy` with safe legacy backfill (`manual_v1` for non-smart legacy rows, `smart_window_v1` for legacy smart rows) and a legacy-safe DB default of `smart_window_v1`; Backend must explicitly write `continuous_presence_v1` for new continuous smart sessions.
- `attendance_monitoring_leases` for session-scoped Backend worker ownership (`lease_owner`, `lease_until`, `heartbeat_at`).
- `attendance_monitoring_states` for per-session/projection/student accumulators (`last_accounted_until`, `away_seconds`, `unknown_seconds_consumed`, `current_presence_state`, `last_presence_reason`, `status_candidate`, `finalized_at`).
- `CSE999` / `B101` / `PRF001` seed data: two daily schedule windows (`00:00-12:00`, `12:00-00:00`) for all seven days plus active enrollments for every seeded student account.

Run after `017_selected_lms_subset.sql` on persisted Service deployments, before deploying Backend/Front versions that read `attendance_policy` or monitoring tables.

### Continuous attendance rollback

This migration is additive, but rollback can delete monitoring state and the 24h/7d test course. First stop continuous-attendance-capable Backend/Front versions and take a verified backup. Prefer restoring the pre-upgrade backup. If a reviewed destructive rollback is still required, delete `attendance_monitoring_states`, delete `attendance_monitoring_leases`, delete `CSE999` course/enrollment/schedule rows, and only then drop `attendance_sessions.attendance_policy` after all application code no longer reads it.
