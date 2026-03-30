# DB

Database assets for the smart-class vertical slice.

This repo currently provides PostgreSQL init scripts used by the shared Docker
Compose stack.

## Contents

- `postgres/init/001_schema.sql` initial schema
- `postgres/init/010_seed.sql` development seed data
- `postgres/seed/*.csv` CSV seed inputs for users, classrooms, AP mappings, courses, schedules, enrollments, and registered devices

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
