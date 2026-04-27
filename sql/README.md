# SQL Source of Truth

`docs/sql/` is the authoritative database initialization source for local Docker PostgreSQL.

- Docker mounts `docs/sql/` to `/mediask-init/sql`
- PostgreSQL entrypoint executes `/mediask-init/sql/init-dev.sql`
- All schema and seed changes must be made in `docs/sql/`

The repository root `sql/` directory is no longer used by Docker initialization and must not be treated as the source of truth.
