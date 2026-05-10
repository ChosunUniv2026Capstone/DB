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
- `postgres/seed/*.csv` CSV seed inputs for users, classrooms, AP mappings, courses, schedules, enrollments, and registered devices

Object storage trigger checks live in `postgres/tests/object_storage_triggers.sql`.

The DB init set does not ship a default exam demo seed. Professors are expected
to create exam data through the application flow.

## Usage

The shared compose file in `CodexKit` mounts `postgres/init` into the Postgres
container's `/docker-entrypoint-initdb.d`.

Seed summary:
- students: 10
- professors: 2
- admins: 2
- classrooms: 3
- AP mappings: 10
- courses: 20
- default dev password: `devpass123`
