# Outbound rate limiting

Package syncs make HTTP requests to upstream registries, and several of those registries return 429s or have asked us to reduce load. A per-registry cap on how many sync jobs start per second keeps the request rate to each host under control while letting other registries' work continue.

## How it works

[`sidekiq-throttled`](https://github.com/ixti/sidekiq-throttled) patches `Sidekiq::BasicFetch`. When a worker process pulls a job from redis, it checks the job's throttle strategy before running it. If the job is over its limit, it is pushed back onto its queue with a raw `redis.lpush` and a different job is fetched instead. The push does not go through `Sidekiq::Client`, so `sidekiq-unique-jobs` client middleware does not run and the job's `until_executed` lock stays intact rather than being deduped. The `:schedule` requeue mode would go through the client and lose the job, so the default `:enqueue` mode is used.

A single shared strategy, `:registry_host`, is registered in [`config/initializers/sidekiq_throttled.rb`](../config/initializers/sidekiq_throttled.rb). Its threshold key is the host part of the registry's URL, so two registries whose URLs point at the same host share one bucket. Its limit is `registry.metadata['rate_limit']`, an integer number of jobs per second. When `rate_limit` is nil `sidekiq-throttled` short-circuits before any redis call and the job runs immediately, so unthrottled registries carry no overhead.

The workers that share `:registry_host` all take `registry_id` as their first argument, which the strategy's `key_suffix` and `limit` procs read at fetch time via [`Registry.host_for`](../app/models/registry.rb) and [`Registry.rate_limit_for`](../app/models/registry.rb):

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

`rate_limit` is stored in the registry's `metadata` json and validated as a positive integer, since sidekiq-throttled treats zero or negative as permanently throttled. Default limits for registries that have throttled us are set in [`db/seeds.rb`](../db/seeds.rb). Setting the value back to nil removes the cap:

```ruby
Registry.find_by_name!('npmjs.org').update!(rate_limit: nil)
```

## Enqueue budget

Throttled jobs go back onto their queue, so if crons enqueue more jobs for a rate-limited registry than that registry can drain before the next cron tick, the queue grows without bound. [`Registry#sync_budget(period)`](../app/models/registry.rb) returns `rate_limit * period` seconds (nil when unthrottled), and [`Registry#sync_one_percent_of_packages`](../app/models/registry.rb) caps its batch at that budget so a tick never adds more than can be processed by the next one. The cross-ecosystem sweeps in [`Package.sync_least_recent_async`](../app/models/package.rb), [`sync_least_recent_top_async`](../app/models/package.rb) and [`check_statuses_async`](../app/models/package.rb) skip the tick when the `:critical` queue is over 10,000 so a backlog from any source stops compounding.

## Metrics

Every outbound Faraday request emits a `request.faraday` notification, which [`config/initializers/faraday.rb`](../config/initializers/faraday.rb) turns into two AppSignal custom metrics: `registry_http_requests` (counter, tagged `host` and `status`) and `registry_http_duration` (distribution, tagged `host`). The "Registry outbound HTTP" AppSignal dashboard graphs successful requests, 429s, 4xx/5xx errors, connection failures and p95 duration per host.

`sidekiq_queue_latency` and `sidekiq_queue_length` for the `:critical` queue show whether throttled jobs are backing up. If `:critical` latency climbs steadily across cron ticks, either a registry's `rate_limit` is set below what its share of the periodic sweeps enqueues, or a cron is enqueueing more than the budget cap accounts for.
