# Development

## Setup

First things first, you'll need to fork and clone the repository to your local machine.

`git clone https://github.com/ecosyste-ms/packages.git`

The project uses ruby on rails which have a number of system dependencies you'll need to install.

- [ruby](https://www.ruby-lang.org/en/documentation/installation/)
- [postgresql 14](https://www.postgresql.org/download/)
- [redis 6+](https://redis.io/download/)
- [node.js 16+](https://nodejs.org/en/download/)
- [wget](https://www.gnu.org/software/wget/)
- [maven](https://maven.apache.org/download.cgi) (`brew install maven` on macOS)

You will then need to set some configuration environment variables. Copy `env.example` to `.env.development` and customise the values to suit your local setup.

Once you've got all of those installed, from the root directory of the project run the following commands:

```
bin/setup
bin/dev
```

You can then load up [http://localhost:3000](http://localhost:3000) to access the service.

### Docker

Alternatively you can use the existing docker configuration files to run the app in a container.

Run this command from the root directory of the project to start the service.

`docker-compose up --build`

You can then load up [http://localhost:3000](http://localhost:3000) to access the service.

For access the rails console use the following command:

`docker-compose exec app rails console`

Running rake tasks in docker follows a similar pattern:

`docker-compose exec app rake packages:sync_recent`

## Importing data

The default set of supported registries are listed in [db/seeds.rb](db/seeds.rb) and can be automatically enabled with the following rake command:

`rake db:seed`

You can then start syncing package data for each registry with the following command, this will take a very long time:

`rake packages:sync_all`

To quickly load some data you can just load recent packages:

`rake packages:sync_recent`

## Tests

The applications tests can be found in [test](test) and use the testing framework [minitest](https://github.com/minitest/minitest).

You can run all the tests with:

`rails test`

## Rake tasks

The applications rake tasks can be found in [lib/tasks](lib/tasks).

You can list all of the available rake tasks with the following command:

`rake -T`

### Package corpus exports

`exports:corpus` creates an experimental package and project archive directly from the database. No input files or previous export are required. The separate search service builds its index from this data.

Run with the project's Ruby and Bundler:

```sh
bundle exec rake exports:corpus OUTPUT=/path/to/corpus.tar.gz
```

The default target is 300,000 packages. Set `TARGET` to change it, up to 1,000,000; a smaller candidate pool produces fewer records. `OUTPUT` defaults to a timestamped archive under `tmp/`. Existing files are never overwritten.

Selection uses downloads, package dependents, repository dependents, Docker downloads, stars and forks. Registries with at most `CENSUS_LIMIT=10000` cached packages get a bounded census. Larger registries contribute up to `HEAD_LIMIT=20000` records per signal through existing indexes, plus a seeded page sample for background coverage. The task checks actual census size before treating it as complete.

Registry allocations start with `REGISTRY_FLOOR=500`, then use square-root population weights, subject to candidate availability and `REGISTRY_CAP=60000`. Within each allocation, the target mix is 70% signal heads, 20% outer heads and 10% background, with deterministic fill when a category is too small. `SEED=20261031` controls sampling and ordering. The saved selection records make a run reusable; a seed alone cannot reproduce a changing database or page layout.

The 90%, 95% and 99% cutoffs describe the observed signal prefix when a query is truncated, not total registry usage. All cutoff ties within that prefix qualify, but the SQL limit can split a boundary tie. `selection.json` records truncation, observed totals and cutoffs. This bounded selection does not promise to reproduce a historical export's population.

Reads use transactions marked read-only, query-plan checks, a five-second statement timeout and a 500 ms lock timeout. Metadata is fetched by package ID in batches of 250; `BATCH_SIZE` accepts 1–1000. A query that exceeds the plan budget fails before fetching rows. The task reads no versions and makes no requests to registries or repository services. Separate batches can observe different database states. Run it as a one-off worker with disk space for the extracted output and final archive; project grouping retains a reduced package projection in memory.

Grouping uses stored repository IDs with matching URLs or aliases, guarded distribution-release coordinates, and corroborated names, descriptions, maintainers or distribution source metadata. Known collection repositories and labelled forks are excluded from repository grouping. Homepage-only matches and inferred Nix names do not establish identity. Repository-root groups remain provisional; the export is experimental. Every retained package has one assignment and keeps its original ID and service-generated PURL, including null PURLs. Packages marked `removed` are excluded.

The archive contains:

- `packages.ndjson.gz`: full exported package and repository metadata, usage signals and provenance, keyed by package ID. Missing values and numeric zeros remain distinct.
- `projects.ndjson.gz`: project names, descriptions, aliases, identifiers, filters, compact ranking signals and public package references.
- `corpus.json`: self-contained input for the search service, including project records and metadata. No matching baseline corpus is needed.
- `assignments.ndjson.gz` and `assignment-manifest.json`: memberships, checksums and the `repository`, `package`, `distribution_release` and `registry_mirror` reason enums.
- `selection.ndjson.gz`, `selection.json`, `identity.json`, `excluded.json` and `manifest.json`: selection decisions, grouping counts, exclusions, registry coverage, null counts, query limits and file checksums.

To reuse a fixed selection and grouping, set `ASSIGNMENTS=/path/to/assignment-manifest.json`. It identifies an assignments file by `assignments_file` and `assignments_sha256`, with `packages` and `projects` counts. Each assignment contains `package_id`, `project_id`, `previous_project_id`, `display_name` and `reason`. This mode refreshes those IDs from the database without regrouping them. Add `SOURCE=/path/to/packages.ndjson.gz` to replay a checksum-verified snapshot without querying the database. Removed packages and manifest `known_newly_removed_package_ids` are excluded in both modes; missing selected IDs cause an error.

Optional upload uses S3-compatible HTTPS PUT requests and requires no new gems or external upload tools. Set `UPLOAD=true`, `S3_ENDPOINT`, `S3_BUCKET`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. `AWS_SESSION_TOKEN` is supported. For R2, use the account's S3 API endpoint and the default `S3_REGION=auto`; for AWS S3, set its regional endpoint and region. See the [R2 S3 API documentation](https://developers.cloudflare.com/r2/api/s3/api/).

Objects use `package-corpus/<archive-sha256>.tar.gz`; set `S3_PREFIX` to choose another prefix. The task uploads no mutable latest pointer and does not change bucket visibility. An upload failure keeps the complete local file. Retry it without exporting again:

```sh
bundle exec rake exports:upload_corpus FILE=/path/to/corpus.tar.gz
```

The upload-only task uses the same storage environment variables. Uploads stream from disk, have connection and read/write timeouts, and support files up to 5 GB in a single request. Larger exports need multipart upload support.

## Background tasks

Background tasks are handled by [sidekiq](https://github.com/mperham/sidekiq), the workers live in [app/sidekiq](app/sidekiq/).

Sidekiq is automatically run by `bin/dev`, but if you need to run it manually, run the following command:

`bundle exec sidekiq`

You can also view the status of the workers and their queues from the web interface http://localhost:3000/sidekiq


## Adding an ecosystem

Ecosystem support live in [app/models/ecosystem](app/models/ecosystem), create a new file in that folder with the name of your ecosystem.

The basic class should look like the following:

```ruby
module Ecosystem
  class Myecosystem < Base

  end
end
```

Then you need to implement the various methods for fetching data from the registry, the `Cargo` class is a good example: [app/models/ecosystem/cargo.rb](app/models/ecosystem/cargo.rb).

See the `Base` class for the full list of methods and their default implementations: [app/models/ecosystem/base.rb](app/models/ecosystem/base.rb).

To test your ecosystem, add a new test file to [test/models/ecosystem/](test/models/ecosystem/) named `myecosystem_test.rb`, again the Cargo test class is a good example to follow: [test/models/ecosystem/cargo.rb](test/models/ecosystem/cargo.rb).

To avoid making actual http requests during testing, mock out the requests using the `stub_request` helper method, and download (via wget or similar) the file you wish to return into a new directory like [test/fixtures/files/myecosystem](test/fixtures/files/myecosystem).

```ruby
stub_request(:get, "https://crates.io/api/v1/crates?page=1&per_page=100")
      .to_return({ status: 200, body: file_fixture('cargo/crates') })
```

Also don't forget to add a new default registry for your ecosystem to [db/seeds.rb](db/seeds.rb).

## Deployment

A container-based deployment is highly recommended, we use [dokku.com](https://dokku.com/).
