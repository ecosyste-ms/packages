# Development

## Setup

First things first, you'll need to fork and clone the repository to your local machine.

`git clone https://github.com/ecosyste-ms/packages.git`

The project uses ruby on rails which have a number of system dependencies you'll need to install. 

- [ruby 3.3.4](https://www.ruby-lang.org/en/documentation/installation/)
- [postgresql 14](https://www.postgresql.org/download/)
- [redis 6+](https://redis.io/download/)
- [node.js 16+](https://nodejs.org/en/download/)

Once you've got all of those installed, from the root directory of the project run the following commands:

```
bundle install
bundle exec rake db:create
bundle exec rake db:migrate
rails server
```

You can then load up [http://localhost:3000](http://localhost:3000) to access the service.

### Docker

Alternatively you can use the existing docker configuration files to run the app in a container.

Run this command from the root directory of the project to start the service.

`docker-compose up --build`

You can then load up [http://localhost:3000](http://localhost:3000) to access the service.

For access the rails console use the following command:

`docker-compose exec app rails console`

Runing rake tasks in docker follows a similar pattern:

`docker-compose exec app rake packages:sync_recent`

## Importing data

The default set of supported registries are listed in [db/seeds.rb](db/seeds.rb) and can be automatically enabled with the following rake command:

`rake db:seed`

You can then start syncing package data for each registry with the following command, this will take a very long time:

`rake packages:sync_all_packages`

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

## Background tasks 

Background tasks are handled by [sidekiq](https://github.com/mperham/sidekiq), the workers live in [app/sidekiq](app/sidekiq/).

To process the tasks run the following command:

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