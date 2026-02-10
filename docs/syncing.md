# How packages stay up to date

packages.ecosyste.ms tracks millions of packages across dozens of registries. Keeping them current involves several overlapping strategies: polling registries for recent changes, accepting pings from sibling services, running periodic sweeps to catch anything that fell through the cracks, and prioritising high-value packages for more frequent updates.

This is all best effort. packages.ecosyste.ms is a free, open source service and there are no guarantees about how fresh any given package's data will be. The system is designed to keep the most popular packages reasonably current and eventually catch up on everything else, but delays happen -- especially for less popular packages or registries with limited APIs.

All scheduling is defined in [`app.json`](../app.json) as Heroku-style cron entries. Sidekiq processes the resulting background jobs across three queues (critical, default, low).

## Polling registries for recent changes

The primary mechanism. Each ecosystem class implements `recently_updated_package_names`, which queries its registry's feed of recently published or updated packages. The strategies vary by registry:

- **npm** combines the registry's RSS feed (`/-/rss?descending=true&limit=50`) with a dedicated `npm.ecosyste.ms/recent` endpoint that returns up to 200 names. ([`Ecosystem::Npm#recently_updated_package_names`](../app/models/ecosystem/npm.rb#L56))
- **PyPI** parses `rss/updates.xml` and `rss/packages.xml` for updated and newly published packages. ([`Ecosystem::Pypi#recently_updated_package_names`](../app/models/ecosystem/pypi.rb#L45))
- **RubyGems** hits the `activity/just_updated.json` and `activity/latest.json` API endpoints. ([`Ecosystem::Rubygems#recently_updated_package_names`](../app/models/ecosystem/rubygems.rb#L38))
- **Maven** combines Sonatype's search API with a Libraries.io recent updates feed (or, for non-Maven Central registries, an archetype catalog). ([`Ecosystem::Maven#recently_updated_package_names`](../app/models/ecosystem/maven.rb#L66))
- Other registries use similar approaches: RSS feeds, changelog APIs, git commit diffs, or API search endpoints sorted by update time.

[`Registry#recently_updated_package_names_excluding_recently_synced`](../app/models/registry.rb#L70) filters the results. It drops any package already synced in the last 10 minutes and adds packages that exist in the registry feed but are missing from the database. This prevents redundant work when the same package appears in consecutive poll cycles.

Two cron entries drive this:

| Schedule | Task | What it does |
|---|---|---|
| Every 5 min | `packages:sync_recent_npm` | Polls npm only (by far the highest volume registry) |
| Every 15 min | `packages:sync_recent` | Polls all non-Docker registries via [`Registry.sync_all_recently_updated_packages_async`](../app/models/registry.rb#L22) |

## Pings from repos.ecosyste.ms

The repos service is the main source of inbound pings. It monitors repositories across GitHub, GitLab, Gitea, and other hosts, and pings packages whenever a repository changes.

repos.ecosyste.ms detects repository changes two ways:

- **Polling for recently active repos.** Every 15 minutes, repos runs `repositories:sync_recently_active`, which asks each host for repositories changed in the last 15 minutes. For GitHub, this queries timeline.ecosyste.ms's `/api/v1/events/repository_names` endpoint, which tracks the GitHub events firehose. For GitLab and Gitea, it paginates through repos sorted by `updated_at`. Up to 1000 repo names per host are queued for sync.
- **Syncing repos with new tags.** Separately, repos queries timeline.ecosyste.ms for recent `ReleaseEvent` entries from GitHub. Repos that had a release event get their tags downloaded, and any repo not yet tracked gets synced for the first time.

When repos fetches fresh data for a repository and any attribute has changed -- pushed_at, stargazers_count, description, topics, default_branch, license, or anything else -- it calls [`ping_packages_async`](https://github.com/ecosyste-ms/repos/blob/main/app/models/repository.rb#L472). This queues a `PingPackagesWorker` (with a 1-day uniqueness lock to avoid duplicate pings) that sends a GET request to:

```
GET /api/v1/packages/ping?repository_url={repository_html_url}
```

On the packages side, this hits the [bulk ping endpoint](../app/controllers/api/v1/packages_controller.rb#L289), which finds all packages sharing that repository URL (up to 1000) and queues each one for sync. If the request's User-Agent contains `repos.ecosyste.ms`, it also queues a repo metadata update for each package.

So the chain is: GitHub event -> timeline.ecosyste.ms -> repos.ecosyste.ms syncs the repo -> repo attributes changed -> ping packages.ecosyste.ms -> packages re-synced from their registries.

## Pings from other ecosyste.ms services

advisories.ecosyste.ms also pings packages when it detects new or updated security advisories. The ping hits the same endpoints but is identified by its User-Agent, which triggers an [`update_advisories_async`](../app/models/package.rb#L750) instead of (or in addition to) a repo metadata update.

Any service can ping a specific package directly:

**Single package ping** -- [`GET /api/v1/registries/:registry_id/packages/:id/ping`](../app/controllers/api/v1/packages_controller.rb#L276)

Queues an [`UpdatePackageWorker`](../app/sidekiq/update_package_worker.rb) for the package. If the package doesn't exist yet, it queues a [`SyncPackageWorker`](../app/sidekiq/sync_package_worker.rb) to create it.

**Bulk ping by repository URL** -- [`GET /api/v1/packages/ping?repository_url=...`](../app/controllers/api/v1/packages_controller.rb#L289)

Finds all packages matching that repository URL (up to 1000) and applies the same logic.

## Outbound pings from packages

When a package's repo metadata is updated via [`update_repo_metadata`](../app/models/package.rb#L372), packages pings outward to keep sibling services in sync:

- [`ping_repo`](../app/models/package.rb#L391) tells repos.ecosyste.ms to refresh its data for the package's repository
- [`ping_issues`](../app/models/package.rb#L508) tells issues.ecosyste.ms to refresh issue metadata
- [`ping_commits`](../app/models/package.rb#L644) tells commits.ecosyste.ms to refresh commit stats
- [`ping_usage`](../app/models/package.rb#L412) tells repos.ecosyste.ms to refresh usage tracking for the package

This creates a bidirectional flow: when repos detects a repository change it pings packages, and when packages updates its repo metadata it pings repos back (along with issues, commits, and usage).

## Catch-up sweeps for stale packages

Polling and pings handle most updates, but packages can still fall behind. Several cron jobs run periodic sweeps to catch stragglers.

| Schedule | Task | Selection logic |
|---|---|---|
| Every 15 min | `packages:sync_least_recent` | [`Package.sync_least_recent_async`](../app/models/package.rb#L81) -- 4000 random active packages not synced in over a month |
| Every 30 min | `packages:sync_least_recent_top` | [`Package.sync_least_recent_top_async`](../app/models/package.rb#L85) -- 3000 random top-2% packages not synced in over 12 hours |
| Every 20 min | `packages:sync_worst_one_percent` | [`Registry.sync_worst_one_percent`](../app/models/registry.rb#L423) -- finds the registry with the highest [`outdated_percentage`](../app/models/registry.rb#L395), syncs 1% of its outdated packages at random |
| Hourly | `packages:sync_batch_registries_outdated` | [`Registry.sync_in_batches_outdated`](../app/models/registry.rb#L46) -- for batch-sync registries (deb, conda, vcpkg, alpine, nixpkgs, bower, julia, adelie, postmarketos), syncs up to 1000 outdated packages each |
| Hourly | `packages:sync_outdated_docker` | 1000 random [outdated](../app/models/package.rb#L38) Docker packages (rate-limited to 1/sec) |
| Daily (midnight) | `packages:sync_missing` | [`Registry.sync_all_missing_packages_async`](../app/models/registry.rb#L34) -- compares each registry's full package list against the database and syncs anything missing |

A package is considered ["outdated"](../app/models/package.rb#L38) when `last_synced_at` is older than one month.

## Sync throttling

Several mechanisms prevent redundant syncing:

- [`Package#sync_async`](../app/models/package.rb#L310) skips the job entirely if the package was synced in the last 24 hours.
- [`Registry#sync_package`](../app/models/registry.rb#L145) checks the same 24-hour window. If a recently-synced package is requested again, it schedules the sync to run after the 24 hours expire rather than dropping it.
- [`recently_updated_package_names_excluding_recently_synced`](../app/models/registry.rb#L70) filters out packages synced in the last 10 minutes.
- [`Package.sync_download_counts_async`](../app/models/package.rb#L93) and [`sync_maintainers_async`](../app/models/package.rb#L101) check the Sidekiq default queue size and bail out if it exceeds 20,000 jobs.

## Priority tiers

Not all packages get the same treatment. The system treats high-value packages differently:

- **Top 2% packages** (by ranking percentile, based on downloads, dependents, stars, forks) get synced every 30 minutes if they're more than 12 hours stale. ([`sync_least_recent_top_async`](../app/models/package.rb#L85))
- **Regular packages** get caught by the least-recent sweep if they're more than a month stale. ([`sync_least_recent_async`](../app/models/package.rb#L81))
- **Worst-performing registry** gets targeted attention every 20 minutes via [`sync_worst_one_percent`](../app/models/registry.rb#L423), which finds whichever registry has the highest percentage of outdated packages and syncs 1% of them.

## Enrichment jobs

Beyond core package sync, several jobs enrich packages with data from other sources:

| Schedule | Task | What it does |
|---|---|---|
| Every 30 min | `packages:update_repo_metadata_async` | [`Package.update_repo_metadata_async`](../app/models/package.rb#L363) -- updates repo metadata for 400 packages (ordered by least recently updated) |
| Every 30 min | `packages:sync_maintainers` | [`Package.sync_maintainers_async`](../app/models/package.rb#L101) -- syncs maintainer data for up to 1000 packages in supported ecosystems |
| Every 30 min | `packages:update_rankings` | [`Package.update_rankings_async`](../app/models/package.rb#L110) -- calculates ranking percentiles for up to 1000 unranked packages |
| Hourly | `packages:update_advisories` | [`Package.update_advisories`](../app/models/package.rb#L754) -- fetches recently changed advisories and updates affected packages |
| Hourly | `packages:check_statuses` | [`Package.check_statuses_async`](../app/models/package.rb#L89) -- checks if up to 1000 packages not synced in 5+ weeks still exist (catches removed/unpublished packages) |
| Daily 3am | `packages:update_docker_usages` | [`Package.update_docker_usages`](../app/models/package.rb#L800) -- pulls Docker dependency and download counts from docker.ecosyste.ms |
| Daily 5am | `packages:update_extra_counts` | [`Registry.update_extra_counts`](../app/models/registry.rb#L18) -- updates aggregate registry metadata (active package counts, version totals, etc.) |
| Every 2 hours | `packages:crawl_recently_updated_github_marketplace` | Crawls GitHub Actions marketplace for recently updated actions |
| Every 6 days | `packages:calculate_funding_domains` | Calculates funding domain statistics |

## What happens during a sync

When [`Registry#sync_package`](../app/models/registry.rb#L145) runs for a given package name:

1. Check if the package was synced in the last 24 hours. If so, schedule a deferred re-sync and return.
2. Fetch package metadata from the ecosystem API.
3. If the returned name differs from the requested name (e.g. PyPI normalizing `aracnid_utils` to `aracnid-utils`), delete the misnamed record.
4. Create or update the Package record.
5. If the package changed, queue a repo metadata update via [`update_repo_metadata_async`](../app/models/package.rb#L367).
6. Fetch version metadata, upsert new versions, and insert dependencies for any versions that don't have them yet.
7. Update `versions_count` and `last_synced_at`.
8. Run [`update_details`](../app/models/package.rb#L205) (normalize licenses, set latest version, combine keywords).
9. Queue dependent repos count update and [`sync_maintainers_async`](../app/models/package.rb#L721) (if the ecosystem supports it).
10. Run [`check_status`](../app/models/package.rb#L350) (whether it's been removed or deprecated).

## Housekeeping

| Schedule | Task |
|---|---|
| Weekly (Sunday midnight) | `packages:clean_up_sidekiq_unique_jobs` -- clears the unique jobs digest set |
| Weekly (Sunday 2am) | `growth_stats:calculate` -- calculates registry growth statistics |
| Daily 4am | `sitemap:refresh` -- regenerates the sitemap |

## Reporting problems

If a package is out of date or missing, open an issue at https://github.com/ecosyste-ms/packages/issues with:

- The registry name and package name (or URL on packages.ecosyste.ms)
- What you expected to see vs what's actually showing
- When the package was last published or updated upstream, if you know
- Whether the package was recently renamed, transferred, or removed

For broader syncing problems affecting an entire registry, include the registry's status page URL (e.g. `packages.ecosyste.ms/registries/rubygems.org/status`) which shows the current outdated percentage and least recently synced packages.
