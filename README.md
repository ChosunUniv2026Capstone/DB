# DB

Database assets for the smart-class vertical slice.

This repo currently provides PostgreSQL init scripts used by the shared Docker
Compose stack.

## Contents

- `postgres/init/001_schema.sql` initial schema
- `postgres/init/010_seed.sql` development seed data
- `postgres/init/011_presence_threshold.sql` classroom AP threshold patch
- `postgres/init/012_attendance_demo_seed.sql` attendance demo seed
- `postgres/init/013_exam_schema.sql` exam MVP schema
- `postgres/init/014_assignment_schema.sql` assignment schema
- `postgres/init/015_object_storage_schema.sql` Garage/S3-compatible object metadata, deletion jobs, and trigger strategy
- `postgres/init/016_selected_lms_subset.sql` selected LMS grading fields, Q&A tables, and learning progress snapshots
- `postgres/init/017_selected_lms_demo_seed.sql` selected LMS demo seed
- `postgres/init/018_continuous_attendance_monitoring.sql` continuous attendance policy, monitoring lease/state tables, and 24h/7d test course seed
- `postgres/seed/*.csv` CSV seed inputs for users, classrooms, AP mappings, courses, schedules, enrollments, and registered devices
- `postgres/migrations/014_assignment_schema_upgrade.sql` idempotent assignment-table upgrade path for existing volumes
- `postgres/migrations/015_object_storage_schema_upgrade.sql` idempotent object metadata/deletion-outbox upgrade path for existing volumes
- `postgres/migrations/016_openwrt_collector_registry.sql` idempotent OpenWrt collector registry upgrade
- `postgres/migrations/017_selected_lms_subset.sql` idempotent selected LMS subset upgrade
- `postgres/migrations/018_continuous_attendance_monitoring.sql` idempotent continuous attendance monitoring upgrade and CSE999 24h/7d seed

Object storage trigger checks live in `postgres/tests/object_storage_triggers.sql`. Continuous attendance monitoring smoke checks live in `postgres/tests/continuous_attendance_monitoring.sql`.

Existing Postgres volumes do not re-run `postgres/init/*.sql`. For assignment/object-storage/selected-LMS/continuous-attendance rollouts on persisted Service `postgres-data` volumes, run the ordered migrations documented in `postgres/migrations/README.md` or use the Service release manifest `components.db.resetRequired` gate when a reset is acceptable.

The DB init set does not ship a default exam demo seed. Professors are expected
to create exam data through the application flow.

## Usage

The shared compose file in `CodexKit` mounts `postgres/init` into the Postgres
container's `/docker-entrypoint-initdb.d`.

Seed summary:
- students: 15
- professors: 3
- admins: 2
- classrooms: 3
- AP mappings: 10
- courses: 21 (20 CSV courses plus `CSE999` continuous attendance 24h/7d test course enrolled to every student)
- default dev password: `devpass123`
