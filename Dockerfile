FROM postgres:16-alpine

COPY postgres/init /docker-entrypoint-initdb.d
COPY postgres/seed /seed-data
