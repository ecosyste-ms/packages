json.extract! version, :number, :published_at, :licenses, :integrity, :status

json.dependencies version.dependencies, partial: 'api/v1/dependencies/dependency', as: :dependency