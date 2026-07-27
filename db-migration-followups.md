# packages DB migration followups

sd-142878 (195.154.87.126) is now running native PG18 behind pgbouncer:6432.
sd-135240 (195.154.29.88) old dokku-postgres still running as fallback, diverged since 2026-07-22 ~16:03.

## statement_timeout not enforcing through pgbouncer

Queries ran 40+ min despite `variables: statement_timeout` in database.yml.
`track_extra_parameters = IntervalStyle,statement_timeout` is in
`/etc/pgbouncer/pgbouncer.ini` but apparently not taking effect.

Check what pgbouncer actually loaded:

    sudo -u postgres psql -h /var/run/postgresql -p 6432 -U pgbouncer pgbouncer -c "SHOW CONFIG;" | grep -i track

Then verify whether Rails's SET reaches a backend by connecting through
pgbouncer and checking `SHOW statement_timeout` after a `SET`. If
track_extra_parameters isn't working, alternatives are per-role defaults
(`ALTER ROLE ... SET statement_timeout`) split by web vs worker user, or
session pool mode.

Update 2026-07-23: track_extra_parameters can't work for this. pgbouncer can
only track parameters the server reports via GUC_REPORT, and statement_timeout
isn't one of them. Per-role defaults are the way: separate web and worker DB
users, `ALTER ROLE <web_role> SET statement_timeout = '30s'`, worker role
uncapped. Role defaults apply at backend startup so pooling can't strip them.

Confirmed during the 2026-07-23 index build saturation: rack-timeout fires
fine (AppSignal p90 stayed under 15s) but the queries it abandons keep running
in PG for hours. Killing the client never cancels the query, and
client_connection_check_interval won't help behind pgbouncer since the
backend's client socket belongs to pgbouncer, not puma. Interim tool while no
role split exists, cull orphans by application_name:

    SELECT count(pg_cancel_backend(pid)) FROM pg_stat_activity
    WHERE state='active' AND application_name = '/usr/local/bundle/bin/puma'
    AND query_start < now() - interval '30 seconds';

## Config tidy on sd-142878

Tuning was appended to the bottom of `/etc/postgresql/18/main/postgresql.conf`
(everything from `listen_addresses = '*'` onward, ~35 lines) so that
pg_upgradecluster would carry it, because it copies postgresql.conf but not
conf.d contents. The original split files still exist at
`/etc/postgresql/14/main/conf.d/tuning.conf` and `logging.conf`.

To tidy: copy those two files into `/etc/postgresql/18/main/conf.d/`, delete
the appended block from 18's postgresql.conf, drop the `hot_standby` and
`hot_standby_feedback` lines (only relevant when it was a replica), reload.
Verify with `SHOW shared_buffers` afterwards.

Also remove `/etc/systemd/system/postgresql@14-main.service.d/timeout.conf`
and the `pg_ctl_options = '-t 3600'` line in
`/etc/postgresql/14/main/pg_ctl.conf` (both were for the initial WAL replay).

## Drop old 14 cluster

pg_upgrade ran with `--link` so 14's data files are hard-linked into 18's
data dir; 14 is not independently startable (its `global/pg_control` is
renamed to `.old`). After a day or two on 18 with no issues:

## Drop old 14 cluster

After a day or two on 18 with no issues:

    sudo pg_dropcluster 14 main

This frees almost no space (hard links), just removes the config and the
now-unusable 14 data dir.

## pgbouncer config reference

`/etc/pgbouncer/pgbouncer.ini` (transaction mode, 6432, max_prepared_statements=200)
`/etc/pgbouncer/userlist.txt` (postgres password, 600 postgres:postgres)
`/etc/systemd/system/pgbouncer.service.d/limits.conf` (LimitNOFILE=8192)

App hosts allowed in `/etc/postgresql/18/main/pg_hba.conf`: 51.15.23.142 and
195.154.29.88.

## Extension version

    sudo -u postgres psql -d packages_production -c "ALTER EXTENSION pg_stat_statements UPDATE;"

## Autovacuum tuning

`packages`, `versions`, `dependencies` are large enough that default
scale_factor (20%) means autovacuum rarely runs. Watch
`pg_stat_user_tables.n_dead_tup` and `last_autovacuum` for a few days, then
set per-table `autovacuum_vacuum_scale_factor` (0.01-0.05) via migration if
dead tuples accumulate.

## Backup schedule

One-off dump at `/var/lib/postgresql/backups/packages_20260721.dump` (83G).
Need a recurring dump or WAL archiving. Simplest: nightly pg_dump via cron
to the same dir with rotation.

## Decommission sd-135240 postgres

Old dokku-postgres container still running, diverged since cutover. Once
confident on 18:

    dokku postgres:destroy packages_production

on sd-135240. Box itself stays as an app host (dokku2). All three SSDs are
past endurance so it needs replacing or re-disking eventually.

## Index work

Tracked at https://github.com/ecosyste-ms/packages/issues/1744, PR in
progress via codex.
