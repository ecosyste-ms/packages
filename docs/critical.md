# How the `critical` flag is set

The `critical` label is calculated from recorded package usage within each registry, such as npm, PyPI, or RubyGems. The calculation selects the active packages that account for most of that registry's use.

Each package record gets its own flag, so one source repository may have a mix of marked and unmarked packages. The same project may appear in several registries and receive a separate result in each.

## How the calculation works

The calculation runs separately for each registry:

1. The registry must contain at least 4,000 packages. Smaller registries are skipped.
2. If the registry reports downloads, active packages are ordered from most to least downloaded. Hackage is the exception because its download figures are considered unreliable.
3. If downloads are unavailable, or the registry is Hackage, packages are ordered by the number of known public repositories that depend on them. This fallback requires the registry to have a positive dependent-repository count.
4. Starting with the most-used package, the counts are added together until they exceed 80% of the registry total. Every package in that group is marked `critical`, including the package that takes the total past 80%.

For example, if a registry records 1 million downloads, the target is 800,000. If its 25 most-downloaded active packages account for 805,000 downloads, those 25 packages are marked critical. The next package is not.

When both measures are available, downloads alone determine the result. Each registry is calculated independently.

The values come from code in this service: 4,000 packages and an 80% cutoff. Package registries do not supply a `critical` designation.

Before a registry is recalculated, its existing flags are cleared and the newly selected packages are marked. A registry is left unchanged when it contains fewer than 4,000 packages or has no usable measure.

## Why a package is marked or unmarked

The `critical` flag means that the package was active and fell within the leading group needed to exceed 80% of its registry's recorded downloads or dependent-repository use at the time of calculation. An unmarked package can result from any of these conditions:

- it falls below that registry's 80% cutoff, even if it still has substantial use;
- its status is not `active`;
- its registry contains fewer than 4,000 packages;
- its registry has no positive download or dependent-repository total;
- its usage data is missing or out of date;
- most of the project's recorded use belongs to a different package record from the same source repository; or
- the calculation has not run since its usage changed.

Project quality, security, maintenance, and importance to a particular organisation are outside this usage calculation. Download counts can include activity unrelated to production use. The dependent-repository count includes only repositories and dependency files known to repos.ecosyste.ms.

The flag changes when the `packages:update_critical` task runs. Individual package syncs leave it untouched. [`app.json`](../app.json) contains no schedule for the task, so this repository defines no regular refresh interval.

## Where the code is

- [`Registry#find_critical_packages`](../app/models/registry.rb#L650) contains the selection rules, including the 4,000-package minimum, metric choice, 80% cutoff, and database updates.
- [`packages:update_critical`](../lib/tasks/packages.rake#L215) is the task that runs the calculation for every registry.
- [`Package.critical`](../app/models/package.rb#L1088) is the query used to select packages whose flag is `true`.
- [`Registry#update_extra_counts`](../app/models/registry.rb#L396) calculates each registry's download and dependent-repository totals from its package records.
- [`Package#update_dependent_repos_count`](../app/models/package.rb#L686) gets a package's dependent-repository count from repos.ecosyste.ms.
- [`AddCriticalToPackages`](../db/migrate/20240225160813_add_critical_to_packages.rb) adds the nullable boolean column, and [`AddCriticalIndex`](../db/migrate/20240225175644_add_critical_index.rb) adds the partial index used for flagged packages.
