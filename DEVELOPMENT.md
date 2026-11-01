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

`exports:corpus` creates an experimental data archive for the separate search service. It reuses a supplied package selection and project assignments. It does not select a new population, recalculate project identity or build a search index.

Run with the project's Ruby and Bundler:

```sh
bundle exec rake exports:corpus ASSIGNMENTS=/path/to/assignment-manifest.json OUTPUT=/path/to/corpus.tar.gz
```

The input manifest identifies a compressed assignments file by `assignments_file` and `assignments_sha256`, with `packages` and `projects` counts. Each assignment contains `package_id`, `project_id`, `previous_project_id`, `display_name` and a `reason` enum. Supported reasons are `repository`, `package`, `distribution_release` and `registry_mirror`. Existing assignment exports can be used directly.

The task refreshes those package IDs from the database in read-only batches of 250. `BATCH_SIZE` accepts 1–1000. It inspects table statistics, indexes and query plans, rejects costly sequential scans and applies a five-second statement timeout. It reads no versions and makes no requests to registries or repository services. Batches can observe different database states; refreshed metadata does not revalidate the supplied grouping.

To replay a saved package snapshot without querying the database, add `SOURCE=/path/to/packages.ndjson.gz`. Its checksum must match the input manifest's `source_package_sha256`. Both modes exclude records with status `removed` and IDs in `known_newly_removed_package_ids`. Missing selected IDs cause an error. Existing output files are never overwritten.

The archive contains `packages.ndjson.gz` with full exported metadata, `projects.ndjson.gz` with group names and original package IDs, `assignments.ndjson.gz`, their manifests, and `excluded.json`. PURLs come from the package service in database mode and remain unchanged in snapshot mode. Nulls and numeric zeros stay distinct. The manifest records counts by registry, null counts, source checksums and file checksums. Existing search importers that require a baseline corpus still need that matching baseline separately.

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
