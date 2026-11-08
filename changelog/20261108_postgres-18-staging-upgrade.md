# Postgres 18 on staging

Date: 2026-11-08
Status: written, not yet run (execution is manual, one app at a time)

## What changed

Both staging databases move from Postgres 16 to 18.

- `staging/apps/naikbusaja/docker-compose.staging.yml`: `postgis/postgis:16-3.4` → `postgis/postgis:18-3.6` (18-3.6 is published for linux/amd64, which is all the staging host needs, so the existing `platform:` pin stays)
- `staging/apps/maribelanja/docker-compose.staging.yml`: `postgres:16-alpine` → `postgres:18-alpine`
- Both `db` services get `shm_size: "256mb"`: PG18's async I/O (io_method=worker default) allocates from /dev/shm, and Docker's 64MB default is a known cause of "could not resize shared memory segment" startup failures
- `staging/scripts/upgrade-postgres-18.sh` + two Makefile targets do the dump / wipe / restore
- Topology diagram in `staging/README.md` updated to match

## Why

No 16-specific problem to fix; this is buying the future early while there are no real users to break. PG18's async I/O gives a genuine read-throughput jump, B-tree skip scans help multicolumn indexes, and the support window runs to late 2030 vs 2028 for 16. Staging is the cheap place to learn what the migration actually takes before a production stack ever needs it.

## What carries over, and what doesn't

A PG18 server cannot read a PG16 data directory, so the upgrade is a dump / wipe / re-init / restore, not an image bump. The scripts carry over exactly:

| Data | Fate |
| --- | --- |
| `users` (both apps) | Restored. Password hashes live in the rows, so `staging-test@darmawan.be` keeps its password. naikbusaja Google sign-ins survive via `google_id`. |
| `user_favorite_routes` (naikbusaja) | Restored |
| `users_tokens` (both apps) | Dropped on purpose. Sessions start fresh; everyone logs in again. |
| maribelanja catalog data | Dropped (no real data to lose yet) |
| naikbusaja transit feed | Dropped; re-imports itself on first boot after the wipe |

## How to run it

From `staging/`, against the EC2 box:

```
make pg18-dump                        # both apps; FULL=1 also dumps the whole DB
make pg18-upgrade APP=naikbusaja      # destructive: wipes that stack's pgdata volume
make pg18-upgrade APP=maribelanja     # destructive
```

The dump step saves user rows to `/opt/<app>/backups/pg18-users-<timestamp>.sql` and writes a marker file. The upgrade step refuses to wipe unless that marker exists and the compose file on the server is already on 18, so the order above is enforced by the tooling. naikbusaja migrates on app boot and is briefly live with an empty users table during the restore; maribelanja restores while its app is still down.

## Verification

The script's own post-checks: `SHOW server_version` reports 18.x, and each restored table's row count matches what the dump step recorded. Human checks after each app: log in at the staging URL with the test account, and for naikbusaja watch `make logs-naikbusaja` until the transit feed import finishes.

## Rollback

Git-revert the compose change and re-run `make pg18-upgrade APP=...` logic in reverse: the old cluster is gone once `down -v` runs, so data recovery means restoring from the dump files in `/opt/<app>/backups/` (or the `pg18-full-*.sql` dumps if `FULL=1` was used). There is no in-place rollback, which is the point of running this on staging first.
