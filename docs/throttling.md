# Outbound rate limiting

Package syncs make HTTP requests to upstream registries, and several of those registries return 429s or have asked us to reduce load. A per-registry cap on how many sync jobs start per second keeps the request rate to each host under control while letting other registries' work continue.

## How it works

[`sidekiq-throttled`](https://github.com/ixti/sidekiq-throttled) patches `Sidekiq::BasicFetch`. When a worker process pulls a job from redis, it checks the job's throttle strategy before running it. If the job is over its limit, it is pushed back onto its queue with a raw `redis.lpush` and a different job is fetched instead. The push does not go through `Sidekiq::Client`, so `sidekiq-unique-jobs` client middleware does not run and the job's `until_executed` lock stays intact rather than being deduped. The `:schedule` requeue mode would go through the client and lose the job, so the default `:enqueue` mode is used.

A single shared strategy, `:registry_host`, is registered in [`config/initializers/sidekiq_throttled.rb`](../config/initializers/sidekiq_throttled.rb). Its threshold key is the host part of the registry's URL, so two registries whose URLs point at the same host share one bucket. Its rate is `registry.metadata['rate_limit']`, jobs per second; `sidekiq-throttled` takes a limit-per-period pair rather than a rate, so [`Registry`](../app/models/registry.rb) exposes helpers that translate one into the other. When `rate_limit` is nil the limit proc returns nil, `sidekiq-throttled` short-circuits before any redis call, and the job runs immediately, so unthrottled registries carry no overhead.

The workers that share `:registry_host` all take `registry_id` as their first argument, which the strategy's procs read at fetch time:

| Worker | Enqueued from |
|---|---|
| [`SyncPackageWorker`](../app/sidekiq/sync_package_worker.rb) | `Registry#sync_packages_async` (recent-changes polling, missing-package discovery) |
| [`SyncPackageVersionWorker`](../app/sidekiq/sync_package_version_worker.rb) | Go index discovery |
| [`SyncPackageByIdWorker`](../app/sidekiq/sync_package_by_id_worker.rb) | `Package#sync_async` (catch-up sweeps, ping endpoints) |
| [`CheckPackageStatusWorker`](../app/sidekiq/check_package_status_worker.rb) | `Package#check_status_async` |

`Registry.host_for` and `Registry.rate_limit_for` are backed by a class-level `pluck` of the whole registries table with a 60-second TTL. Each sidekiq process re-reads the table once a minute, so a `rate_limit` change made from a console reaches every worker within 60 seconds without a restart.

## Scope

The unit is job starts per second, so a registry with `rate_limit: 5` whose sync jobs each make three requests to the registry host produces roughly 15 requests per second at that host. Ecosystems that make many requests per job (Go's per-version `.mod` and `.info` fetches, Helm's version pagination) produce higher request rates than the limit alone suggests. Secondary hosts a job touches (npm's `api.npmjs.org` for download counts, PyPI's `pypistats.org`) scale with the job rate too, so capping npm sync jobs also caps `api.npmjs.org` traffic.

Rake tasks that call `Registry#sync_packages` directly (the non-async path used by `sync_in_batches?` ecosystems such as nixpkgs and julia) run in the cron container and are not throttled. Neither are requests made outside sync jobs, such as `all_package_names` calls that happen inside a rake task before any workers are enqueued.

## Setting a limit

```ruby
Registry.find_by_name!('npmjs.org').update!(rate_limit: 3)
```

`rate_limit` is stored in the registry's `metadata` json and validated as a positive number (integer or float), since sidekiq-throttled treats zero or negative as permanently throttled. A float below 1 gives fewer than one job per second, useful for hosts that 429 even at one job per second. Default limits for registries that have throttled us are set in [`db/seeds.rb`](../db/seeds.rb); production values are tuned via the console and may differ. Setting the value back to nil removes the cap:

```ruby
Registry.find_by_name!('npmjs.org').update!(rate_limit: nil)
```

## Enqueue budget

Throttled jobs go back onto their queue, so if crons enqueue more jobs for a rate-limited registry than that registry can drain before the next cron tick, the queue grows without bound. [`Registry#sync_budget(period)`](../app/models/registry.rb) returns the number of jobs a registry's throttle can drain over `period` (nil when unthrottled), and the per-registry enqueue paths cap their batches at that budget so a tick never adds more than can be processed by the next one.

Throttled registries still receive jobs from more than one cron, and each cron sizes its batch against the throttle independently, so their combined inflow can exceed a single registry's drain rate. To keep that from compounding, the broad stale-package sweep excludes throttled registries entirely, and the remaining sweeps skip a tick when their target queue is already over its guard threshold.

## Metrics

Every outbound Faraday request emits a `request.faraday` notification, which [`config/initializers/faraday.rb`](../config/initializers/faraday.rb) turns into two AppSignal custom metrics: `registry_http_requests` (counter, tagged `host` and `status`) and `registry_http_duration` (distribution, tagged `host`). The "Registry outbound HTTP" AppSignal dashboard graphs successful requests, 429s, 4xx/5xx errors, connection failures and p95 duration per host. The 429 series is the signal for whether a `rate_limit` is set correctly: a host serving 429s needs a lower value, and a host that has been 429-free for a while is a candidate for a higher one.

`sidekiq_queue_length` for `:critical` shows whether throttled jobs are backing up. Because `sidekiq-throttled` requeues an over-limit job with its original `enqueued_at` intact, `sidekiq_queue_latency` on that queue reports the age of the oldest requeued job rather than time-to-first-run, so a steady non-zero length with a bouncing latency is the throttle working as intended. A length that climbs across cron ticks without falling back means a cron is enqueueing more than the budget cap accounts for.
